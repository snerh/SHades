# Core domain types used across model/controller/view layers.

Base.@kwdef struct ScanParams
    wavelengths::Vector{Float64}
    interaction::String = "SIG"
    acq_time_s::Float64 = 0.1
    frames::Int = 1
    delay_s::Float64 = 0.0
    sol_divider::Float64 = 2.0
    fixed_sol_wavelength::Union{Nothing,Float64} = nothing
    polarizer_deg::Float64 = 0.0
    analyzer_deg::Float64 = 0.0
    target_power::Union{Nothing,Float64} = nothing
    camera_temp_c::Union{Nothing,Float64} = nothing
end

struct Spectrum
    wavelength::Vector{Float64}
    signal::Vector{Float64}
end
