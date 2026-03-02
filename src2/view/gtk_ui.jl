module GtkUI

import Gtk
import Cairo
import Printf

using ..State
using ..Parameters
using ..Persistence
using ..ParameterParser
using ..DeviceManager: SystemEvent
using ..Measurement: MeasurementCommand, StartMeasurement, StopMeasurement
using ..Power: PowerCommand, StartStab, StopStab, SetTargetPower

export SetParam, AxisEntry, GtkApp, start_gtk_ui!, render!, test_gtk

struct SetParam <: SystemEvent
    name::Symbol
    val::String
end

mutable struct AxisEntry
    name::Symbol
    widget::Any
end

mutable struct GtkApp
    win::Any
    entries::Dict{Symbol,AxisEntry}
    status_label::Any
    power_label::Any
    points_label::Any
    file_label::Any
    canvas_signal::Any
    canvas_raw::Any
end

function AxisEntry(name::Symbol, event_ch, init_str::AbstractString)
    gtk = Gtk
    entry = gtk.Entry()
    gtk.set_gtk_property!(entry, :text, String(init_str))

    function callback(_...)
        text = gtk.get_gtk_property(entry, "text", String)
        put!(event_ch, SetParam(name, text))
        return nothing
    end

    gtk.signal_connect(callback, entry, "activate")
    gtk.signal_connect(callback, entry, "editing-done")
    return AxisEntry(name, entry)
end

function _build_form_box(raw_params::Vector{Pair{Symbol,String}}, event_ch)
    gtk = Gtk
    form = gtk.Box(:v, 6)
    entries = Dict{Symbol,AxisEntry}()

    for (name, value) in raw_params
        row = gtk.Box(:h, 8)
        label = gtk.Label(String(name))
        entry = AxisEntry(name, event_ch, value)
        gtk.set_gtk_property!(label, :xalign, 0.0)
        gtk.set_gtk_property!(label, :width_request, 110)
        push!(row, label)
        push!(row, entry.widget)
        push!(form, row)
        entries[name] = entry
    end
    return form, entries
end

function _collect_raw_params(entries::Dict{Symbol,AxisEntry}, template::Vector{Pair{Symbol,String}})
    out = Pair{Symbol,String}[]
    for (name, _) in template
        haskey(entries, name) || continue
        txt = Gtk.get_gtk_property(entries[name].widget, "text", String)
        push!(out, name => txt)
    end
    return out
end

function _safe_canvas_ctx(canvas)
    try
        return Gtk.getgc(canvas)
    catch ex
        if occursin("not yet initialized", sprint(showerror, ex))
            return nothing
        end
        rethrow(ex)
    end
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
    guard = 0
    while t <= stopv + step * 1e-9 && guard < 1000
        push!(ticks, abs(t) < step * 1e-12 ? 0.0 : t)
        t += step
        guard += 1
    end
    return isempty(ticks) ? [lo, hi] : ticks
end

function _draw_cartesian_ticks!(ctx, w::Float64, h::Float64, xmin::Float64, xmax::Float64, ymin::Float64, ymax::Float64)
    left, top = 40.0, 15.0
    pw = max(w - 55, 1)
    ph = max(h - 40, 1)

    xspan = max(xmax - xmin, 1e-12)
    yspan = max(ymax - ymin, 1e-12)

    Cairo.set_source_rgb(ctx, 0.2, 0.2, 0.2)
    Cairo.set_line_width(ctx, 1.0)
    Cairo.set_font_size(ctx, 10)

    for xv in _nice_ticks(xmin, xmax; target=6)
        x = left + (xv - xmin) / xspan * pw
        y = top + ph
        Cairo.move_to(ctx, x, y)
        Cairo.line_to(ctx, x, y + 4)
        Cairo.stroke(ctx)
        Cairo.move_to(ctx, x - 14, y + 14)
        Cairo.show_text(ctx, _fmt_tick(xv))
    end

    for yv in _nice_ticks(ymin, ymax; target=6)
        x = left
        y = top + ph - (yv - ymin) / yspan * ph
        Cairo.move_to(ctx, x - 4, y)
        Cairo.line_to(ctx, x, y)
        Cairo.stroke(ctx)
        Cairo.move_to(ctx, 2, y + 3)
        Cairo.show_text(ctx, _fmt_tick(yv))
    end
    return nothing
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

function _draw_polyline!(ctx, xs::Vector{Float64}, ys::Vector{Float64}, w::Float64, h::Float64; color=(0.05, 0.33, 0.75), title::String="")
    _draw_axes!(ctx, w, h; title=title)
    n = min(length(xs), length(ys))
    n == 0 && return

    x2 = Float64[]
    y2 = Float64[]
    for i in 1:n
        x = xs[i]
        y = ys[i]
        if isfinite(x) && isfinite(y)
            push!(x2, x)
            push!(y2, y)
        end
    end
    isempty(x2) && return

    xmin, xmax = _nice_limits(x2)
    ymin, ymax = _nice_limits(y2)
    _draw_cartesian_ticks!(ctx, w, h, xmin, xmax, ymin, ymax)
    xspan = max(xmax - xmin, 1e-12)
    yspan = max(ymax - ymin, 1e-12)

    left, top = 40.0, 15.0
    pw = max(w - 55, 1)
    ph = max(h - 40, 1)

    tx(x) = left + (x - xmin) / xspan * pw
    ty(y) = top + ph - (y - ymin) / yspan * ph

    Cairo.set_source_rgb(ctx, color...)
    if length(x2) == 1
        Cairo.arc(ctx, tx(x2[1]), ty(y2[1]), 3.5, 0.0, 2 * pi)
        Cairo.fill(ctx)
        return
    end

    Cairo.set_line_width(ctx, 1.7)
    Cairo.move_to(ctx, tx(x2[1]), ty(y2[1]))
    for i in 2:length(x2)
        Cairo.line_to(ctx, tx(x2[i]), ty(y2[i]))
    end
    Cairo.stroke(ctx)
end

function _signal_xy(state::AppState)
    if state.current_spectrum !== nothing
        return state.current_spectrum.wavelength, state.current_spectrum.signal
    end

    xs = Float64[]
    ys = Float64[]
    for p in state.points
        if haskey(p, :wl) && haskey(p, :sig)
            try
                push!(xs, Float64(p[:wl]))
                push!(ys, Float64(p[:sig]))
            catch
            end
        end
    end
    return xs, ys
end

function _render_signal_canvas!(canvas, state::AppState)
    ctx = _safe_canvas_ctx(canvas)
    ctx === nothing && return nothing
    w = Float64(Gtk.width(canvas))
    h = Float64(Gtk.height(canvas))
    xs, ys = _signal_xy(state)
    _draw_polyline!(ctx, xs, ys, w, h; color=(0.03, 0.38, 0.62), title="spectrum")
    Gtk.draw(canvas)
    return nothing
end

function _render_raw_canvas!(canvas, state::AppState)
    ctx = _safe_canvas_ctx(canvas)
    ctx === nothing && return nothing
    w = Float64(Gtk.width(canvas))
    h = Float64(Gtk.height(canvas))

    xs = collect(1.0:1.0:length(state.current_raw))
    ys = state.current_raw
    _draw_polyline!(ctx, xs, ys, w, h; color=(0.62, 0.19, 0.08), title="raw camera data")
    Gtk.draw(canvas)
    return nothing
end

function render!(ui::GtkApp, state::AppState)
    points = length(state.points)
    Gtk.set_gtk_property!(ui.status_label, :label, "measurement: $(state.measurement_state)")
    Gtk.set_gtk_property!(ui.power_label, :label, "power: $(round(state.current_power; digits=4))")
    Gtk.set_gtk_property!(ui.points_label, :label, "points: $(points)")
    file_lbl = state.last_saved_file === nothing ? "saved: -" : "saved: $(basename(state.last_saved_file))"
    Gtk.set_gtk_property!(ui.file_label, :label, file_lbl)

    _render_signal_canvas!(ui.canvas_signal, state)
    _render_raw_canvas!(ui.canvas_raw, state)
    return nothing
end

function _on_mainloop(f::Function)
    Gtk.GLib.g_idle_add(nothing) do _
        try
            f()
        catch ex
            @warn "UI render callback failed" exception=(ex, catch_backtrace())
        end
        Cint(false)
    end
    return nothing
end

function start_gtk_ui!(
    state::AppState,
    event_ch,
    ui_channel,
    meas_cmd::Channel{MeasurementCommand},
    power_cmd::Channel{PowerCommand};
    config_path::AbstractString="preset.json",
    title::AbstractString="SHades2.0",
)
    raw_p = load_config(config_path)
    state.raw_params = raw_p
    state.scan_params = build_scan_axis_set_from_text_specs(raw_p)

    win = Gtk.Window(String(title), 980, 700)
    root = Gtk.Box(:v, 10)

    status_label = Gtk.Label("measurement: $(state.measurement_state)")
    power_label = Gtk.Label("power: $(state.current_power)")
    points_label = Gtk.Label("points: 0")
    file_label = Gtk.Label("saved: -")
    header = Gtk.Box(:v, 4)
    push!(header, status_label)
    push!(header, power_label)
    push!(header, points_label)
    push!(header, file_label)

    form, entries = _build_form_box(raw_p, event_ch)

    dir_entry = Gtk.Entry()
    Gtk.set_gtk_property!(dir_entry, :text, state.app_config.dir)
    target_entry = Gtk.Entry()
    Gtk.set_gtk_property!(target_entry, :text, "1.0")

    pick_dir_btn = Gtk.Button("Dir")
    scan_btn = Gtk.Button("Scan")
    stop_btn = Gtk.Button("Stop")
    power_btn = Gtk.ToggleButton("Power stab")
    target_btn = Gtk.Button("Set power")

    controls = Gtk.Box(:h, 8)
    push!(controls, Gtk.Label("output"))
    push!(controls, dir_entry)
    push!(controls, pick_dir_btn)
    push!(controls, scan_btn)
    push!(controls, stop_btn)
    push!(controls, power_btn)
    push!(controls, target_entry)
    push!(controls, target_btn)

    canvas_signal = Gtk.GtkCanvas(100, 100)
    canvas_raw = Gtk.GtkCanvas(100, 100)
    paned = Gtk.Paned(:h)
    paned[1] = canvas_signal
    paned[2] = canvas_raw
    Gtk.signal_connect((w, alloc) -> Gtk.set_gtk_property!(w, :position, alloc.width ÷ 2), paned, "size-allocate")
    Gtk.signal_connect((w, alloc) -> Gtk.set_gtk_property!(w, :position, alloc.height), paned, "size-allocate")

    push!(root, header)
    push!(root, controls)
    push!(root, form)
    push!(root, paned)
    push!(win, root)

    ui = GtkApp(win, entries, status_label, power_label, points_label, file_label, canvas_signal, canvas_raw)

    function apply_target_power!()
        txt = strip(Gtk.get_gtk_property(target_entry, "text", String))
        isempty(txt) && return nothing
        v = try
            parse(Float64, txt)
        catch
            @warn "Invalid target power value: $txt"
            return nothing
        end
        put!(power_cmd, SetTargetPower(v))
        return nothing
    end

    Gtk.signal_connect(target_entry, "activate") do _
        apply_target_power!()
    end

    Gtk.signal_connect(target_btn, "clicked") do _
        apply_target_power!()
    end

    Gtk.signal_connect(power_btn, "toggled") do w
        if Gtk.GAccessor.active(w)
            put!(power_cmd, StartStab())
        else
            put!(power_cmd, StopStab())
        end
    end

    Gtk.signal_connect(dir_entry, "activate") do _
        state.app_config.dir = strip(Gtk.get_gtk_property(dir_entry, "text", String))
        return nothing
    end

    Gtk.signal_connect(pick_dir_btn, "clicked") do _
        path = Gtk.open_dialog("Select output folder", win, action=Gtk.GtkFileChooserAction.SELECT_FOLDER)
        path === nothing && return nothing
        chosen = isdir(path) ? path : dirname(path)
        Gtk.set_gtk_property!(dir_entry, :text, chosen)
        state.app_config.dir = chosen
        return nothing
    end

    Gtk.signal_connect(scan_btn, "clicked") do _
        raw_now = _collect_raw_params(ui.entries, state.raw_params)
        state.raw_params = raw_now
        try
            state.scan_params = build_scan_axis_set_from_text_specs(raw_now)
        catch
            return nothing
        end
        out_dir = strip(Gtk.get_gtk_property(dir_entry, "text", String))
        state.app_config.dir = out_dir
        put!(meas_cmd, StartMeasurement(state.scan_params, isempty(out_dir) ? nothing : out_dir))
        return nothing
    end

    Gtk.signal_connect(stop_btn, "clicked") do _
        put!(meas_cmd, StopMeasurement())
        return nothing
    end

    refresh_alive = Ref(true)

    Gtk.signal_connect(win, "destroy") do _
        refresh_alive[] = false
        state.raw_params = _collect_raw_params(ui.entries, state.raw_params)
        save_config(config_path, state.raw_params)
        Gtk.gtk_main_running[] && Gtk.gtk_quit()
        return nothing
    end

    Gtk.showall(win)

    @async begin
        for _ui_cmd in ui_channel
            _on_mainloop(() -> render!(ui, state))
        end
    end

    # Fallback refresh loop: keeps plots responsive even if event bursts are sparse.
    @async begin
        while refresh_alive[]
            sleep(0.2)
            Gtk.gtk_main_running[] || continue
            _on_mainloop(() -> render!(ui, state))
        end
    end

    render!(ui, state)
    Gtk.gtk_main()
    return ui
end

function test_gtk()
    win = Gtk.Window("test window", 720, 520)
    Gtk.signal_connect(win, "destroy") do _
        Gtk.gtk_main_running[] && Gtk.gtk_quit()
        return nothing
    end
    button = Gtk.Button("123")
    push!(win, button)
    Gtk.showall(win)
    Gtk.gtk_main()
end

end
