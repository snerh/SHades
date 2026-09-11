module TimeUtils

export parse_duration_seconds, try_parse_duration_seconds

const _NUM = raw"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?"
const _DURATION_RE = Regex("^\\s*($_NUM)\\s*(us|ms|s)?\\s*\$", "i")

function parse_duration_seconds(v)
    if v isa Number
        return Float64(v)
    elseif v isa AbstractString
        s = strip(String(v))
        isempty(s) && error("empty duration")
        m = match(_DURATION_RE, s)
        m === nothing && error("invalid duration '$s'")
        val = parse(Float64, m.captures[1])
        unit = m.captures[2]
        unit === nothing && return val
        unit_lc = lowercase(unit)
        unit_lc == "s" && return val
        unit_lc == "ms" && return val / 1000.0
        unit_lc == "us" && return val / 1_000_000.0
        error("unsupported duration unit '$unit'")
    elseif v isa Tuple && length(v) == 2
        return parse_duration_seconds("$(v[1]) $(v[2])")
    elseif v isa Vector{Any} && length(v) == 2
        return parse_duration_seconds("$(v[1]) $(v[2])")
    end
    error("unsupported duration value of type $(typeof(v))")
end

function try_parse_duration_seconds(v)
    try
        return parse_duration_seconds(v)
    catch
        return nothing
    end
end

end
