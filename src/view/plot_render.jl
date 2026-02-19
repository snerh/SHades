import Cairo
import Printf

function _dict_num(d::Dict{Symbol,Any}, k::Symbol, default::Float64=NaN)
    v = get(d, k, default)
    v isa Number && return Float64(v)
    try
        return parse(Float64, string(v))
    catch
        return default
    end
end

function _axis_values(points::Vector{Dict{Symbol,Any}}, xaxis::Symbol, yaxis::Symbol)
    xs = Float64[]
    ys = Float64[]
    for p in points
        x = _dict_num(p, xaxis, NaN)
        y = _dict_num(p, yaxis, NaN)
        if isfinite(x) && isfinite(y)
            push!(xs, x)
            push!(ys, y)
        end
    end
    return xs, ys
end

function _axis_triplet_values(points::Vector{Dict{Symbol,Any}}, xaxis::Symbol, yaxis::Symbol, zaxis::Symbol)
    xs = Float64[]
    ys = Float64[]
    zs = Float64[]
    for p in points
        x = _dict_num(p, xaxis, NaN)
        y = _dict_num(p, yaxis, NaN)
        z = _dict_num(p, zaxis, NaN)
        if isfinite(x) && isfinite(y) && isfinite(z)
            push!(xs, x)
            push!(ys, y)
            push!(zs, z)
        end
    end
    return xs, ys, zs
end

function _nice_limits(v::Vector{Float64})
    isempty(v) && return (0.0, 1.0)
    lo = minimum(v)
    hi = maximum(v)
    if lo == hi
        d = lo == 0 ? 1.0 : abs(lo) * 0.1
        return (lo - d, hi + d)
    end
    pad = (hi - lo) * 0.05
    return (lo - pad, hi + pad)
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

function _draw_polyline!(ctx, xs::Vector{Float64}, ys::Vector{Float64}, w::Float64, h::Float64; color=(0.05,0.33,0.75), title::String="")
    _draw_axes!(ctx, w, h; title=title)
    length(xs) < 2 && return

    xmin, xmax = _nice_limits(xs)
    ymin, ymax = _nice_limits(ys)
    _draw_cartesian_ticks!(ctx, w, h, xmin, xmax, ymin, ymax)

    left, top = 40.0, 15.0
    pw = max(w - 55, 1)
    ph = max(h - 40, 1)

    tx(x) = left + (x - xmin) / (xmax - xmin) * pw
    ty(y) = top + ph - (y - ymin) / (ymax - ymin) * ph

    Cairo.set_source_rgb(ctx, color...)
    Cairo.set_line_width(ctx, 1.7)
    Cairo.move_to(ctx, tx(xs[1]), ty(ys[1]))
    for i in 2:length(xs)
        Cairo.line_to(ctx, tx(xs[i]), ty(ys[i]))
    end
    Cairo.stroke(ctx)
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

    zagg = Float64[]
    for (s, n) in values(acc)
        push!(zagg, s / n)
    end
    zmin, zmax = _nice_limits(zagg)
    zspan = max(zmax - zmin, 1e-12)

    tx(x) = left + (x - xlo) / max(xhi - xlo, 1e-12) * pw
    ty(y) = top + ph - (y - ylo) / max(yhi - ylo, 1e-12) * ph

    for ix in 1:length(xvals), iy in 1:length(yvals)
        k = (xvals[ix], yvals[iy])
        haskey(acc, k) || continue
        s, n = acc[k]
        z = s / n
        c = _heat_color((z - zmin) / zspan)
        Cairo.set_source_rgb(ctx, c...)
        x1 = tx(xedges[ix])
        x2 = tx(xedges[ix + 1])
        y1 = ty(yedges[iy + 1])
        y2 = ty(yedges[iy])
        Cairo.rectangle(ctx, min(x1, x2), min(y1, y2), abs(x2 - x1), abs(y2 - y1))
        Cairo.fill(ctx)
    end
end

function _draw_polar!(ctx, angles_deg::Vector{Float64}, radii::Vector{Float64}, w::Float64, h::Float64; title::String="")
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

function render_signal_plot!(
    ctx,
    w::Float64,
    h::Float64,
    points::Vector{Dict{Symbol,Any}};
    xaxis::Symbol,
    yaxis::Symbol,
    mode::Symbol=:line,
    zaxis::Symbol=:sig,
    log_scale::Bool=false,
    title::String=""
)
    if mode == :heatmap
        xs, ys, zs = _axis_triplet_values(points, xaxis, yaxis, zaxis)
        zdraw = _maybe_log10(zs; enabled=log_scale)
        keep = [isfinite(xs[i]) && isfinite(ys[i]) && isfinite(zdraw[i]) for i in eachindex(xs)]
        xs2 = xs[keep]
        ys2 = ys[keep]
        zs2 = zdraw[keep]
        tag = log_scale ? "log10($(zaxis))" : string(zaxis)
        _draw_heatmap!(ctx, xs2, ys2, zs2, w, h; title=isempty(title) ? "heatmap: $(xaxis), $(yaxis), $(tag)" : title)
    elseif mode == :polar
        xs, ys = _axis_values(points, xaxis, yaxis)
        rdraw = _maybe_log10(ys; enabled=log_scale)
        keep = [isfinite(xs[i]) && isfinite(rdraw[i]) for i in eachindex(xs)]
        x2 = xs[keep]
        r2 = rdraw[keep]
        rtag = log_scale ? "log10($(yaxis))" : string(yaxis)
        _draw_polar!(ctx, x2, r2, w, h; title=isempty(title) ? "polar: angle=$(xaxis), r=$(rtag)" : title)
    else
        xs, ys = _axis_values(points, xaxis, yaxis)
        ydraw = _maybe_log10(ys; enabled=log_scale)
        keep = [isfinite(xs[i]) && isfinite(ydraw[i]) for i in eachindex(xs)]
        x2 = xs[keep]
        y2 = ydraw[keep]
        ytag = log_scale ? "log10($(yaxis))" : string(yaxis)
        _draw_polyline!(ctx, x2, y2, w, h; color=(0.03, 0.38, 0.62), title=isempty(title) ? "signal: $(xaxis) vs $(ytag)" : title)
    end
    return nothing
end
