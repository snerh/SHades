module Persistence

using TOML
using ..Parameters

export save_config, load_config

function save_config(path, params::ScanAxisSet)

    dict = Dict{String,Any}()

    for (k,v) in axes_dict(params)
        dict[string(k)] = axis_to_dict(v)
    end

    open(path, "w") do io
        TOML.print(io, Dict("scan" => dict))
    end
end

function load_config(path)
    data = TOML.parsefile(path)
    specs = Dict{Symbol,ScanAxis}()

    for (k,tbl) in data["scan"]
        specs[Symbol(k)] = load_spec(Symbol(k), tbl)
    end

    return ScanAxisSet(collect(values(specs)))
end

function load_spec(name::Symbol, tbl)
    t = tbl["type"]
    if t == "fixed"
        FixedAxis(name, tbl["value"])
    elseif t == "list"
        IndependentAxis(name, tbl["values"])
    elseif t == "loop"
        LoopAxis(name=name, start=tbl["start"], step=tbl["step"], stop=tbl["stop"])
    else
        error("Unknown spec")
    end
end

axis_to_dict(p::FixedAxis) = Dict("type"=>"fixed","value"=>p.value)
axis_to_dict(p::IndependentAxis) =
    Dict("type"=>"list","values"=>p.values)
axis_to_dict(p::LoopAxis) =
    Dict("type"=>"loop","start"=>p.start,"stop"=>p.stop,"step"=>p.step)

end
