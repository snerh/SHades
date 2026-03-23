module Processing

import Cairo

using ..Domain
using ..PlotRender: render_signal_plot!

export save_plot_dat, save_plot_png
export save_spectrum_dat, save_spectrum_png

@inline function _to_num(v)
    v isa Number && return Float64(v)
    try
        return parse(Float64, String(v))
    catch
        return NaN
    end
end

@inline function _point_axis(p::Point, axis::Symbol)::Float64
    return _to_num(get(p, axis, NaN))
end

function _maybe_log10(v::Vector{Float64}; enabled::Bool=false)
    !enabled && return copy(v)
    out = Float64[]
    for x in v
        if x > 0
            push!(out, log10(x))
        else
            push!(out, NaN)
        end
    end
    return out
end

function _header_string(params::AbstractDict)
    chunks = String[]
    for (k, v) in sort(collect(params); by=first)
        push!(chunks, "$(String(k))=$(repr(v))")
    end
    return join(chunks, ";")
end

function _collect_xy(points::Vector{Point}, xaxis::Symbol, yaxis::Symbol; log_scale::Bool=false)
    xs = Float64[]
    ys = Float64[]
    for p in points
        x = _point_axis(p, xaxis)
        y = _point_axis(p, yaxis)
        if isfinite(x) && isfinite(y)
            push!(xs, x)
            push!(ys, y)
        end
    end
    ydraw = _maybe_log10(ys; enabled=log_scale)
    keep = [isfinite(xs[i]) && isfinite(ydraw[i]) for i in eachindex(xs)]
    return xs[keep], ydraw[keep]
end

function _aggregate_xyz(points::Vector{Point}, xaxis::Symbol, yaxis::Symbol, zaxis::Symbol; log_scale::Bool=false)
    xs = Float64[]
    ys = Float64[]
    zs = Float64[]
    for p in points
        x = _point_axis(p, xaxis)
        y = _point_axis(p, yaxis)
        z = _point_axis(p, zaxis)
        if isfinite(x) && isfinite(y) && isfinite(z)
            push!(xs, x)
            push!(ys, y)
            push!(zs, z)
        end
    end
    zdraw = _maybe_log10(zs; enabled=log_scale)

    acc = Dict{Tuple{Float64,Float64},Tuple{Float64,Int}}()
    for i in eachindex(xs)
        isfinite(zdraw[i]) || continue
        k = (xs[i], ys[i])
        if haskey(acc, k)
            s, n = acc[k]
            acc[k] = (s + zdraw[i], n + 1)
        else
            acc[k] = (zdraw[i], 1)
        end
    end

    rows = NamedTuple{(:x, :y, :z, :n),Tuple{Float64,Float64,Float64,Int}}[]
    for ((x, y), (s, n)) in sort(collect(acc); by=x -> x[1])
        push!(rows, (x=x, y=y, z=s / n, n=n))
    end
    return rows
end

function save_plot_dat(
    path::AbstractString,
    points::Vector{Point};
    xaxis::Symbol=:wl,
    yaxis::Symbol=:sig,
    zaxis::Symbol=:sig,
    mode::Symbol=:line,
    log_scale::Bool=false,
    params::AbstractDict=Dict{Symbol,Any}(),
)
    mkpath(dirname(path))
    open(path, "w") do io
        full = Dict{Symbol,Any}(k => v for (k, v) in params)
        full[:mode] = mode
        full[:xaxis] = xaxis
        full[:yaxis] = yaxis
        full[:zaxis] = zaxis
        full[:log_scale] = log_scale

        if mode == :heatmap
            rows = _aggregate_xyz(points, xaxis, yaxis, zaxis; log_scale=log_scale)
            zcol = log_scale ? Symbol("log10_$(zaxis)") : zaxis
            full[:columns] = (xaxis, yaxis, zcol, :samples)
            println(io, "# ", _header_string(full))
            for r in rows
                println(io, "$(r.x) $(r.y) $(r.z) $(r.n)")
            end
        else
            xs, ys = _collect_xy(points, xaxis, yaxis; log_scale=log_scale)
            ycol = log_scale ? Symbol("log10_$(yaxis)") : yaxis
            full[:columns] = (xaxis, ycol)
            println(io, "# ", _header_string(full))
            n = min(length(xs), length(ys))
            for i in 1:n
                println(io, "$(xs[i]) $(ys[i])")
            end
        end
    end
    return path
end

function save_plot_png(
    path::AbstractString,
    points::Vector{Point};
    xaxis::Symbol=:wl,
    yaxis::Symbol=:sig,
    zaxis::Symbol=:sig,
    mode::Symbol=:line,
    log_scale::Bool=false,
    width::Int=900,
    height::Int=520,
    title::String="",
)
    out = endswith(lowercase(path), ".png") ? path : string(path, ".png")
    mkpath(dirname(out))

    surf = Cairo.CairoImageSurface(width, height, Cairo.FORMAT_ARGB32)
    ctx = Cairo.CairoContext(surf)
    render_signal_plot!(
        ctx,
        Float64(width),
        Float64(height),
        points;
        xaxis=xaxis,
        yaxis=yaxis,
        zaxis=zaxis,
        mode=mode,
        log_scale=log_scale,
        title=title,
    )
    Cairo.write_to_png(surf, out)
    try
        Cairo.finish(surf)
    catch
    end
    return out
end

function _spec_to_points(spec::Spectrum)
    n = min(length(spec.wavelength), length(spec.signal))
    return [Dict{Symbol,Any}(:wl => spec.wavelength[i], :sig => spec.signal[i]) for i in 1:n]
end

function save_spectrum_dat(path::AbstractString, spec::Spectrum; params::AbstractDict=Dict{Symbol,Any}())
    pts = _spec_to_points(spec)
    return save_plot_dat(path, pts; xaxis=:wl, yaxis=:sig, mode=:line, log_scale=false, params=params)
end

function save_spectrum_png(path::AbstractString, spec::Spectrum; width::Int=900, height::Int=520, title::String="spectrum")
    pts = _spec_to_points(spec)
    return save_plot_png(path, pts; xaxis=:wl, yaxis=:sig, mode=:line, log_scale=false, width=width, height=height, title=title)
end

end
