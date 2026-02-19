mutable struct MeasurementControl
    stop::Bool
    pause::Bool
end

MeasurementControl() = MeasurementControl(false, false)

mutable struct AppState
    params::Union{Nothing,ScanParams}
    spectrum::Union{Nothing,Spectrum}
    running::Bool
    points::Vector{Dict{Symbol,Any}}
    last_raw::Vector{Float64}
    status::String
end

AppState() = AppState(nothing, nothing, false, Dict{Symbol,Any}[], Float64[], "Idle")
