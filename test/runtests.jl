using Test

module SHadesLite

include(joinpath(@__DIR__, "..", "src2", "domain.jl"))
include(joinpath(@__DIR__, "..", "src2", "parameters.jl"))
include(joinpath(@__DIR__, "..", "src2", "parameters_parser.jl"))
include(joinpath(@__DIR__, "..", "src2", "state.jl"))
include(joinpath(@__DIR__, "..", "src2", "device_manager.jl"))
include(joinpath(@__DIR__, "..", "src2", "app_events.jl"))
include(joinpath(@__DIR__, "..", "src2", "time_utils.jl"))
include(joinpath(@__DIR__, "..", "src2", "dataset_io.jl"))
include(joinpath(@__DIR__, "..", "src2", "persistence.jl"))
include(joinpath(@__DIR__, "..", "src2", "app_logic.jl"))
include(joinpath(@__DIR__, "..", "src2", "app_controller.jl"))

end

using .SHadesLite.AppLogic
using .SHadesLite.AppController: Controller, load_presets!, save_presets!, append_preset!, delete_preset_at!, build_preset, publish_focus_params!, refresh_lifecycle!, connect_devices!, init_devices!, disconnect_devices!, toggle_power_stabilization!, select_output_dir!, start_scan!, start_focus!, stop_measurement!
using .SHadesLite.AppEvents: SyncRawParams, DirectoryLoaded, SetDeviceLifecycle
using .SHadesLite.DatasetIO
using .SHadesLite.DeviceManager: DeviceHub, DeviceCommand, ConnectDevice, InitDevice, DisconnectDevice, GetDeviceStatus
using .SHadesLite.Parameters
using .SHadesLite.ParameterParser
using .SHadesLite.Persistence: PresetSpec, ensure_required_params, load_presets, save_presets, next_preset_name
using .SHadesLite.State
using .SHadesLite.TimeUtils: parse_duration_seconds, try_parse_duration_seconds

function make_controller(;
    device_hub=DeviceHub(Dict{Symbol,Channel{DeviceCommand}}()),
    load_dir=dir -> Dict{Symbol,Any}[],
    load_presets=() -> PresetSpec[],
    save_presets=presets -> nothing,
)
    event_ch = Channel{Any}(32)
    meas_cmd = Channel{Any}(32)
    power_cmd = Channel{Any}(32)
    controller = Controller(
        event_ch,
        meas_cmd,
        power_cmd,
        device_hub,
        load_dir,
        load_presets,
        save_presets,
        (params, output_dir) -> (kind=:start_measurement, params=params, output_dir=output_dir),
        () -> (kind=:stop_measurement,),
        params -> (kind=:update_params, params=params),
        () -> (kind=:start_power,),
        () -> (kind=:stop_power,),
    )
    return controller, event_ch, meas_cmd, power_cmd
end

function make_device_hub()
    cmd = Channel{DeviceCommand}(32)
    connected = Ref(false)
    initialized = Ref(false)

    task = @async begin
        for req in cmd
            if req isa ConnectDevice
                connected[] = true
                put!(req.reply, :ok)
            elseif req isa InitDevice
                if connected[]
                    initialized[] = true
                    put!(req.reply, :ok)
                else
                    put!(req.reply, :not_connected)
                end
            elseif req isa DisconnectDevice
                connected[] = false
                initialized[] = false
                put!(req.reply, :ok)
            elseif req isa GetDeviceStatus
                put!(req.reply, (connected=connected[], initialized=initialized[], healthy=true))
            end
        end
    end

    return DeviceHub(Dict(:laser => cmd)), cmd, task
end

@testset "Axis parser" begin
    ax = parse_axis_spec(:wl, "500:2:504")
    @test ax isa RangeAxis
    @test collect(ax.range) == [500.0, 502.0, 504.0]

    dax = parse_axis_spec(:sol_wl, "=round(wl/40)*20")
    @test dax isa DependentAxis
    @test dax.depends_on == :wl
    @test dax.f(503.0) == 260.0
end

@testset "Raw param validation" begin
    errs = validate_raw_params([
        :wl => "500:2:504",
        :sol_wl => "=round(wl/40)*20",
        :inter => "\"SIG\"",
        :acq_time => "100 ms",
    ])
    @test isempty(errs)

    bad = validate_raw_params([
        :wl => "500:0:504",
        :sol_wl => "=",
        :acq_time => "100 parsecs",
    ])
    @test haskey(bad, :wl)
    @test haskey(bad, :sol_wl)
    @test haskey(bad, :acq_time)
end

@testset "Time utils" begin
    @test parse_duration_seconds("100 ms") == 0.1
    @test parse_duration_seconds("12 s") == 12.0
    @test parse_duration_seconds("250 us") == 0.00025
    @test parse_duration_seconds("2") == 2.0
    @test try_parse_duration_seconds("wat") === nothing
end

@testset "State sync and focus plan" begin
    state = AppState()
    sync_raw_params!(state, [
        :wl => "500:2:504",
        :sol_wl => "=round(wl/40)*20",
    ])

    @test length(state.measurement.raw_params) == 2
    @test state.measurement.scan_params !== nothing
    @test length(state.measurement.scan_params.axes) == 2

    set_raw_param!(state, :power, "1.0")
    @test any(p -> p.first == :power && p.second == "1.0", state.measurement.raw_params)
    @test state.measurement.scan_params !== nothing

    base_axes = copy(state.measurement.scan_params.axes)
    focus_axes = focus_scan_params(state.measurement.scan_params)
    @test length(state.measurement.scan_params.axes) == length(base_axes)
    @test count(ax -> ax isa LoopAxis && ax.name == :loop, focus_axes.axes) == 1
    @test any(ax -> ax isa LoopAxis && ax.name == :loop && ax.stop === nothing, focus_axes.axes)
end

@testset "Running state keeps current scan plan" begin
    state = AppState()
    sync_raw_params!(state, [:wl => "500:2:504"])
    original_plan = state.measurement.scan_params

    state.measurement_state = State.Running
    sync_raw_params!(state, [:wl => "broken"])

    @test state.measurement.scan_params === original_plan
    @test state.measurement.raw_params == [:wl => "broken"]
end

@testset "Fixed params for live focus updates" begin
    fixed = collect_fixed_params([
        :wl => "500",
        :inter => "\"SIG\"",
        :sol_wl => "=round(wl/40)*20",
    ])

    @test fixed[:wl] == 500.0
    @test fixed[:inter] == "SIG"
    @test !haskey(fixed, :sol_wl)
end

@testset "Controller config and directory loading" begin
    saved = Ref(PresetSpec[])
    controller, events, _, _ = make_controller(
        load_dir=dir -> [Dict{Symbol,Any}(:wl => 500.0, :sig => 1.0)],
        load_presets=() -> [PresetSpec("Preset 1", [:wl => "500"])],
        save_presets=presets -> (saved[] = copy(presets)),
    )

    presets = load_presets!(controller)
    @test length(presets) == 1
    @test presets[1].name == "Preset 1"
    @test presets[1].params == ensure_required_params([:wl => "500"])

    result = select_output_dir!(controller, "demo")
    @test result.ok
    ev = take!(events)
    @test ev isa DirectoryLoaded
    @test ev.dir == "demo"
    @test ev.points[1][:wl] == 500.0

    updated = append_preset!(controller, presets, build_preset(presets, [:wl => "510"]))
    @test length(updated) == 2
    @test saved[][2].name == "Preset 2"
    updated = delete_preset_at!(controller, updated, 1)
    @test length(updated) == 1
    @test saved[][1].name == "Preset 2"
end

@testset "Controller measurement commands" begin
    controller, events, meas_cmd, _ = make_controller()
    state = AppState()
    state.devices.connected = true
    state.devices.initialized = true
    state.session.config.dir = "out"

    raw = [
        :wl => "500:2:504",
        :sol_wl => "=round(wl/40)*20",
    ]

    result = start_scan!(controller, state, raw)
    @test result.ok
    @test result.started
    ev = take!(events)
    @test ev isa SyncRawParams
    @test ev.values == raw
    cmd = take!(meas_cmd)
    @test cmd.kind == :start_measurement
    @test cmd.output_dir == "out"
    @test cmd.params isa ScanAxisSet

    result = start_focus!(controller, state, raw)
    @test result.ok
    ev = take!(events)
    @test ev isa SyncRawParams
    cmd = take!(meas_cmd)
    @test cmd.kind == :start_measurement
    @test cmd.output_dir === nothing
    @test count(ax -> ax isa LoopAxis && ax.name == :loop, cmd.params.axes) == 1

    stop_measurement!(controller)
    @test take!(meas_cmd).kind == :stop_measurement
end

@testset "Controller lifecycle and power actions" begin
    hub, cmd_ch, task = make_device_hub()
    controller, events, _, power_cmd = make_controller(device_hub=hub)
    state = AppState()

    refresh_lifecycle!(controller)
    ev = take!(events)
    @test ev isa SetDeviceLifecycle
    @test !ev.connected
    @test !ev.initialized

    connect_devices!(controller)
    ev = take!(events)
    @test ev.connected
    @test !ev.initialized

    init_devices!(controller)
    ev = take!(events)
    @test ev.connected
    @test ev.initialized

    result = toggle_power_stabilization!(controller, state, true)
    @test !result.ok
    ev = take!(events)
    @test ev isa SetDeviceLifecycle
    @test occursin("power stabilization", ev.message)

    state.devices.connected = true
    state.devices.initialized = true
    result = toggle_power_stabilization!(controller, state, true)
    @test result.ok
    @test take!(power_cmd).kind == :start_power

    disconnect_devices!(controller)
    @test take!(power_cmd).kind == :stop_power
    ev = take!(events)
    @test !ev.connected
    @test !ev.initialized

    close(cmd_ch)
    wait(task)
end

@testset "Controller validation keeps commands pure" begin
    controller, events, meas_cmd, _ = make_controller()
    state = AppState()

    result = start_scan!(controller, state, [:wl => "broken"])
    @test !result.ok
    @test !result.started
    ev = take!(events)
    @test ev isa SyncRawParams
    ev = take!(events)
    @test ev isa SetDeviceLifecycle
    @test occursin("before scan", ev.message)
    @test !isready(meas_cmd)

    live = publish_focus_params!(controller, [
        :wl => "500",
        :inter => "\"SIG\"",
        :sol_wl => "=round(wl/40)*20",
    ])
    @test live.ok
    @test live.updated
    cmd = take!(meas_cmd)
    @test cmd.kind == :update_params
    @test cmd.params[:wl] == 500.0
    @test cmd.params[:inter] == "SIG"
    @test !haskey(cmd.params, :sol_wl)
end

@testset "Preset persistence and dataset IO" begin
    mktempdir() do d
        preset_path = joinpath(d, "presets.jsonl")
        presets = [
            PresetSpec("Preset 1", [:wl => "500", :acq_time => "100 ms"]),
            PresetSpec("Preset 2", [:wl => "600", :acq_time => "2 s"]),
        ]
        save_presets(preset_path, presets)
        loaded = load_presets(preset_path)
        @test length(loaded) == 2
        @test loaded[1].name == "Preset 1"
        @test loaded[1].params[1] == (:wl => "500")
        @test any(==(:acq_time => "100 ms"), loaded[1].params)
        @test next_preset_name(loaded) == "Preset 3"

        dat_path = joinpath(d, "sample.dat")
        point = Dict{Symbol,Any}(:wl => 500.0, :acq_time => "100 ms")
        data = [1.0, 3.0, 2.0]
        DatasetIO.save_raw_file(dat_path, point, data)
        point2, data2 = DatasetIO.load_raw_file(dat_path)
        @test point2[:wl] == 500.0
        @test point2[:acq_time] == "100 ms"
        @test data2 == data

        pts = DatasetIO.import_dir(d, (p, raw) -> Dict{Symbol,Any}(:wl => p[:wl], :sig => maximum(raw) - minimum(raw)))
        @test length(pts) == 1
        @test pts[1][:sig] == 2.0
        @test haskey(pts[1], :__file_path)
    end
end
