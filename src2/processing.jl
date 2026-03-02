module Processing

import Cairo
import Printf

using ..Domain

export save_spectrum_dat, save_spectrum_png

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
    for _ in 1:1000
        t > stopv + step * 1e-9 && break
        push!(ticks, abs(t) < step * 1e-12 ? 0.0 : t)
        t += step
    end
    return isempty(ticks) ? [lo, hi] : ticks
end

function _limits(v::Vector{Float64})
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

function _header_string(params::AbstractDict)
    chunks = String[]
    for (k, v) in sort(collect(params); by=first)
        push!(chunks, "$(String(k))=$(repr(v))")
    end
    return join(chunks, ";")
end

function save_spectrum_dat(path::AbstractString, spec::Spectrum; params::AbstractDict=Dict{Symbol,Any}())
    mkpath(dirname(path))
    open(path, "w") do io
        full = Dict{Symbol,Any}(k => v for (k, v) in params)
        full[:columns] = ("wavelength", "signal")
        println(io, "# ", _header_string(full))
        n = min(length(spec.wavelength), length(spec.signal))
        for i in 1:n
            println(io, "$(spec.wavelength[i]) $(spec.signal[i])")
        end
    end
    return path
end

function save_spectrum_png(path::AbstractString, spec::Spectrum; width::Int=900, height::Int=520, title::String="spectrum")
    out = endswith(lowercase(path), ".png") ? path : string(path, ".png")
    mkpath(dirname(out))

    xs = spec.wavelength
    ys = spec.signal
    n = min(length(xs), length(ys))

    surf = Cairo.CairoImageSurface(width, height, Cairo.FORMAT_ARGB32)
    ctx = Cairo.CairoContext(surf)
    w = Float64(width)
    h = Float64(height)
    left, top = 60.0, 24.0
    pw = max(w - 96, 1)
    ph = max(h - 72, 1)

    Cairo.set_source_rgb(ctx, 1, 1, 1)
    Cairo.rectangle(ctx, 0, 0, w, h)
    Cairo.fill(ctx)

    Cairo.set_source_rgb(ctx, 0.15, 0.15, 0.15)
    Cairo.set_line_width(ctx, 1.0)
    Cairo.rectangle(ctx, left, top, pw, ph)
    Cairo.stroke(ctx)
    Cairo.set_font_size(ctx, 12)
    Cairo.move_to(ctx, left, 16)
    Cairo.show_text(ctx, title)

    if n > 0
        xvals = Float64[xs[i] for i in 1:n if isfinite(xs[i]) && isfinite(ys[i])]
        yvals = Float64[ys[i] for i in 1:n if isfinite(xs[i]) && isfinite(ys[i])]
        if !isempty(xvals)
            xmin, xmax = _limits(xvals)
            ymin, ymax = _limits(yvals)
            xspan = max(xmax - xmin, 1e-12)
            yspan = max(ymax - ymin, 1e-12)

            Cairo.set_source_rgb(ctx, 0.2, 0.2, 0.2)
            Cairo.set_font_size(ctx, 10)
            for xv in _nice_ticks(xmin, xmax; target=6)
                x = left + (xv - xmin) / xspan * pw
                y = top + ph
                Cairo.move_to(ctx, x, y); Cairo.line_to(ctx, x, y + 4); Cairo.stroke(ctx)
                Cairo.move_to(ctx, x - 14, y + 15); Cairo.show_text(ctx, _fmt_tick(xv))
            end
            for yv in _nice_ticks(ymin, ymax; target=6)
                x = left
                y = top + ph - (yv - ymin) / yspan * ph
                Cairo.move_to(ctx, x - 4, y); Cairo.line_to(ctx, x, y); Cairo.stroke(ctx)
                Cairo.move_to(ctx, 4, y + 3); Cairo.show_text(ctx, _fmt_tick(yv))
            end

            tx(x) = left + (x - xmin) / xspan * pw
            ty(y) = top + ph - (y - ymin) / yspan * ph
            Cairo.set_source_rgb(ctx, 0.03, 0.38, 0.62)
            Cairo.set_line_width(ctx, 1.7)
            Cairo.move_to(ctx, tx(xvals[1]), ty(yvals[1]))
            for i in 2:length(xvals)
                Cairo.line_to(ctx, tx(xvals[i]), ty(yvals[i]))
            end
            Cairo.stroke(ctx)
        end
    end

    Cairo.write_to_png(surf, out)
    try
        Cairo.finish(surf)
    catch
    end
    return out
end

end
