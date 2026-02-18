abstract type MeasurementEvent end

struct MeasurementStarted <: MeasurementEvent
    params::ScanParams
end

struct StepResult <: MeasurementEvent
    index::Int
    wavelength::Float64
    signal::Float64
    power::Float64
    raw::Vector{Float64}
    spectrum::Spectrum
end

struct MeasurementFinished <: MeasurementEvent
    spectrum::Spectrum
end

struct MeasurementStopped <: MeasurementEvent end

struct MeasurementError <: MeasurementEvent
    message::String
    ex::Exception
end

struct LegacyScanStarted <: MeasurementEvent
    output_dir::Union{Nothing,String}
end

struct LegacyScanStep <: MeasurementEvent
    index::Int
    file_stem::String
    params::Dict{Symbol,Any}
    raw::Vector{Float64}
    accumulated::Vector{Dict{Symbol,Any}}
end

struct LegacyScanFinished <: MeasurementEvent
    points::Int
end
