using DelimitedFiles
using Statistics

const _HAS_JSON = let
    try
        @eval import JSON
        true
    catch
        false
    end
end

_to_symbol_dict(d::Dict) = Dict{Symbol,Any}(Symbol(k) => v for (k, v) in d)

function _parse_literal(ex)
    if ex isa Number || ex isa String || ex isa Symbol
        return ex
    end
    if ex isa Expr && ex.head == :tuple
        return tuple((_parse_literal(arg) for arg in ex.args)...)
    end
    return string(ex)
end

function _encode_header(params::Dict{Symbol,Any})
    if _HAS_JSON
        return JSON.json(Dict(String(k) => v for (k, v) in params))
    end
    chunks = String[]
    for (k, v) in sort(collect(params); by=first)
        push!(chunks, "$(String(k))=$(repr(v))")
    end
    return join(chunks, ";")
end

function _decode_header(s::AbstractString)
    if isempty(s)
        return Dict{Symbol,Any}()
    end
    if _HAS_JSON
        try
            return _to_symbol_dict(JSON.parse(s))
        catch
        end
    end
    out = Dict{Symbol,Any}()
    for chunk in split(s, ';')
        kv = split(chunk, '='; limit=2)
        length(kv) == 2 || continue
        key = Symbol(strip(kv[1]))
        val_src = strip(kv[2])
        try
            out[key] = _parse_literal(Meta.parse(val_src))
        catch
            out[key] = val_src
        end
    end
    isempty(out) && (out[:header_raw] = String(s))
    return out
end

function _time_to_seconds(v)
    if v isa Tuple && length(v) == 2 && v[1] isa Number && v[2] isa AbstractString
        t0, unit = v
        return Float64(t0) * (
            unit == "ns" ? 1e-9 :
            unit == "mks" ? 1e-6 :
            unit == "ms" ? 1e-3 :
            unit == "s" ? 1.0 :
            unit == "min" ? 60.0 :
            unit == "h" ? 3600.0 : 1.0)
    elseif v isa Number
        return Float64(v)
    end
    return 0.0
end

function read_dat_file(path::AbstractString)
    io = open(path, "r")
    try
        header_line = readline(io)
        header_payload = startswith(header_line, "#") ? strip(header_line[2:end]) : ""
        params = _decode_header(header_payload)

        data = Float64.(vec(DelimitedFiles.readdlm(io)))

        if !haskey(params, :time_s)
            if haskey(params, :acq_time)
                params[:time_s] = _time_to_seconds(params[:acq_time])
            elseif haskey(params, :time)
                params[:time_s] = _time_to_seconds(params[:time])
            end
        end
        if !haskey(params, :sig) && !isempty(data)
            params[:sig] = maximum(data) - median(data)
        end
        if !haskey(params, :wl) && haskey(params, :wavelength)
            params[:wl] = params[:wavelength]
        end

        return params, data
    finally
        close(io)
    end
end

function load_dataset_dir(dir::AbstractString)
    files = sort(readdir(dir; join=true))
    dat_files = filter(f -> endswith(lowercase(f), ".dat"), files)
    records = map(read_dat_file, dat_files)

    sort!(records; by=x -> get(x[1], :wl, typemax(Float64)))
    return records
end

function save_dat_file(path::AbstractString, params::Dict{Symbol,Any}, data::AbstractVector{<:Real})
    open(path, "w") do io
        println(io, "# ", _encode_header(params))
        for y in data
            println(io, y)
        end
    end
    return path
end
