using Cairo
import Printf

const _HAS_JSON_SPECTRUM = let
    try
        @eval import JSON
        true
    catch
        false
    end
end

function save_plot_from_points(
    path::AbstractString,
    points::Vector{ScanPoint};
    xaxis::Symbol=:wl,
    yaxis::Symbol=:sig,
    mode::Symbol=:line,
    zaxis::Symbol=:sig,
    log_scale::Bool=false,
    width::Int=900,
    height::Int=520,
    title::String=""
)
    if !isdefined(@__MODULE__, :render_signal_plot!)
        error("render_signal_plot! is not available; load gtk view first")
    end
    out = endswith(lowercase(path), ".png") ? path : string(path, ".png")
    mkpath(dirname(out))
    surf = Cairo.CairoImageSurface(width, height, Cairo.FORMAT_ARGB32)
    ctx = Cairo.CairoContext(surf)
    render_signal_plot!(ctx, Float64(width), Float64(height), points;
        xaxis=xaxis, yaxis=yaxis, mode=mode, zaxis=zaxis, log_scale=log_scale, title=title)
    Cairo.write_to_png(surf, out)
    try
        Cairo.finish(surf)
    catch
    end
    isfile(out) || error("PNG not written: $out")
    return out
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

function _fmt_tick(v::Float64)
    a = abs(v)
    if a != 0 && (a >= 1e4 || a < 1e-3)
        return Printf.@sprintf("%.2e", v)
    end
    return string(round(v, sigdigits=4))
end

function save_spectrum_dat(path::AbstractString, spec::Spectrum; params::Dict{Symbol,Any}=Dict{Symbol,Any}())
    open(path, "w") do io
        header = Dict(String(k) => v for (k, v) in params)
        header["columns"] = ["wavelength", "signal"]
        if _HAS_JSON_SPECTRUM
            println(io, "# ", JSON.json(header))
        else
            println(io, "# columns=wavelength,signal")
        end
        for i in eachindex(spec.wavelength)
            println(io, "$(spec.wavelength[i]) $(spec.signal[i])")
        end
    end
    return path
end

function save_spectrum_plot(
    path::AbstractString,
    spec::Spectrum;
    width::Int=900,
    height::Int=520,
    title::String="Spectrum",
    x_label::String="wavelength",
    y_label::String="signal"
)
    out = endswith(lowercase(path), ".png") ? path : string(path, ".png")
    mkpath(dirname(out))
    surf = Cairo.CairoImageSurface(width, height, Cairo.FORMAT_ARGB32)
    ctx = Cairo.CairoContext(surf)

    w = Float64(width)
    h = Float64(height)
    left, top = 60.0, 20.0
    pw = max(w - 90, 1)
    ph = max(h - 60, 1)

    Cairo.set_source_rgb(ctx, 1, 1, 1)
    Cairo.rectangle(ctx, 0, 0, w, h)
    Cairo.fill(ctx)

    Cairo.set_source_rgb(ctx, 0.15, 0.15, 0.15)
    Cairo.set_line_width(ctx, 1.0)
    Cairo.rectangle(ctx, left, top, pw, ph)
    Cairo.stroke(ctx)

    if !isempty(title)
        Cairo.move_to(ctx, left, 14)
        Cairo.set_font_size(ctx, 12)
        Cairo.show_text(ctx, title)
    end

    xs = spec.wavelength
    ys = spec.signal
    if length(xs) >= 2
        xmin, xmax = minimum(xs), maximum(xs)
        ymin, ymax = minimum(ys), maximum(ys)
        if xmin == xmax
            xmin -= 1
            xmax += 1
        end
        if ymin == ymax
            ymin -= 1
            ymax += 1
        end
        tx(x) = left + (x - xmin) / (xmax - xmin) * pw
        ty(y) = top + ph - (y - ymin) / (ymax - ymin) * ph

        Cairo.set_source_rgb(ctx, 0.2, 0.2, 0.2)
        Cairo.set_font_size(ctx, 10)
        for xv in _nice_ticks(xmin, xmax; target=6)
            x = tx(xv)
            Cairo.move_to(ctx, x, top + ph)
            Cairo.line_to(ctx, x, top + ph + 4)
            Cairo.stroke(ctx)
            Cairo.move_to(ctx, x - 12, top + ph + 16)
            Cairo.show_text(ctx, _fmt_tick(xv))
        end
        for yv in _nice_ticks(ymin, ymax; target=6)
            y = ty(yv)
            Cairo.move_to(ctx, left - 4, y)
            Cairo.line_to(ctx, left, y)
            Cairo.stroke(ctx)
            Cairo.move_to(ctx, 4, y + 3)
            Cairo.show_text(ctx, _fmt_tick(yv))
        end

        Cairo.move_to(ctx, w / 2 - 30, h - 10)
        Cairo.show_text(ctx, x_label)
        Cairo.save(ctx)
        Cairo.translate(ctx, 12, h / 2 + 30)
        Cairo.rotate(ctx, -pi / 2)
        Cairo.show_text(ctx, y_label)
        Cairo.restore(ctx)

        Cairo.set_source_rgb(ctx, 0.03, 0.38, 0.62)
        Cairo.set_line_width(ctx, 1.7)
        Cairo.move_to(ctx, tx(xs[1]), ty(ys[1]))
        for i in 2:length(xs)
            Cairo.line_to(ctx, tx(xs[i]), ty(ys[i]))
        end
        Cairo.stroke(ctx)
    end

    Cairo.write_to_png(surf, out)
    try
        Cairo.finish(surf)
    catch
    end
    if !isfile(out)
        error("PNG not written: $out")
    end
    return out
end
