module Persistence

using JSON
using ..TimeUtils: try_parse_duration_seconds

export PresetSpec, default_preset, ensure_required_params
export load_presets, save_presets, next_preset_name

const _REQUIRED_DEFAULTS = Pair{Symbol,String}[
    :wl => "500:10:600",
    :sol_wl => "500",
    :inter => "IDL",
    :power => "1.0",
    :polarizer => "0",
    :analyzer => "0",
    :acq_time => "100 ms",
    :cam_temp => "-10",
    :frames => "2",
]

struct PresetSpec
    name::String
    params::Vector{Pair{Symbol,String}}
end

function ensure_required_params(raw_params::Vector{Pair{Symbol,String}})
    out = copy(raw_params)
    for (k, v) in _REQUIRED_DEFAULTS
        haskey = any(p -> p.first == k, out)
        haskey || push!(out, k => v)
    end
    idx = findfirst(p -> p.first == :acq_time, out)
    if idx !== nothing
        acq = strip(out[idx].second)
        if try_parse_duration_seconds(acq) !== nothing
            out[idx] = :acq_time => acq
        end
    end
    return out
end

default_preset(; name::AbstractString="Preset 1") = PresetSpec(String(name), copy(_REQUIRED_DEFAULTS))

function _params_to_json_ready(params::Vector{Pair{Symbol,String}})
    return [Dict(pair.first => pair.second) for pair in params]
end

function _dict_to_pair(x::Dict{Symbol,Any})
    length(x) == 1 || error("Expected dict with exactly one key, got $(length(x))")
    k = first(keys(x))
    return k => string(x[k])
end

function _parse_legacy_preset(parsed)
    raw_params = _dict_to_pair.(parsed)
    return [PresetSpec("Preset 1", ensure_required_params(raw_params))]
end

function _line_to_preset(line::AbstractString, idx::Int)
    parsed = JSON.parse(line, dicttype=Dict{Symbol,Any})
    name = string(get(parsed, :name, get(parsed, "name", "Preset $(idx)")))
    params_src = get(parsed, :params, get(parsed, "params", nothing))
    params_src === nothing && error("Preset line $(idx) does not contain params")
    params = _dict_to_pair.(params_src)
    return PresetSpec(name, ensure_required_params(params))
end

function load_presets(path)
    try
        s = read(path, String)
        isempty(strip(s)) && return PresetSpec[]
        stripped = strip(s)
        if startswith(stripped, "[")
            parsed = JSON.parse(stripped, dicttype=Dict{Symbol,Any})
            return _parse_legacy_preset(parsed)
        end

        presets = PresetSpec[]
        for (idx, line) in enumerate(split(s, '\n'))
            isempty(strip(line)) && continue
            push!(presets, _line_to_preset(line, idx))
        end
        return presets
    catch ex
        @warn "No preset file" exception=(ex, catch_backtrace())
        return [default_preset()]
    end
end

function save_presets(path, presets::Vector{PresetSpec})
    open(path, "w") do io
        for preset in presets
            payload = Dict(
                :name => preset.name,
                :params => _params_to_json_ready(ensure_required_params(preset.params)),
            )
            println(io, JSON.json(payload))
        end
    end
    return nothing
end

function next_preset_name(presets::Vector{PresetSpec})
    max_idx = 0
    for preset in presets
        m = match(r"^Preset\s+(\d+)$", preset.name)
        m === nothing && continue
        max_idx = max(max_idx, parse(Int, m.captures[1]))
    end
    return "Preset $(max_idx + 1)"
end

end
