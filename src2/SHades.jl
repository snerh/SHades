module SHades

include("domain.jl")
include("parameters.jl")
include("parameters_parser.jl")
include("state.jl")
include("device_manager.jl")
include("measurement.jl")
include("power.jl")
include("view/plot_render.jl")
include("processing.jl")
include("persistence.jl")
include("view/gtk_ui.jl")
include("reducer.jl")
include("devices/raw/raw_devices.jl")

using .Domain
using .Parameters
using .ParameterParser
using .State
using .DeviceManager
using .Measurement
using .Power
using .Processing
using .PlotRender
using .Reducer
using .GtkUI
using .RawDevices

export AppRuntime, run, run_real, stop!
export start_measurement!, stop_measurement!
#export start_power_stabilization!, stop_power_stabilization!, set_target_power!
export start_gtk_ui!
export save_plot_dat, save_plot_png
export save_spectrum_dat, save_spectrum_png

mutable struct AppRuntime
    state::AppState
    devices::Vector{RawDevice}
    device_hub::DeviceHub
    meas_cmd::Channel{MeasurementCommand}
    power_cmd::Channel{PowerCommand}
    ui_events::Channel{SystemEvent}
    ui_cmd::Channel{Nothing}
    tasks::Vector{Task}
end

function _start_runtime(devices::Vector{RawDevice}, device_hub::DeviceHub)

    state = AppState()

    meas_cmd = Channel{MeasurementCommand}(16)
    meas_events = Channel{SystemEvent}(32)

    power_cmd = Channel{PowerCommand}(16)
    power_events = Channel{SystemEvent}(32)

    ui_events = Channel{SystemEvent}(32)
    ui_cmd = Channel{Nothing}(16)

    name_by_channel = Dict{Channel{DeviceCommand},Symbol}()
    for (name, ch) in device_hub.devices
        name_by_channel[ch] = name
    end
    device_tasks = [@async device_loop(dev, get(name_by_channel, dev.device_cmd, :device)) for dev in devices]
    t_measure = @async measurement_loop(meas_cmd, meas_events, device_hub)
    t_power = @async power_loop(power_cmd, power_events, device_hub)

    # Центральный event bus
    event_bus = Channel{SystemEvent}(64)

    t_fwd_meas = @async forward(meas_events, event_bus)
    t_fwd_power = @async forward(power_events, event_bus)
    t_fwd_dev = [@async forward(dev.device_events, event_bus) for dev in devices]
    t_fwd_ui = @async forward(ui_events, event_bus)

    t_bus_closer = @async begin
        wait(t_fwd_meas)
        wait(t_fwd_power)
        for t in t_fwd_dev
            wait(t)
        end
        wait(t_fwd_ui)
        close(event_bus)
    end

    # UI event pump (Gtk должен вызывать reduce! из main thread)
    t_reducer = @async begin
        for ev in event_bus
            try
                reduce!(state, ev)
                _notify_ui!(ui_cmd)
            catch ex
                @warn "Reducer failed on event" event_type=string(typeof(ev)) exception=(ex, catch_backtrace())
            end
        end
    end

    tasks = Task[]
    append!(tasks, device_tasks)
    append!(tasks, Task[t_measure, t_power, t_fwd_meas, t_fwd_power])
    append!(tasks, t_fwd_dev)
    append!(tasks, Task[t_fwd_ui, t_bus_closer, t_reducer])
    return AppRuntime(state, devices, device_hub, meas_cmd, power_cmd, ui_events, ui_cmd, tasks)
end

function run()
    md = MockDevice()
    md_cam = MockCamDevice()
    device_hub = DeviceHub(Dict(
        :laser => md.device_cmd,
        :spec => md.device_cmd,
        :ell => md.device_cmd,
        :cam => md_cam.device_cmd,
        :pd => md.device_cmd,
    ))
    return _start_runtime(RawDevice[md, md_cam], device_hub)
end

function run_real(; kwargs...)
    real = RawDevices.build_real_devices(; kwargs...)
    return _start_runtime(real.devices, real.hub)
end

function forward(src, dst)
    for ev in src
        put!(dst, ev)
    end
end

function _put_if_open!(ch, cmd)
    if isopen(ch)
        try
            put!(ch, cmd)
        catch ex
            ex isa InvalidStateException || rethrow(ex)
        end
    end
    return nothing
end

function _close_if_open!(ch)
    isopen(ch) && close(ch)
    return nothing
end

function _notify_ui!(ui_cmd::Channel{Nothing})
    isopen(ui_cmd) || return nothing

    # Coalesce repaint signals so reducer never blocks.
    if !isready(ui_cmd)
        try
            put!(ui_cmd, nothing)
        catch ex
            ex isa InvalidStateException || rethrow(ex)
        end
    end
    return nothing
end

function stop!(runtime::AppRuntime; timeout_s::Float64=2.0)
    _put_if_open!(runtime.meas_cmd, ShutdownMeasurement())
    _put_if_open!(runtime.power_cmd, ShutdownPower())
    for dev in runtime.devices
        _put_if_open!(dev.device_cmd, ShutdownDevice())
    end

    _close_if_open!(runtime.meas_cmd)
    _close_if_open!(runtime.power_cmd)
    _close_if_open!(runtime.ui_events)
    for dev in runtime.devices
        _close_if_open!(dev.device_cmd)
    end

    for t in runtime.tasks
        timedwait(() -> istaskdone(t), timeout_s)
    end
    return runtime.state
end

start_measurement!(runtime::AppRuntime, params::ScanAxisSet; output_dir::Union{Nothing,String}=nothing) =
    put!(runtime.meas_cmd, StartMeasurement(params, output_dir))
stop_measurement!(runtime::AppRuntime) = put!(runtime.meas_cmd, StopMeasurement())

#start_power_stabilization!(runtime::AppRuntime) = put!(runtime.power_cmd, StartStab())
#stop_power_stabilization!(runtime::AppRuntime) = put!(runtime.power_cmd, StopStab())
#set_target_power!(runtime::AppRuntime, value::Real) = put!(runtime.power_cmd, SetTargetPower(Float64(value)))

start_gtk_ui!(runtime::AppRuntime; config_path::AbstractString="preset.json", title::AbstractString="SHades2.0") =
    GtkUI.start_gtk_ui!(
        runtime.state,
        runtime.ui_events,
        runtime.ui_cmd,
        runtime.meas_cmd,
        runtime.power_cmd,
        runtime.device_hub;
        config_path=config_path,
        title=title,
    )

end
