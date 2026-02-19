import Gtk
import Cairo

function _safe_parse_int(s::AbstractString, d::Int)
    try
        parse(Int, strip(s))
    catch
        d
    end
end

function _safe_parse_float(s::AbstractString, d::Float64)
    try
        parse(Float64, replace(strip(s), "," => "."))
    catch
        d
    end
end

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

function _draw_polyline!(ctx, xs::Vector{Float64}, ys::Vector{Float64}, w::Float64, h::Float64; color=(0.05,0.33,0.75), title::String="")
    _draw_axes!(ctx, w, h; title=title)
    length(xs) < 2 && return

    xmin, xmax = _nice_limits(xs)
    ymin, ymax = _nice_limits(ys)

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

function _render_signal_canvas!(canvas, state::AppState, xaxis::Symbol, yaxis::Symbol)
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
    xs, ys = _axis_values(state.points, xaxis, yaxis)
    _draw_polyline!(ctx, xs, ys, w, h; color=(0.03, 0.38, 0.62), title="signal: $(xaxis) vs $(yaxis)")
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

function start_gtk_legacy_app(devices::DeviceBundle; title::String="SHades2.0", default_output_dir::String="")
    win = Gtk.Window(title, 1080, 720)
    root = Gtk.Box(:h)
    left = Gtk.Box(:v)
    right = Gtk.Box(:v)
    form = Gtk.Grid()

    state = AppState()
    session_ref = Ref{Union{Nothing,MeasurementSession}}(nothing)

    wl_spec = Gtk.Entry(); Gtk.set_gtk_property!(wl_spec, :text, "500:2:540")
    sol_spec = Gtk.Entry(); Gtk.set_gtk_property!(sol_spec, :text, "=round(wl/40)*20")
    pol_spec = Gtk.Entry(); Gtk.set_gtk_property!(pol_spec, :text, "")
    ana_spec = Gtk.Entry(); Gtk.set_gtk_property!(ana_spec, :text, "")
    power_spec = Gtk.Entry(); Gtk.set_gtk_property!(power_spec, :text, "")

    inter = Gtk.Entry(); Gtk.set_gtk_property!(inter, :text, "SIG")
    acq_ms = Gtk.Entry(); Gtk.set_gtk_property!(acq_ms, :text, "50")
    frames = Gtk.Entry(); Gtk.set_gtk_property!(frames, :text, "2")
    delay_s = Gtk.Entry(); Gtk.set_gtk_property!(delay_s, :text, "0.01")
    out_dir = Gtk.Entry(); Gtk.set_gtk_property!(out_dir, :text, default_output_dir)

    xbox = Gtk.ComboBoxText(); ybox = Gtk.ComboBoxText()
    axis_choices = String.([:wl, :polarizer, :analyzer, :power, :loop, :real_power, :sig, :time_s])
    for c in axis_choices
        push!(xbox, c)
        push!(ybox, c)
    end
    Gtk.set_gtk_property!(xbox, :active, 0)
    Gtk.set_gtk_property!(ybox, :active, 6)

    run_btn = Gtk.Button("Run")
    stop_btn = Gtk.Button("Stop")
    pause_btn = Gtk.ToggleButton("Pause")
    status = Gtk.Label("Idle")

    rows = [
        ("wl spec", wl_spec),
        ("sol_wl spec", sol_spec),
        ("polarizer spec", pol_spec),
        ("analyzer spec", ana_spec),
        ("power spec", power_spec),
        ("interaction", inter),
        ("acq time (ms)", acq_ms),
        ("frames", frames),
        ("delay (s)", delay_s),
        ("output dir", out_dir),
        ("plot X", xbox),
        ("plot Y", ybox),
    ]

    for (i, (lbl, w)) in enumerate(rows)
        form[1, i] = Gtk.Label(lbl)
        form[2, i] = w
    end

    btn_row = Gtk.Box(:h)
    push!(btn_row, run_btn)
    push!(btn_row, pause_btn)
    push!(btn_row, stop_btn)

    canvas_signal = Gtk.GtkCanvas(800, 320)
    canvas_raw = Gtk.GtkCanvas(800, 320)
    Gtk.set_gtk_property!(canvas_signal, :expand, true)
    Gtk.set_gtk_property!(canvas_raw, :expand, true)

    push!(left, form)
    push!(left, btn_row)
    push!(left, status)

    push!(right, canvas_signal)
    push!(right, canvas_raw)

    push!(root, left)
    push!(root, right)
    push!(win, root)

    spec_order = [
        :wl => wl_spec,
        :sol_wl => sol_spec,
        :polarizer => pol_spec,
        :analyzer => ana_spec,
        :power => power_spec,
    ]
    spec_entries = Dict{Symbol,Any}(spec_order)

    function set_field_error!(entry, msg::String)
        Gtk.set_gtk_property!(entry, :tooltip_text, msg)
        try
            Gtk.set_gtk_property!(entry, :secondary_icon_name, "dialog-error-symbolic")
            Gtk.set_gtk_property!(entry, :secondary_icon_tooltip_text, msg)
        catch
        end
    end

    function clear_field_error!(entry)
        Gtk.set_gtk_property!(entry, :tooltip_text, "")
        try
            Gtk.set_gtk_property!(entry, :secondary_icon_name, "")
            Gtk.set_gtk_property!(entry, :secondary_icon_tooltip_text, "")
        catch
        end
    end

    function clear_errors!()
        for e in values(spec_entries)
            clear_field_error!(e)
        end
    end

    function apply_errors!(errs::Dict{Symbol,String})
        clear_errors!()
        for (k, msg) in errs
            haskey(spec_entries, k) && set_field_error!(spec_entries[k], msg)
        end
    end

    function refresh_plots!()
        xaxis = Symbol(Gtk.bytestring(Gtk.GAccessor.active_text(xbox)))
        yaxis = Symbol(Gtk.bytestring(Gtk.GAccessor.active_text(ybox)))
        _render_signal_canvas!(canvas_signal, state, xaxis, yaxis)
        _render_raw_canvas!(canvas_raw, state)
        Gtk.set_gtk_property!(status, :label, state.status)
    end

    Gtk.signal_connect(run_btn, "clicked") do _
        try
            if session_ref[] !== nothing
                stop_measurement!(session_ref[])
                session_ref[] = nothing
            end

            specs = Pair{Symbol,String}[]
            for (sym, entry) in spec_order
                txt = strip(Gtk.get_gtk_property(entry, "text", String))
                isempty(txt) || push!(specs, sym => txt)
            end

            inter_txt = strip(Gtk.get_gtk_property(inter, "text", String))
            inter_txt = isempty(inter_txt) ? "SIG" : inter_txt

            fixed = Pair{Symbol,Any}[
                :inter => inter_txt,
                :acq_time => (max(_safe_parse_int(Gtk.get_gtk_property(acq_ms, "text", String), 50), 1), "ms"),
                :frames => max(_safe_parse_int(Gtk.get_gtk_property(frames, "text", String), 1), 1),
            ]

            numeric_axes = Set([:wl, :sol_wl, :polarizer, :analyzer, :power])
            vr = validate_scan_text_specs(specs; fixed=fixed, numeric_axes=numeric_axes)
            if !vr.ok
                apply_errors!(vr.errors)
                state.status = "Validation error"
                refresh_plots!()
                return
            end
            clear_errors!()

            dly = max(_safe_parse_float(Gtk.get_gtk_property(delay_s, "text", String), 0.01), 0.0)
            od = strip(Gtk.get_gtk_property(out_dir, "text", String))
            out = isempty(od) ? nothing : od

            session = start_legacy_scan(devices, vr.plan; delay_s=dly, output_dir=out)
            session_ref[] = session
            bind_stop_button!(stop_btn, session)
            bind_pause_toggle!(pause_btn, session)

            handlers = GtkEventHandlers(
                on_started = ev -> begin
                    apply_event!(state, ev)
                    refresh_plots!()
                end,
                on_step = ev -> begin
                    apply_event!(state, ev)
                    refresh_plots!()
                end,
                on_finished = ev -> begin
                    apply_event!(state, ev)
                    refresh_plots!()
                end,
                on_stopped = ev -> begin
                    apply_event!(state, ev)
                    refresh_plots!()
                end,
                on_error = ev -> begin
                    apply_event!(state, ev)
                    refresh_plots!()
                end,
            )
            consume_events_gtk!(session.events; handlers=handlers)
        catch e
            state.status = "Error: $(sprint(showerror, e))"
            refresh_plots!()
        end
    end

    Gtk.signal_connect(xbox, "changed") do _
        refresh_plots!()
    end
    Gtk.signal_connect(ybox, "changed") do _
        refresh_plots!()
    end

    Gtk.signal_connect(win, "destroy") do _
        if session_ref[] !== nothing
            stop_measurement!(session_ref[])
        end
    end

    refresh_plots!()
    Gtk.showall(win)
    Gtk.gtk_main()
    return nothing
end
