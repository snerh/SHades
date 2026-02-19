function _render_signal_canvas!(
    canvas,
    state::AppState,
    xaxis::Symbol,
    yaxis::Symbol;
    mode::Symbol=:line,
    zaxis::Symbol=:sig,
    log_scale::Bool=false,
    overlays::Vector{NamedTuple{(:label, :points, :color),Tuple{String,Vector{ScanPoint},NTuple{3,Float64}}}}=NamedTuple{(:label, :points, :color),Tuple{String,Vector{ScanPoint},NTuple{3,Float64}}}[]
)
    ctx = try
        Gtk.getgc(canvas)
    catch e
        if occursin("not yet initialized", sprint(showerror, e))
            return nothing
        end
        rethrow(e)
    end
    w = Float64(Gtk.width(canvas))
    h = Float64(Gtk.height(canvas))
    render_signal_plot!(ctx, w, h, state.points; xaxis=xaxis, yaxis=yaxis, mode=mode, zaxis=zaxis, log_scale=log_scale, overlays=overlays)
    Gtk.draw(canvas)
    return nothing
end

function _render_raw_canvas!(canvas, state::AppState)
    ctx = try
        Gtk.getgc(canvas)
    catch e
        if occursin("not yet initialized", sprint(showerror, e))
            return nothing
        end
        rethrow(e)
    end
    w = Float64(Gtk.width(canvas))
    h = Float64(Gtk.height(canvas))

    raw = state.last_raw
    xs = collect(1.0:1.0:length(raw))
    ys = raw
    _draw_polyline!(ctx, xs, ys, w, h; color=(0.62, 0.19, 0.08), title="raw spectrum")
    Gtk.draw(canvas)
    return nothing
end
