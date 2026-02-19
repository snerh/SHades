function time_to_seconds(v; default::Float64=0.0)
    if v isa Tuple && length(v) == 2 && v[1] isa Number && v[2] isa AbstractString
        t0, unit = v
        scale =
            unit == "ns" ? 1e-9 :
            unit == "mks" ? 1e-6 :
            unit == "ms" ? 1e-3 :
            unit == "s" ? 1.0 :
            unit == "min" ? 60.0 :
            unit == "h" ? 3600.0 : NaN
        return isfinite(scale) ? Float64(t0) * scale : default
    elseif v isa Number
        return Float64(v)
    end
    return default
end
