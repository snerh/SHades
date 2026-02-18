mutable struct MeasurementControl
    stop::Bool
    pause::Bool
end

MeasurementControl() = MeasurementControl(false, false)

mutable struct AppState
    params::Union{Nothing,ScanParams}
    spectrum::Union{Nothing,Spectrum}
    running::Bool
end

AppState() = AppState(nothing, nothing, false)
