using TOML

function _scanparams_to_dict(p::ScanParams)
    d = Dict{String,Any}(
        "wavelengths" => p.wavelengths,
        "interaction" => p.interaction,
        "acq_time_s" => p.acq_time_s,
        "frames" => p.frames,
        "delay_s" => p.delay_s,
        "sol_divider" => p.sol_divider,
        "polarizer_deg" => p.polarizer_deg,
        "analyzer_deg" => p.analyzer_deg,
    )

    p.fixed_sol_wavelength !== nothing && (d["fixed_sol_wavelength"] = p.fixed_sol_wavelength)
    p.target_power !== nothing && (d["target_power"] = p.target_power)
    p.camera_temp_c !== nothing && (d["camera_temp_c"] = p.camera_temp_c)

    return d
end

function _dict_to_scanparams(d::Dict)
    getv(k, default) = haskey(d, k) ? d[k] : default
    return ScanParams(
        wavelengths = Float64.(getv("wavelengths", Float64[])),
        interaction = String(getv("interaction", "SIG")),
        acq_time_s = Float64(getv("acq_time_s", 0.1)),
        frames = Int(round(getv("frames", 1))),
        delay_s = Float64(getv("delay_s", 0.0)),
        sol_divider = Float64(getv("sol_divider", 2.0)),
        fixed_sol_wavelength = getv("fixed_sol_wavelength", nothing),
        polarizer_deg = Float64(getv("polarizer_deg", 0.0)),
        analyzer_deg = Float64(getv("analyzer_deg", 0.0)),
        target_power = getv("target_power", nothing),
        camera_temp_c = getv("camera_temp_c", nothing),
    )
end

function _load_toml_dict(path::AbstractString)
    parsed = TOML.parsefile(path)
    return Dict{String,Any}(parsed)
end

function save_preset(path::AbstractString, params::ScanParams)
    d = _scanparams_to_dict(params)
    open(path, "w") do io
        TOML.print(io, d)
    end
    return path
end

function load_preset(path::AbstractString)
    d = _load_toml_dict(path)
    return _dict_to_scanparams(d)
end

function save_preset_state(path::AbstractString, state::Dict{String,Any})
    open(path, "w") do io
        TOML.print(io, state)
    end
    return path
end

function load_preset_state(path::AbstractString)
    return _load_toml_dict(path)
end
