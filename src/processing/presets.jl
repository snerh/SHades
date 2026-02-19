const _HAS_JSON_PRESET = let
    try
        @eval import JSON
        true
    catch
        false
    end
end

function _json_escape(s::AbstractString)
    buf = IOBuffer()
    for c in s
        if c == '"'
            print(buf, "\\\"")
        elseif c == '\\'
            print(buf, "\\\\")
        elseif c == '\n'
            print(buf, "\\n")
        elseif c == '\r'
            print(buf, "\\r")
        elseif c == '\t'
            print(buf, "\\t")
        else
            print(buf, c)
        end
    end
    return String(take!(buf))
end

function _json_dump(x)
    if x === nothing
        return "null"
    elseif x isa Bool
        return x ? "true" : "false"
    elseif x isa Number
        return string(x)
    elseif x isa AbstractString
        return "\"" * _json_escape(x) * "\""
    elseif x isa AbstractVector
        return "[" * join((_json_dump(v) for v in x), ",") * "]"
    elseif x isa Dict
        parts = String[]
        for (k, v) in x
            push!(parts, "\"" * _json_escape(String(k)) * "\":" * _json_dump(v))
        end
        return "{" * join(parts, ",") * "}"
    else
        return "\"" * _json_escape(string(x)) * "\""
    end
end

function _json_skip_ws(s::AbstractString, i::Int)
    n = lastindex(s)
    while i <= n && s[i] in (' ', '\n', '\r', '\t')
        i += 1
    end
    return i
end

function _json_parse_string(s::AbstractString, i::Int)
    i += 1
    buf = IOBuffer()
    n = lastindex(s)
    while i <= n
        c = s[i]
        if c == '"'
            return String(take!(buf)), i + 1
        elseif c == '\\'
            i += 1
            i > n && error("invalid escape")
            esc = s[i]
            if esc == '"'
                print(buf, '"')
            elseif esc == '\\'
                print(buf, '\\')
            elseif esc == 'n'
                print(buf, '\n')
            elseif esc == 'r'
                print(buf, '\r')
            elseif esc == 't'
                print(buf, '\t')
            else
                print(buf, esc)
            end
        else
            print(buf, c)
        end
        i += 1
    end
    error("unterminated string")
end

function _json_parse_number(s::AbstractString, i::Int)
    n = lastindex(s)
    j = i
    while j <= n && s[j] in ('+', '-', '.', 'e', 'E', '0':'9')
        j += 1
    end
    return parse(Float64, s[i:j-1]), j
end

function _json_parse_value(s::AbstractString, i::Int)
    i = _json_skip_ws(s, i)
    i > lastindex(s) && error("unexpected end")
    c = s[i]
    if c == '"'
        return _json_parse_string(s, i)
    elseif c == '{'
        i += 1
        obj = Dict{String,Any}()
        i = _json_skip_ws(s, i)
        if s[i] == '}'
            return obj, i + 1
        end
        while true
            key, i = _json_parse_string(s, i)
            i = _json_skip_ws(s, i)
            s[i] == ':' || error("expected ':'")
            i += 1
            val, i = _json_parse_value(s, i)
            obj[key] = val
            i = _json_skip_ws(s, i)
            if s[i] == '}'
                return obj, i + 1
            end
            s[i] == ',' || error("expected ','")
            i += 1
            i = _json_skip_ws(s, i)
        end
    elseif c == '['
        i += 1
        arr = Any[]
        i = _json_skip_ws(s, i)
        if s[i] == ']'
            return arr, i + 1
        end
        while true
            val, i = _json_parse_value(s, i)
            push!(arr, val)
            i = _json_skip_ws(s, i)
            if s[i] == ']'
                return arr, i + 1
            end
            s[i] == ',' || error("expected ','")
            i += 1
            i = _json_skip_ws(s, i)
        end
    elseif c == 'n' && startswith(s[i:end], "null")
        return nothing, i + 4
    elseif c == 't' && startswith(s[i:end], "true")
        return true, i + 4
    elseif c == 'f' && startswith(s[i:end], "false")
        return false, i + 5
    else
        return _json_parse_number(s, i)
    end
end

function _json_parse(s::AbstractString)
    val, i = _json_parse_value(s, firstindex(s))
    i = _json_skip_ws(s, i)
    i <= lastindex(s) && error("trailing data")
    return val
end

function _scanparams_to_dict(p::ScanParams)
    return Dict(
        "wavelengths" => p.wavelengths,
        "interaction" => p.interaction,
        "acq_time_s" => p.acq_time_s,
        "frames" => p.frames,
        "delay_s" => p.delay_s,
        "sol_divider" => p.sol_divider,
        "fixed_sol_wavelength" => p.fixed_sol_wavelength,
        "polarizer_deg" => p.polarizer_deg,
        "analyzer_deg" => p.analyzer_deg,
        "target_power" => p.target_power,
        "camera_temp_c" => p.camera_temp_c,
    )
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

function save_preset(path::AbstractString, params::ScanParams)
    d = _scanparams_to_dict(params)
    open(path, "w") do io
        _HAS_JSON_PRESET ? print(io, JSON.json(d)) : print(io, _json_dump(d))
    end
    return path
end

function load_preset(path::AbstractString)
    s = read(path, String)
    if _HAS_JSON_PRESET
        d = JSON.parse(s)
        return _dict_to_scanparams(Dict(d))
    end
    d = _json_parse(s)
    return _dict_to_scanparams(Dict{String,Any}(d))
end

function save_preset_state(path::AbstractString, state::Dict{String,Any})
    open(path, "w") do io
        _HAS_JSON_PRESET ? print(io, JSON.json(state)) : print(io, _json_dump(state))
    end
    return path
end

function load_preset_state(path::AbstractString)
    s = read(path, String)
    if _HAS_JSON_PRESET
        d = JSON.parse(s)
        return Dict{String,Any}(d)
    end
    d = _json_parse(s)
    return Dict{String,Any}(d)
end
