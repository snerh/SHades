module SHades

include("core/types.jl")
include("core/scan_axes.jl")
include("core/plan_builders.jl")
include("core/axis_spec_parser.jl")
include("model/interfaces.jl")
include("model/state.jl")
include("model/legacy_adapters.jl")
include("processing/dataset_io.jl")
include("controller/events.jl")
include("controller/measurement.jl")
include("controller/app_controller.jl")
include("controller/legacy_scan.jl")
include("controller/state_updates.jl")
include("view/console_view.jl")

export ScanParams, Spectrum
export ScanAxis, IndependentAxis, FixedAxis, DependentAxis, MultiDependentAxis, LoopAxis, ScanPlan
export axis_name, has_axis, legacy_axes_to_plan
export parse_axis_spec, build_scan_plan_from_text_specs, validate_scan_plan, validate_scan_text_specs
export DeviceBundle
export LegacyModules, LegacyCamera, LegacySpectrometer, LegacyLockin, LegacyEllipsometer, LegacyLaser
export load_legacy_modules!, build_legacy_bundle
export read_dat_file, load_dataset_dir, save_dat_file
export MeasurementControl, AppState, MeasurementSession
export MeasurementEvent, MeasurementStarted, StepResult, MeasurementFinished, MeasurementStopped, MeasurementError
export LegacyScanStarted, LegacyScanStep, LegacyScanFinished
export start_measurement, stop_measurement!, pause_measurement!, resume_measurement!
export start_legacy_scan
export apply_event!
export consume_events!
export load_gtk_view!
export GtkEventHandlers, consume_events_gtk!, bind_stop_button!, bind_pause_toggle!
export build_legacy_scan_plan
export start_gtk_legacy_app

const _gtk_view_loaded = Ref(false)

function load_gtk_view!()
    _gtk_view_loaded[] && return true
    include(joinpath(@__DIR__, "view", "gtk_view.jl"))
    include(joinpath(@__DIR__, "view", "gtk_app.jl"))
    _gtk_view_loaded[] = true
    return true
end

end
