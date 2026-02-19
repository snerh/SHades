mutable struct MeasurementControl
    stop::Bool
    pause::Bool
end

MeasurementControl() = MeasurementControl(false, false)

mutable struct AppState
    params::Union{Nothing,ScanParams}
    spectrum::Union{Nothing,Spectrum}
    running::Bool
    points::Vector{ScanPoint}
    last_raw::Vector{Float64}
    status::String
    progress_step::Int
    progress_total::Union{Nothing,Int}
    current_wl::Union{Nothing,Float64}
    started_at::Union{Nothing,Float64}
end

AppState() = AppState(nothing, nothing, false, ScanPoint[], Float64[], "Idle", 0, nothing, nothing, nothing)
