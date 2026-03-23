module Persistence

using JSON
using ..Parameters

export save_config, load_config

const _REQUIRED_DEFAULTS = Pair{Symbol,String}[
    :wl => "500:10:600",
    :sol_wl => "500",
    :inter => "IDL",
    :power => "1.0",
    :polarizer => "0",
    :analyzer => "0",
    :acq_time => "100",
    :cam_temp => "-10",
    :frames => "2",
]

function _ensure_required_params(raw_params::Vector{Pair{Symbol,String}})
    out = copy(raw_params)
    for (k, v) in _REQUIRED_DEFAULTS
        haskey = any(p -> p.first == k, out)
        haskey || push!(out, k => v)
    end
    return out
end

function save_config(path, params::Vector{Pair{Symbol, String}})
    json_ready = [Dict(p.first => p.second) for p in params]
    json = JSON.json(json_ready)
    open(path, "w") do io
        write(io, json)
    end
    return nothing
end

function _dict_to_pair(x::Dict{Symbol,Any})
    length(x) == 1 || error("Expected dict with exactly one key, got $(length(x))")
    k = first(keys(x))
    return k => string(x[k])
end

function load_config(path)
    try
        s = read(path, String)
        parsed = JSON.parse(s, dicttype=Dict{Symbol,Any})
        raw_params = _dict_to_pair.(parsed)
        _ensure_required_params(raw_params)
    catch ex
        @warn "No backup file" exception=(ex, catch_backtrace())
        copy(_REQUIRED_DEFAULTS)
    end
end

end
