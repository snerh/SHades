module Persistence

using JSON
using ..Parameters

export save_config, load_config

function save_config(path, params::Vector{Pair{Symbol, String}})
    println("========Saving params=============")
    println(params)
    json = JSON.json(params)
    open(path, "w") do io
        write(io, json)
    end
    return nothing
end

function load_config(path)
    try
        s = read(path, String)
        println(s)
        raw_params = JSON.parse(s,Vector{Pair{Symbol,String}})
        println(raw_params)
        raw_params
    catch
        @warn "No backup file"
        [
            :wl => "500:10:600",
            :sol_wl => "500",
            :inter => "IDL",
            :polarizer => "0",
            :analyzer => "0",
            :acq_time => "100",
            :cam_temp => "-10",
            :frames => "2",
        ]
    end
end

end
