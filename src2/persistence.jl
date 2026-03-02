module Persistence

using JSON
using ..Parameters

export save_config, load_config

function save_config(path, params::Vector{Pair{Symbol, String}})
    json = JSON.json(params)
    #Log.printlog(json)
    io = open(path, "w")
    write(io, json)
    #Log.printlog("writing state file")
    close(io)
end
function load_config(path)
    try        
        io = open(path,"r")
        s = readline(io)
        dicts = JSON.Parser.parse(s,dicttype=Dict{Symbol,Any})
        println(dicts)
        function dict_to_pair(d)
            k = collect(keys(d))[1]
            k => d[k]
        end
        raw_params = map(dict_to_pair, dicts)
        println(raw_params)
		#Log.printlog("\n=========text_state=============")
		#Log.printlog(raw_params)
        close(io)
        raw_param
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
