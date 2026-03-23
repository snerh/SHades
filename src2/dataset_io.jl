module DatasetIO

using JSON
using ..Domain

export save_raw_file, load_raw_file, import_dir

function save_raw_file(path::AbstractString, params::Dict{Symbol,Any}, data::Vector{Float64})
    json = JSON.json(params)
    open(path, "w") do io
        println(io, "# ", json)
        for y in data
            println(io, y)
        end
    end
    return path
end

function load_raw_file(path::AbstractString)
    data = Float64[]
    open(path, "r") do io
        s = readline(io)
        header = s[2:end]
        point = Dict(JSON.parse(header, dicttype=Dict{Symbol,Any}))
        for line in eachline(io)
            s = strip(line)
            isempty(s) && continue
            startswith(s, "#") && continue
            try
                push!(data, parse(Float64, s))
            catch
            end
        end
        return point, data
    end
end

function import_dir(path::AbstractString, point_builder::Function)
    files = readdir(path, join=true, sort=true)
    dat_files = filter(file -> endswith(lowercase(file), ".dat"), files)
    isempty(dat_files) && return Point[]

    return map(dat_files) do file
        point, data = load_raw_file(file)
        new_p = point_builder(point, data)
        new_p[:__file_path] = file
        new_p
    end
end

end
