module Persistence

using TOML
using ..Parameters

export save_config, load_config

function save_config(path, params::ScanAxisSet)

    dict = Dict{String,Any}()

    for (k,v) in params.params
        dict[string(k)] = spec_to_dict(v)
    end

    open(path, "w") do io
        TOML.print(io, Dict("scan" => dict))
    end
end

function load_config(path)
    data = TOML.parsefile(path)
    specs = Dict{Symbol,ScanAxis}()

    for (k,tbl) in data["scan"]
        specs[Symbol(k)] = load_spec(tbl)
    end

    return ParameterSet(specs)
end

function load_spec(tbl)
    t = tbl["type"]
    if t == "fixed"
        Fixed(tbl["value"])
    elseif t == "linear"
        LinearRange(tbl["start"], tbl["stop"], tbl["step"])
    elseif t == "list"
        ValueList(tbl["values"])
    else
        error("Unknown spec")
    end
end

spec_to_dict(p::Fixed) = Dict("type"=>"fixed","value"=>p.value)
spec_to_dict(p::LinearRange) =
    Dict("type"=>"linear","start"=>p.start,"stop"=>p.stop,"step"=>p.step)
spec_to_dict(p::ValueList) =
    Dict("type"=>"list","values"=>p.values)

end