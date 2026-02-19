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

Base.@kwdef struct ScanPoint
    wl::Float64 = NaN
    sol_wl::Float64 = NaN
    polarizer::Float64 = NaN
    analyzer::Float64 = NaN
    power::Float64 = NaN
    loop::Float64 = NaN
    real_power::Float64 = NaN
    sig::Float64 = NaN
    time_s::Float64 = NaN
end

@inline function _scanpoint_num(v, default::Float64=NaN)
    v isa Number && return Float64(v)
    try
        return parse(Float64, string(v))
    catch
        return default
    end
end

function scan_point_from_params(params::Dict{Symbol,Any})
    return ScanPoint(
        wl = _scanpoint_num(get(params, :wl, NaN)),
        sol_wl = _scanpoint_num(get(params, :sol_wl, NaN)),
        polarizer = _scanpoint_num(get(params, :polarizer, NaN)),
        analyzer = _scanpoint_num(get(params, :analyzer, NaN)),
        power = _scanpoint_num(get(params, :power, NaN)),
        loop = _scanpoint_num(get(params, :loop, NaN)),
        real_power = _scanpoint_num(get(params, :real_power, NaN)),
        sig = _scanpoint_num(get(params, :sig, NaN)),
        time_s = _scanpoint_num(get(params, :time_s, NaN)),
    )
end

function scan_point_axis(p::ScanPoint, axis::Symbol)
    if axis == :wl
        return p.wl
    elseif axis == :sol_wl
        return p.sol_wl
    elseif axis == :polarizer
        return p.polarizer
    elseif axis == :analyzer
        return p.analyzer
    elseif axis == :power
        return p.power
    elseif axis == :loop
        return p.loop
    elseif axis == :real_power
        return p.real_power
    elseif axis == :sig
        return p.sig
    elseif axis == :time_s
        return p.time_s
    end
    return NaN
end

function scan_point_to_dict(p::ScanPoint)
    d = Dict{Symbol,Any}()
    isfinite(p.wl) && (d[:wl] = p.wl)
    isfinite(p.sol_wl) && (d[:sol_wl] = p.sol_wl)
    isfinite(p.polarizer) && (d[:polarizer] = p.polarizer)
    isfinite(p.analyzer) && (d[:analyzer] = p.analyzer)
    isfinite(p.power) && (d[:power] = p.power)
    isfinite(p.loop) && (d[:loop] = p.loop)
    isfinite(p.real_power) && (d[:real_power] = p.real_power)
    isfinite(p.sig) && (d[:sig] = p.sig)
    isfinite(p.time_s) && (d[:time_s] = p.time_s)
    return d
end
