module DatasetIO

using JSON
using DataFrames
import CSV
using ..Domain

export save_raw_file, load_raw_file, import_dir

function save_raw_file(path::AbstractString, params::Dict{Symbol,Any}, df::DataFrame)
    json = JSON.json(params)
    #println("Writing to file (",path,")")
    open(path, "w") do io
        println(io, "# ", json)
        CSV.write(io, df; header=false, delim=' ', append = true)
    end
    return path
end

function load_raw_file(path::AbstractString)
    data = Float64[]
    open(path, "r") do io
        s = readline(io)
        header = s[2:end]
        point = Dict(JSON.parse(header, dicttype=Dict{Symbol,Any}))

        df = CSV.read(path, DataFrame; comment="#", header=false, )
        if ncol(df) == 1
            rename!(df, [1 => :cam_int])
        elseif ncol(df) == 2
            rename!(df, [1 => :cam_wl, 2 => :cam_int])
        end
            
        return point, df
    end
end

function import_dir(path::AbstractString, point_builder::Function)
    files = readdir(path, join=true, sort=true)
    dat_files = filter(file -> endswith(lowercase(file), ".dat"), files)
    isempty(dat_files) && return Point[]

    return map(dat_files) do file
        point, df = load_raw_file(file)
        new_p = point_builder(point, df)
        new_p[:__file_path] = file
        new_p
    end
end

end
