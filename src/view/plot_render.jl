module PlotRender

import Cairo
import DataFrames as DF
import Printf
using Memoize

include("../devices/raw/Log.jl")

using ..Domain

export DEFAULT_AXIS_CHOICES, render_signal_plot!

const DEFAULT_AXIS_CHOICES = Symbol[
    :wl, :sol_wl, :polarizer, :analyzer, :power, :loop, :real_power, :sig, :time_s,
]

"""
Fields which describe acquisition/file metadata rather than an independent
scan coordinate. They are never used for automatic series splitting.
"""

const DEFAULT_SERIES_EXCLUDE = Set{Symbol}([
    :real_power,
    :__file_path,
    :sig,
    :calibr_fun
])

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

"""
Convert Vector{Point} to a DataFrame.

A Point is expected to be Dict{Symbol,Any}. Missing keys are represented by
`missing`, so heterogeneous Point dictionaries can still be represented by
one table.
"""
function _points_to_dataframe(points::Vector{Point})
    if isempty(points)
        return DF.DataFrame()
    end
    
    # 1. Собираем уникальные ключи со всех точек
    allkeys = Set{Symbol}()
    for p in points
        union!(allkeys, keys(p))
    end
    
    # 2. Инициализируем колонки с нужным типом (избегаем Any, если возможно)
    cols = Dict{Symbol, Vector}()
    for k in allkeys
        # Заранее выделяем вектор нужной длины
        cols[k] = [get(p, k, missing) for p in points]
    end
    
    return DF.DataFrame(cols)
end

"""
Return columns which actually vary in the current dataset and therefore can
represent scan dimensions.

xaxis, yaxis and explicitly excluded fields are never considered.
"""
function _series_columns(
    df::DF.DataFrame,
    xaxis::Symbol,
    yaxis::Symbol;
    exclude::AbstractSet{Symbol}=DEFAULT_SERIES_EXCLUDE,
)
    # Предполагаем, что cols берется из имен колонок df
    cols = propertynames(df) 
    result = Symbol[]
    subdf = DF.groupby(df,xaxis)[1]
    for c in cols
        c in exclude && continue
        
        # Передаем только нужный столбец в groupby, а не весь df
        gd = DF.groupby(subdf, c)
        if !isempty(gd)
            if DF.size(gd[1])[1] != DF.size(subdf)[1]
                push!(result, c)
            end 
        subdf = gd[1]; end
    end
    return result
end

function _series_columns_old(
    df::DF.DataFrame,
    xaxis::Symbol,
    yaxis::Symbol;
    exclude::AbstractSet{Symbol}=DEFAULT_SERIES_EXCLUDE,
)
    
    subdf = DF.groupby(df,collect(Set([xaxis])))[1]
    #println("Before aux subdf = ",subdf)
    function aux(df, cols, result)
        #Log.printlog("DF=",df)
        #Log.printlog("cols=",cols)
        #Log.printlog("result=",result)
        if cols == [] || DF.size(df)[1] == 1
            #Log.printlog("Cols = [] or size ==1. Exit")
            return result
        end
        c = cols[1]
        if c in exclude
            #Log.printlog("Excluded col, continue")
            aux(df, cols[2:end], result)
        else
            
            subdf = DF.groupby(df,c)[1]
            if  DF.size(subdf)[1] == DF.size(df)[1]
                #Log.printlog("Equil size, continue. subdf = ", subdf)
                aux(subdf, cols[2:end],result)
            else
                #Log.printlog("continue. subdf = ", subdf,"result=",result)
                push!(result,c)
                aux(subdf, cols[2:end],result)
            end
        end
    end

    result = aux(subdf,propertynames(df),Symbol[])
    #println(result)
    #Log.printlog("Axis for lines", result)
    sort!(result)
    return result
end

"""
Create a stable textual representation of a series parameter value.
"""
function _series_value_string(v)
    v === missing && return "missing"
    v isa AbstractFloat && !isfinite(v) && return string(v)
    return string(v)
end

"""
Generate a label from the values of the columns defining one series.
"""
function _series_label(g, series_columns::Vector{Symbol})
    isempty(series_columns) && return "Current"

    parts = String[]
    for c in series_columns
        push!(parts, "$(c)=$(_series_value_string(g[1, c]))")
    end

    return join(parts, ", ")
end

"""
Generate a deterministic color for series number `i`.
"""
function _series_color(i::Int, n::Int)
    t = n <= 1 ? 0.5 : (i - 1) / (n - 1)
    return _heat_color(t)
end

"""
Extract finite x/y vectors from one DataFrame group.

Rows are sorted by xaxis before extraction.
"""
function _group_axis_values(
    g,
    xaxis::Symbol,
    yaxis::Symbol,
)
    subg = DF.dropmissing(g[!,[xaxis,yaxis]],view = true)
    isempty(subg) && return Float64[], Float64[]

    sort!(subg, xaxis)

    xs = collect(subg[!,xaxis])
    ys = collect(subg[!,yaxis])

    return xs, ys
end

"""
Build plotting series from a DataFrame.

If `series_by` is `nothing`, all varying columns except the excluded fields
are used automatically. If `series_by` is supplied, only those columns are
used for splitting.
"""
function _make_series(
    df::DF.DataFrame,
    xaxis::Symbol,
    yaxis::Symbol;
    series_by::Union{Nothing,AbstractVector{Symbol}}=nothing,
    exclude::AbstractSet{Symbol}=DEFAULT_SERIES_EXCLUDE,
)
    isempty(df) && return NamedTuple[]

    series_columns = series_by === nothing ?
        _series_columns(df, xaxis, yaxis; exclude=exclude) :
        collect(series_by)

    # Do not allow the plot coordinates or explicitly excluded fields to
    # accidentally become series dimensions.
    series_columns = [
        c for c in series_columns
        if c != xaxis &&
           c != yaxis &&
           !(c in exclude) &&
           c in propertynames(df)
    ]

    groups = if isempty(series_columns)
        [df]
    else
        collect(DF.groupby(df, series_columns))
    end

    # GroupBy iteration order is not a useful contract for a legend.
    # Sort by textual representations to make output deterministic even when
    # different columns contain different Julia types.
    sort!(
        groups;
        by = g -> join(
                (
                _series_value_string(g[1, c])
                for c in series_columns),
            ",")
        )

    result = NamedTuple[]

    for (i, g) in enumerate(groups)
        xs, ys = _group_axis_values(g, xaxis, yaxis)
        isempty(xs) && continue

        push!(
            result,
            (
                label = _series_label(g, series_columns),
                xs = xs,
                ys = ys,
                color = _series_color(i, length(groups)),
            ),
        )
    end

    return result
end


function _axis_values(points::Vector{Point}, xaxis::Symbol, yaxis::Symbol)
    df = _points_to_dataframe(points)
    return _group_axis_values(df, xaxis, yaxis)
end

function _axis_triplet_values(points::Vector{Point}, xaxis::Symbol, yaxis::Symbol, zaxis::Symbol)
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
    return xs, ys, zs
end

function _axis_triplet_values(
    df::DF.DataFrame,
    xaxis::Symbol,
    yaxis::Symbol,
    zaxis::Symbol,
)
    xs = Float64[]
    ys = Float64[]
    zs = Float64[]

    for row in eachrow(df)
        x = _to_num(row[xaxis])
        y = _to_num(row[yaxis])
        z = _to_num(row[zaxis])

        if isfinite(x) && isfinite(y) && isfinite(z)
            push!(xs, x)
            push!(ys, y)
            push!(zs, z)
        end
    end

    return xs, ys, zs
end

function _nice_limits(lo::Float64, hi::Float64)
    if lo == hi
        d = lo == 0 ? 1.0 : abs(lo) * 0.1
        return (lo - d, hi + d)
    end
    pad = (hi - lo) * 0.05
    return (lo - pad, hi + pad)
end

function _maybe_log10(v::AbstractVector{Float64}; enabled::Bool=false)
    !enabled && return v
    # Если включен, заранее выделяем массив точного размера
    n = length(v)
    out = Vector{Float64}(undef, n)
    
    # Прямой проход без push!
    @inbounds for i in 1:n
        x = v[i]
        out[i] = x > 0 ? log10(x) : NaN
    end
    
    return out
end

function _draw_axes!(ctx, w::Float64, h::Float64; title::String="")
    Cairo.set_source_rgb(ctx, 1, 1, 1)
    Cairo.rectangle(ctx, 0, 0, w, h)
    Cairo.fill(ctx)

    Cairo.set_source_rgb(ctx, 0.15, 0.15, 0.15)
    Cairo.set_line_width(ctx, 1.0)
    Cairo.rectangle(ctx, 40, 15, max(w - 55, 1), max(h - 40, 1))
    Cairo.stroke(ctx)

    if !isempty(title)
        Cairo.move_to(ctx, 45, 12)
        Cairo.set_font_size(ctx, 12)
        Cairo.show_text(ctx, title)
    end
end

function _fmt_tick(v::Float64)
    a = abs(v)
    if a != 0 && (a >= 1e4 || a < 1e-3)
        return Printf.@sprintf("%.2e", v)
    end
    return string(round(v, sigdigits=4))
end

function _nice_tick_step(span::Float64, target::Int=6)
    s = max(abs(span), 1e-12)
    raw = s / max(target, 1)
    pow10 = 10.0 ^ floor(log10(raw))
    f = raw / pow10
    base =
        f <= 1.0 ? 1.0 :
        f <= 2.0 ? 2.0 :
        f <= 5.0 ? 5.0 : 10.0
    return base * pow10
end

function _nice_ticks(lo::Float64, hi::Float64; target::Int=6)
    if !isfinite(lo) || !isfinite(hi)
        return Float64[]
    end
    if hi < lo
        lo, hi = hi, lo
    end
    if hi == lo
        return [lo]
    end
    step = _nice_tick_step(hi - lo, target)
    start = ceil(lo / step) * step
    stopv = floor(hi / step) * step
    stopv < start && return [lo, hi]

    ticks = Float64[]
    t = start
    limit = 0
    while t <= stopv + step * 1e-9 && limit < 1000
        push!(ticks, abs(t) < step * 1e-12 ? 0.0 : t)
        t += step
        limit += 1
    end
    return isempty(ticks) ? [lo, hi] : ticks
end

function _draw_cartesian_ticks!(ctx, w::Float64, h::Float64, xmin::Float64, xmax::Float64, ymin::Float64, ymax::Float64)
    left, top = 40.0, 15.0
    pw = max(w - 55, 1)
    ph = max(h - 40, 1)

    Cairo.set_source_rgb(ctx, 0.2, 0.2, 0.2)
    Cairo.set_line_width(ctx, 1.0)
    Cairo.set_font_size(ctx, 10)

    xspan = max(xmax - xmin, 1e-12)
    yspan = max(ymax - ymin, 1e-12)
    xticks = _nice_ticks(xmin, xmax; target=6)
    yticks = _nice_ticks(ymin, ymax; target=6)

    for xv in xticks
        t = (xv - xmin) / xspan
        x = left + t * pw
        y = top + ph
        Cairo.move_to(ctx, x, y)
        Cairo.line_to(ctx, x, y + 4)
        Cairo.stroke(ctx)
        Cairo.move_to(ctx, x - 14, y + 14)
        Cairo.show_text(ctx, _fmt_tick(xv))
    end

    for yv in yticks
        t = (yv - ymin) / yspan
        x = left
        y = top + ph - t * ph
        Cairo.move_to(ctx, x - 4, y)
        Cairo.line_to(ctx, x, y)
        Cairo.stroke(ctx)
        Cairo.move_to(ctx, 2, y + 3)
        Cairo.show_text(ctx, _fmt_tick(yv))
    end
end

function _draw_series_legend!(
    ctx,
    series::Vector{<:NamedTuple},
    w::Float64,
    h::Float64
)
    isempty(series) && return
    Cairo.set_font_size(ctx, 10)
    x0 = max(w - 230, 44)
    y0 = 24.0
    for (i, s) in enumerate(series)
        y = y0 + (i - 1) * 14
        Cairo.set_source_rgb(ctx, s.color...)
        Cairo.set_line_width(ctx, 2.0)
        Cairo.move_to(ctx, x0, y)
        Cairo.line_to(ctx, x0 + 18, y)
        Cairo.stroke(ctx)
        Cairo.set_source_rgb(ctx, 0.12, 0.12, 0.12)
        Cairo.move_to(ctx, x0 + 24, y + 3)
        Cairo.show_text(ctx, s.label)
    end
    return nothing
end

function _draw_polyline_series!(
    ctx,
    series::Vector{<:NamedTuple},
    w::Float64,
    h::Float64;
    title::String=""
)
    _draw_axes!(ctx, w, h; title=title)
    isempty(series) && return

    xmin=Inf
    xmax=-Inf
    ymin=Inf
    ymax=-Inf
    for s in series
        xmax = max(xmax, maximum(s.xs))
        xmin = min(xmin, minimum(s.xs))
        ymax = max(ymax, maximum(s.ys))
        ymin = min(ymin, minimum(s.ys))
    end

    xmin, xmax = _nice_limits(xmin, xmax)
    ymin, ymax = _nice_limits(ymin, ymax)
    _draw_cartesian_ticks!(ctx, w, h, xmin, xmax, ymin, ymax)

    left, top = 40.0, 15.0
    pw = max(w - 55, 1)
    ph = max(h - 40, 1)
     # Кэшируем делители, чтобы не делить в цикле
    x_denom = max(xmax - xmin, 1e-12)
    y_denom = max(ymax - ymin, 1e-12)
    #tx(x) = left + (x - xmin) / max(xmax - xmin, 1e-12) * pw
    #ty(y) = top + ph - (y - ymin) / max(ymax - ymin, 1e-12) * ph

    legend_items = NamedTuple[]
    for s in series
        isempty(s.xs) && continue

        Cairo.set_source_rgb(ctx, s.color...)

        xs::Vector{Float64} = s.xs
        ys::Vector{Float64} = s.ys

        if length(xs) == 1
            x_val = left + (xs[1] - xmin) / x_denom * pw
            y_val = top + ph - (ys[1] - ymin) / y_denom * ph
            Cairo.arc(ctx, x_val, y_val, 3.0, 0, 2pi)
            Cairo.fill(ctx)
            push!(legend_items, (label=s.label, color=s.color))
            continue
        end

        Cairo.set_line_width(ctx, 1.7)
         # Первая точка (инлайн расчет вместо tx/ty)
        x0 = left + (xs[1] - xmin) / x_denom * pw
        y0 = top + ph - (ys[1] - ymin) / y_denom * ph
        Cairo.move_to(ctx, x0, y0)

        for i in 2:length(s.xs)
            xi = left + (xs[i] - xmin) / x_denom * pw
            yi = top + ph - (ys[i] - ymin) / y_denom * ph
            Cairo.line_to(ctx, xi, yi)
        end

        Cairo.stroke(ctx)
        push!(legend_items, (label=s.label, color=s.color))
    end

    _draw_series_legend!(ctx, legend_items, w, h)
    return nothing
end

function _heat_color(t::Float64)
    u = clamp(t, 0.0, 1.0)
    if u < 0.33
        a = u / 0.33
        return (0.05, 0.12 + 0.55 * a, 0.40 + 0.50 * a)
    elseif u < 0.66
        a = (u - 0.33) / 0.33
        return (0.05 + 0.90 * a, 0.67 + 0.25 * a, 0.90 - 0.55 * a)
    else
        a = (u - 0.66) / 0.34
        return (0.95, 0.92 - 0.72 * a, 0.35 - 0.25 * a)
    end
end

function _edges_sorted(vals::Vector{Float64})
    n = length(vals)
    n == 0 && return Float64[]
    n == 1 && return [vals[1] - 0.5, vals[1] + 0.5]
    e = Vector{Float64}(undef, n + 1)
    e[1] = vals[1] - (vals[2] - vals[1]) / 2
    for i in 2:n
        e[i] = (vals[i - 1] + vals[i]) / 2
    end
    e[end] = vals[end] + (vals[end] - vals[end - 1]) / 2
    return e
end

function _draw_heatmap!(ctx, xs::Vector{Float64}, ys::Vector{Float64}, zs::Vector{Float64}, w::Float64, h::Float64; title::String="")
    _draw_axes!(ctx, w, h; title=title)
    isempty(xs) && return

    left, top = 40.0, 15.0
    pw = max(w - 55, 1)
    ph = max(h - 40, 1)

    acc = Dict{Tuple{Float64,Float64},Tuple{Float64,Int}}()
    for i in eachindex(xs)
        k = (xs[i], ys[i])
        if haskey(acc, k)
            s, n = acc[k]
            acc[k] = (s + zs[i], n + 1)
        else
            acc[k] = (zs[i], 1)
        end
    end

    xvals = sort(unique(first(k) for k in keys(acc)))
    yvals = sort(unique(last(k) for k in keys(acc)))
    xedges = _edges_sorted(xvals)
    yedges = _edges_sorted(yvals)
    xlo, xhi = xedges[1], xedges[end]
    ylo, yhi = yedges[1], yedges[end]
    _draw_cartesian_ticks!(ctx, w, h, xlo, xhi, ylo, yhi)


    zmin=Inf
    zmax=-Inf
    for (s, n) in values(acc)
        zmin = min(zmin,s / n)
        zmax = min(zmin,s / n)
    end
    zmin, zmax = _nice_limits(zmin,zmax)
    zspan = max(zmax - zmin, 1e-12)

    #tx(x) = left + (x - xlo) / max(xhi - xlo, 1e-12) * pw
    #ty(y) = top + ph - (y - ylo) / max(yhi - ylo, 1e-12) * ph

    xfact = 1/ max(xhi - xlo, 1e-12) * pw
    yfact = 1/ max(yhi - ylo, 1e-12) * ph
    for ix in 1:length(xvals), iy in 1:length(yvals)
        k = (xvals[ix], yvals[iy])
        haskey(acc, k) || continue
        s, n = acc[k]
        z = s / n
        c = _heat_color((z - zmin) / zspan)
        Cairo.set_source_rgb(ctx, c...)
        x1 = left + (xedges[ix] - xlo) * xfact #tx(xedges[ix])
        x2 = left + (xedges[ix+1] - xlo) * xfact #tx(xedges[ix + 1])
        y1 = top + ph - (yedges[iy + 1] - ylo) * yfact #ty(yedges[iy + 1])
        y2 = top + ph - (yedges[iy] - ylo) * yfact #ty(yedges[iy])
        Cairo.rectangle(ctx, min(x1, x2), min(y1, y2), abs(x2 - x1), abs(y2 - y1))
        Cairo.fill(ctx)
    end
end

function _draw_polar!_old(ctx, angles_deg::Vector{Float64}, radii::Vector{Float64}, w::Float64, h::Float64; title::String="")
    Cairo.set_source_rgb(ctx, 1, 1, 1)
    Cairo.rectangle(ctx, 0, 0, w, h)
    Cairo.fill(ctx)

    if !isempty(title)
        Cairo.set_source_rgb(ctx, 0.15, 0.15, 0.15)
        Cairo.move_to(ctx, 12, 18)
        Cairo.set_font_size(ctx, 12)
        Cairo.show_text(ctx, title)
    end

    finite_r = filter(isfinite, radii)
    isempty(finite_r) && return
    rmax = maximum(abs, finite_r)
    rmax = rmax <= 0 ? 1.0 : rmax

    cx = w / 2
    cy = h / 2 + 8
    rr = max(min(w, h) / 2 - 28, 10)
    tr(r) = rr * (r / rmax)

    Cairo.set_source_rgb(ctx, 0.78, 0.78, 0.78)
    Cairo.set_line_width(ctx, 1.0)
    for frac in (0.25, 0.5, 0.75, 1.0)
        Cairo.arc(ctx, cx, cy, rr * frac, 0, 2pi)
        Cairo.stroke(ctx)
    end
    Cairo.move_to(ctx, cx - rr, cy); Cairo.line_to(ctx, cx + rr, cy); Cairo.stroke(ctx)
    Cairo.move_to(ctx, cx, cy - rr); Cairo.line_to(ctx, cx, cy + rr); Cairo.stroke(ctx)

    Cairo.set_source_rgb(ctx, 0.35, 0.35, 0.35)
    Cairo.set_font_size(ctx, 10)
    for frac in (0.25, 0.5, 0.75, 1.0)
        rv = frac * rmax
        Cairo.move_to(ctx, cx + rr * frac + 4, cy - 2)
        Cairo.show_text(ctx, _fmt_tick(rv))
    end
    for deg in 0:45:315
        a = deg * pi / 180
        lx = cx + (rr + 8) * cos(a)
        ly = cy - (rr + 8) * sin(a)
        Cairo.move_to(ctx, lx - 8, ly + 3)
        Cairo.show_text(ctx, string(deg))
    end

    pts = Tuple{Float64,Float64}[]
    for i in eachindex(angles_deg)
        a = angles_deg[i] * pi / 180
        r = radii[i]
        isfinite(r) || continue
        push!(pts, (a, r))
    end
    isempty(pts) && return
    sort!(pts, by=first)

    Cairo.set_source_rgb(ctx, 0.03, 0.38, 0.62)
    Cairo.set_line_width(ctx, 1.7)
    a0, r0 = pts[1]
    Cairo.move_to(ctx, cx + tr(r0) * cos(a0), cy - tr(r0) * sin(a0))
    for i in 2:length(pts)
        a, r = pts[i]
        Cairo.line_to(ctx, cx + tr(r) * cos(a), cy - tr(r) * sin(a))
    end
    Cairo.stroke(ctx)
end

function _draw_polar!(
    ctx,
    series::Vector{<:NamedTuple},
    w::Float64,
    h::Float64;
    title::String="",
)
    Cairo.set_source_rgb(ctx, 1, 1, 1)
    Cairo.rectangle(ctx, 0, 0, w, h)
    Cairo.fill(ctx)

    if !isempty(title)
        Cairo.set_source_rgb(ctx, 0.15, 0.15, 0.15)
        Cairo.move_to(ctx, 12, 18)
        Cairo.set_font_size(ctx, 12)
        Cairo.show_text(ctx, title)
    end

    isempty(series) && return

    finite_r = Float64[]

    for s in series
        append!(finite_r, filter(isfinite, s.ys))
    end

    isempty(finite_r) && return

    rmax = maximum(abs, finite_r)
    rmax = rmax <= 0 ? 1.0 : rmax

    cx = w / 2
    cy = h / 2 + 8
    rr = max(min(w, h) / 2 - 28, 10)

    tr(r) = rr * (r / rmax)

    Cairo.set_source_rgb(ctx, 0.78, 0.78, 0.78)
    Cairo.set_line_width(ctx, 1.0)

    for frac in (0.25, 0.5, 0.75, 1.0)
        Cairo.arc(ctx, cx, cy, rr * frac, 0, 2pi)
        Cairo.stroke(ctx)
    end

    Cairo.move_to(ctx, cx - rr, cy)
    Cairo.line_to(ctx, cx + rr, cy)
    Cairo.stroke(ctx)

    Cairo.move_to(ctx, cx, cy - rr)
    Cairo.line_to(ctx, cx, cy + rr)
    Cairo.stroke(ctx)

    Cairo.set_source_rgb(ctx, 0.35, 0.35, 0.35)
    Cairo.set_font_size(ctx, 10)

    for frac in (0.25, 0.5, 0.75, 1.0)
        rv = frac * rmax

        Cairo.move_to(ctx, cx + rr * frac + 4, cy - 2)
        Cairo.show_text(ctx, _fmt_tick(rv))
    end

    for deg in 0:45:315
        a = deg * pi / 180
        lx = cx + (rr + 8) * cos(a)
        ly = cy - (rr + 8) * sin(a)

        Cairo.move_to(ctx, lx - 8, ly + 3)
        Cairo.show_text(ctx, string(deg))
    end

    legend_items = NamedTuple[]

    for s in series
        pts = Tuple{Float64,Float64}[]

        for i in eachindex(s.xs)
            a = s.xs[i] * pi / 180
            r = s.ys[i]

            isfinite(r) || continue
            push!(pts, (a, r))
        end

        isempty(pts) && continue

        sort!(pts, by=first)

        Cairo.set_source_rgb(ctx, s.color...)
        Cairo.set_line_width(ctx, 1.7)

        a0, r0 = pts[1]

        if length(pts) == 1
            Cairo.arc(
                ctx,
                cx + tr(r0) * cos(a0),
                cy - tr(r0) * sin(a0),
                3.0,
                0,
                2pi,
            )
            Cairo.fill(ctx)
        else
            Cairo.move_to(
                ctx,
                cx + tr(r0) * cos(a0),
                cy - tr(r0) * sin(a0),
            )

            for i in 2:length(pts)
                a, r = pts[i]

                Cairo.line_to(
                    ctx,
                    cx + tr(r) * cos(a),
                    cy - tr(r) * sin(a),
                )
            end

            Cairo.stroke(ctx)
        end

        push!(legend_items, (label=s.label, color=s.color))
    end

    _draw_series_legend!(ctx, legend_items, w, h)

    return nothing
end

"""
Main signal plot renderer.

`points` is converted to a DataFrame once per render call.

`series_by` controls how lines are split:
- `nothing`: automatically use every varying non-axis column except excluded
  metadata;
- `[:polarizer, :analyzer]`: split only by these parameters;
- `Symbol[]`: force one series.

`real_power` and `__file_path` are excluded from automatic grouping by default.
"""
function render_signal_plot!(
    ctx,
    w::Float64,
    h::Float64,
    points::Vector{Point};
    xaxis::Symbol=:wl,
    yaxis::Symbol=:sig,
    mode::Symbol=:line,
    zaxis::Symbol=:sig,
    log_scale::Bool=false,
    title::String="",
    series_by::Union{Nothing,AbstractVector{Symbol}}=nothing,
    series_exclude::AbstractSet{Symbol}=DEFAULT_SERIES_EXCLUDE,
)
    df = _points_to_dataframe(points)

    return render_signal_plot!(
        ctx,
        w,
        h,
        df;
        xaxis=xaxis,
        yaxis=yaxis,
        mode=mode,
        zaxis=zaxis,
        log_scale=log_scale,
        title=title,
        series_by=series_by,
        series_exclude=series_exclude,
    )
end

"""
DataFrame-native main signal plot renderer.

This method is preferable when the same dataset is plotted repeatedly:
the caller can convert Vector{Point} to DataFrame once and reuse it.
"""
function render_signal_plot!(
    ctx,
    w::Float64,
    h::Float64,
    df::DF.DataFrame;
    xaxis::Symbol=:wl,
    yaxis::Symbol=:sig,
    mode::Symbol=:line,
    zaxis::Symbol=:sig,
    log_scale::Bool=false,
    title::String="",
    series_by::Union{Nothing,AbstractVector{Symbol}}=nothing,
    series_exclude::AbstractSet{Symbol}=DEFAULT_SERIES_EXCLUDE,
)
    if isempty(df)
        if mode == :polar
            _draw_polar!(ctx, NamedTuple[], w, h; title=title)
        else
            _draw_axes!(ctx, w, h; title=title)
        end
        return nothing
    end

    # Fail early with a useful error instead of producing an obscure
    # DataFrame indexing error below.
    for axis in (xaxis, yaxis)
        if !(axis in propertynames(df))
            #throw(ArgumentError("Axis column $(axis) is not present in DataFrame"))
            return nothing
        end
    end

    if mode == :heatmap
        if !(zaxis in propertynames(df))
            #throw(ArgumentError("Z-axis column $(zaxis) is not present in DataFrame"))
            return nothing
        end

        xs, ys, zs = _axis_triplet_values(df, xaxis, yaxis, zaxis)

        zdraw = _maybe_log10(zs; enabled=log_scale)

        keep = [
            isfinite(xs[i]) &&
            isfinite(ys[i]) &&
            isfinite(zdraw[i])
            for i in eachindex(xs)
        ]

        xs2 = xs[keep]
        ys2 = ys[keep]
        zs2 = zdraw[keep]

        tag = log_scale ? "log10($(zaxis))" : string(zaxis)

        _draw_heatmap!(ctx, xs2, ys2, zs2, w, h; 
                title=isempty(title) ? "heatmap: $(xaxis), $(yaxis), $(tag)" : title,
        )

    elseif mode == :polar
        raw_series = _make_series(df, xaxis, yaxis; series_by=series_by, exclude=series_exclude,)

        series = NamedTuple[]
        for s in raw_series
            rdraw = _maybe_log10(s.ys; enabled=log_scale)

            keep = [
                isfinite(s.xs[i]) &&
                isfinite(rdraw[i])
                for i in eachindex(s.xs)
            ]

            xs = s.xs[keep]
            ys = rdraw[keep]

            isempty(xs) && continue

            push!(
                series,
                (
                    label=s.label,
                    xs=xs,
                    ys=ys,
                    color=s.color,
                ),
            )
        end

        rtag = log_scale ? "log10($(yaxis))" : string(yaxis)

        _draw_polar!(
            ctx,
            series,
            w,
            h;
            title=isempty(title) ?
                "polar: angle=$(xaxis), r=$(rtag)" :
                title,
        )

    else
        raw_series = _make_series(df, xaxis, yaxis; series_by=series_by, exclude=series_exclude,)

        series = NamedTuple[]

        for s in raw_series
            ydraw = _maybe_log10(s.ys; enabled=log_scale)

            keep = [
                isfinite(s.xs[i]) &&
                isfinite(ydraw[i])
                for i in eachindex(s.xs)
            ]

            xs = s.xs[keep]
            ys = ydraw[keep]

            isempty(xs) && continue

            push!(
                series,
                (
                    label=s.label,
                    xs=xs,
                    ys=ys,
                    color=s.color,
                ),
            )
        end

        ytag = log_scale ? "log10($(yaxis))" : string(yaxis)

        _draw_polyline_series!(
            ctx,
            series,
            w,
            h;
            title=isempty(title) ?
                "signal: $(xaxis) vs $(ytag)" :
                title,
        )
    end

    return nothing
end

end
