module AppController

using ..State
using ..DeviceManager
using ..AppEvents
using ..AppLogic
using ..ParameterParser: build_scan_axis_set_from_text_specs
using ..Persistence: PresetSpec, ensure_required_params, next_preset_name

export Controller
export load_presets!, save_presets!, append_preset!, delete_preset_at!
export build_preset
export dispatch_raw_params!, validation_errors, publish_focus_params!
export refresh_lifecycle!, connect_devices!, init_devices!, disconnect_devices!
export toggle_power_stabilization!, select_output_dir!, start_scan!, start_focus!, stop_measurement!

struct Controller
    event_ch
    meas_cmd
    power_cmd
    device_hub::DeviceHub
    load_dir::Function
    load_presets::Function
    save_presets::Function
    mk_start_measurement::Function
    mk_stop_measurement::Function
    mk_update_params::Function
    mk_start_power::Function
    mk_stop_power::Function
end

function dispatch_raw_params!(controller::Controller, raw_params::Vector{Pair{Symbol,String}})
    put!(controller.event_ch, SyncRawParams(copy(raw_params)))
    return nothing
end

validation_errors(raw_params::Vector{Pair{Symbol,String}}) = AppLogic.validate_raw_params(raw_params)

function load_presets!(controller::Controller)
    presets = controller.load_presets()
    return [PresetSpec(preset.name, ensure_required_params(preset.params)) for preset in presets]
end

function save_presets!(controller::Controller, presets)
    normalized = [PresetSpec(preset.name, ensure_required_params(preset.params)) for preset in presets]
    controller.save_presets(normalized)
    return nothing
end

function append_preset!(controller::Controller, presets, preset)
    updated = copy(presets)
    push!(updated, preset)
    save_presets!(controller, updated)
    return updated
end

function delete_preset_at!(controller::Controller, presets, idx::Int)
    updated = copy(presets)
    deleteat!(updated, idx)
    save_presets!(controller, updated)
    return updated
end

function build_preset(presets, raw_params::Vector{Pair{Symbol,String}}; name::Union{Nothing,AbstractString}=nothing)
    preset_name = name === nothing ? next_preset_name(presets) : String(name)
    return PresetSpec(preset_name, ensure_required_params(raw_params))
end

function publish_focus_params!(controller::Controller, raw_params::Vector{Pair{Symbol,String}})
    live = AppLogic.collect_fixed_params(raw_params)
    isempty(live) && return (ok=true, updated=false, errors=Dict{Symbol,String}())
    put!(controller.meas_cmd, controller.mk_update_params(live))
    return (ok=true, updated=true, errors=Dict{Symbol,String}())
end

function _emit_lifecycle!(controller::Controller, connected::Bool, initialized::Bool, message::AbstractString)
    put!(controller.event_ch, SetDeviceLifecycle(connected, initialized, String(message)))
    return nothing
end

function _emit_init_required!(controller::Controller, state::AppState, label::AbstractString)
    _emit_lifecycle!(controller, state.devices.connected, state.devices.initialized, "devices: init required before $(label)")
    return (ok=false, errors=Dict{Symbol,String}(), started=false)
end

function refresh_lifecycle!(controller::Controller)
    try
        status_map = devices_status(controller.device_hub)
        connected = !isempty(status_map) && all(v -> v.connected, values(status_map))
        initialized = !isempty(status_map) && all(v -> v.connected && v.initialized && v.healthy, values(status_map))
        msg =
            initialized ? "devices: initialized" :
            connected ? "devices: connected (not initialized)" :
            "devices: disconnected"
        _emit_lifecycle!(controller, connected, initialized, msg)
        return (ok=true, connected=connected, initialized=initialized)
    catch ex
        _emit_lifecycle!(controller, false, false, "devices: lifecycle error")
        @warn "Failed to read device lifecycle status" exception=(ex, catch_backtrace())
        return (ok=false, error=ex)
    end
end

function connect_devices!(controller::Controller)
    try
        DeviceManager.connect_devices!(controller.device_hub)
        return refresh_lifecycle!(controller)
    catch ex
        @warn "Connect failed" exception=(ex, catch_backtrace())
        return (ok=false, error=ex)
    end
end

function init_devices!(controller::Controller)
    try
        DeviceManager.init_devices!(controller.device_hub)
        return refresh_lifecycle!(controller)
    catch ex
        @warn "Init failed" exception=(ex, catch_backtrace())
        return (ok=false, error=ex)
    end
end

function disconnect_devices!(controller::Controller)
    try
        put!(controller.power_cmd, controller.mk_stop_power())
        DeviceManager.disconnect_devices!(controller.device_hub)
        return refresh_lifecycle!(controller)
    catch ex
        @warn "Disconnect failed" exception=(ex, catch_backtrace())
        return (ok=false, error=ex)
    end
end

function toggle_power_stabilization!(controller::Controller, state::AppState, enabled::Bool)
    if !state.devices.initialized
        enabled && _emit_init_required!(controller, state, "power stabilization")
        return (ok=false, enabled=false)
    end
    put!(controller.power_cmd, enabled ? controller.mk_start_power() : controller.mk_stop_power())
    return (ok=true, enabled=enabled)
end

function select_output_dir!(controller::Controller, dir::AbstractString)
    dir_str = String(dir)
    try
        points = controller.load_dir(dir_str)
        put!(controller.event_ch, DirectoryLoaded(dir_str, points))
        return (ok=true, points=points)
    catch ex
        @warn "Failed to load output directory" dir=dir_str exception=(ex, catch_backtrace())
        return (ok=false, error=ex)
    end
end

function _prepare_scan_request(raw_params::Vector{Pair{Symbol,String}}; focus::Bool=false)
    errs = validation_errors(raw_params)
    isempty(errs) || return (ok=false, errors=errs, scan_params=nothing, started=false)

    scan_params = try
        build_scan_axis_set_from_text_specs(raw_params)
    catch ex
        return (ok=false, errors=Dict{Symbol,String}(:scan => sprint(showerror, ex)), scan_params=nothing, started=false)
    end

    focus && (scan_params = AppLogic.focus_scan_params(scan_params))
    return (ok=true, errors=Dict{Symbol,String}(), scan_params=scan_params, started=false)
end

function start_scan!(controller::Controller, state::AppState, raw_params::Vector{Pair{Symbol,String}})
    dispatch_raw_params!(controller, raw_params)
    !state.devices.initialized && return _emit_init_required!(controller, state, "scan")

    req = _prepare_scan_request(raw_params; focus=false)
    req.ok || return req

    out_dir = strip(state.session.config.dir)
    put!(controller.meas_cmd, controller.mk_start_measurement(req.scan_params, isempty(out_dir) ? nothing : out_dir))
    return (ok=true, errors=Dict{Symbol,String}(), scan_params=req.scan_params, started=true)
end

function start_focus!(controller::Controller, state::AppState, raw_params::Vector{Pair{Symbol,String}})
    dispatch_raw_params!(controller, raw_params)
    !state.devices.initialized && return _emit_init_required!(controller, state, "focus")

    req = _prepare_scan_request(raw_params; focus=true)
    req.ok || return req

    put!(controller.meas_cmd, controller.mk_start_measurement(req.scan_params, nothing))
    return (ok=true, errors=Dict{Symbol,String}(), scan_params=req.scan_params, started=true)
end

function stop_measurement!(controller::Controller)
    put!(controller.meas_cmd, controller.mk_stop_measurement())
    return nothing
end

end
