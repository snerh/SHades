module GtkUI

import Gtk

using ..State
using ..Parameters
using ..Persistence
using ..ParameterParser
using ..DeviceManager: SystemEvent, DeviceHub, connect_devices!, init_devices!, disconnect_devices!, devices_status
using ..Measurement: MeasurementCommand, StartMeasurement, StopMeasurement
using ..Power: PowerCommand, StartStab, StopStab
using ..Processing: save_plot_dat, save_plot_png
using ..PlotRender: DEFAULT_AXIS_CHOICES, render_signal_plot!

export SetParam, AxisEntry, GtkApp, start_gtk_ui!, render!, test_gtk

struct SetParam <: SystemEvent
    name::Symbol
    val::String
end

struct SetDeviceLifecycle <: SystemEvent
    connected::Bool
    initialized::Bool
    message::String
end

mutable struct AxisEntry
    name::Symbol
    widget::Any
end

mutable struct GtkApp
    win::Any
    entries::Dict{Symbol,AxisEntry}
    status_label::Any
    device_label::Any
    power_label::Any
    points_label::Any
    file_label::Any
    dir_label::Any
    xbox::Any
    ybox::Any
    zbox::Any
    mode_box::Any
    log_cb::Any
    connect_btn::Any
    init_btn::Any
    disconnect_btn::Any
    pick_dir_btn::Any
    scan_btn::Any
    focus_btn::Any
    stop_btn::Any
    power_btn::Any
    save_dat_btn::Any
    save_png_btn::Any
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

function _active_text(box, fallback::AbstractString)
    t = Gtk.GAccessor.active_text(box)
    t === nothing && return String(fallback)
    return Gtk.bytestring(t)
end

function _plot_settings(ui::GtkApp)
    mode_txt = _active_text(ui.mode_box, "line")
    return (
        xaxis = Symbol(_active_text(ui.xbox, "wl")),
        yaxis = Symbol(_active_text(ui.ybox, "sig")),
        zaxis = Symbol(_active_text(ui.zbox, "sig")),
        mode = Symbol(mode_txt),
        log_scale = Gtk.GAccessor.active(ui.log_cb),
    )
end

function _set_combo_active!(box, values::Vector{String}, wanted::String)
    idx = findfirst(==(wanted), values)
    Gtk.set_gtk_property!(box, :active, Int((idx === nothing ? 1 : idx) - 1))
    return nothing
end

function _update_plot_controls!(ui::GtkApp)
    mode_txt = _active_text(ui.mode_box, "line")
    Gtk.set_gtk_property!(ui.zbox, :sensitive, mode_txt == "heatmap")
    return nothing
end

function _is_measurement_active(state::AppState)
    state.measurement_state in (State.Preparing, State.Running, State.Paused, State.Stopping)
end

function _to_int_default(v, default::Int=1)
    try
        return Int(round(Float64(v)))
    catch
        return default
    end
end

function _focus_axes(scan_params::ScanAxisSet)
    axes = scan_params.axes
    have_loop = false
    push!(axes, LoopAxis(name=:loop, start=1, step=1, stop=nothing))
    return ScanAxisSet(axes)
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

function _signal_points(state::AppState)
    if !isempty(state.points)
        return state.points
    end
    if state.current_spectrum !== nothing
        n = min(length(state.current_spectrum.wavelength), length(state.current_spectrum.signal))
        return [Dict{Symbol,Any}(:wl => state.current_spectrum.wavelength[i], :sig => state.current_spectrum.signal[i]) for i in 1:n]
    end
    return Dict{Symbol,Any}[]
end

function _raw_points(state::AppState)
    pts = Dict{Symbol,Any}[]
    for i in eachindex(state.current_raw)
        push!(pts, Dict{Symbol,Any}(:idx => Float64(i), :value => state.current_raw[i]))
    end
    return pts
end

function _render_signal_canvas!(ui::GtkApp, state::AppState)
    canvas = ui.canvas_signal
    ctx = _safe_canvas_ctx(canvas)
    ctx === nothing && return nothing
    w = Float64(Gtk.width(canvas))
    h = Float64(Gtk.height(canvas))
    ps = _plot_settings(ui)
    points = _signal_points(state)
    render_signal_plot!(
        ctx, w, h, points;
        xaxis=ps.xaxis, yaxis=ps.yaxis, zaxis=ps.zaxis, mode=ps.mode, log_scale=ps.log_scale,
    )
    Gtk.draw(canvas)
    return nothing
end

function _render_raw_canvas!(canvas, state::AppState)
    ctx = _safe_canvas_ctx(canvas)
    ctx === nothing && return nothing
    w = Float64(Gtk.width(canvas))
    h = Float64(Gtk.height(canvas))
    render_signal_plot!(
        ctx, w, h, _raw_points(state);
        xaxis=:idx, yaxis=:value, mode=:line, zaxis=:value, log_scale=false, title="raw camera data",
    )
    Gtk.draw(canvas)
    return nothing
end

function _update_controls_state!(ui::GtkApp, state::AppState)
    running = _is_measurement_active(state)
    connected = state.devices_connected
    initialized = state.devices_initialized
    have_signal = !isempty(_signal_points(state))

    Gtk.set_gtk_property!(ui.connect_btn, :sensitive, !running && !connected)
    Gtk.set_gtk_property!(ui.init_btn, :sensitive, !running && connected && !initialized)
    Gtk.set_gtk_property!(ui.disconnect_btn, :sensitive, !running && connected)
    Gtk.set_gtk_property!(ui.pick_dir_btn, :sensitive, !running)
    Gtk.set_gtk_property!(ui.scan_btn, :sensitive, !running && initialized && state.scan_params !== nothing)
    Gtk.set_gtk_property!(ui.focus_btn, :sensitive, !running && initialized && state.scan_params !== nothing)
    Gtk.set_gtk_property!(ui.stop_btn, :sensitive, running)
    Gtk.set_gtk_property!(ui.power_btn, :sensitive, initialized)
    Gtk.set_gtk_property!(ui.save_dat_btn, :sensitive, have_signal)
    Gtk.set_gtk_property!(ui.save_png_btn, :sensitive, have_signal)

    if !initialized && Gtk.GAccessor.active(ui.power_btn)
        Gtk.set_gtk_property!(ui.power_btn, :active, false)
    end

    for entry in values(ui.entries)
        Gtk.set_gtk_property!(entry.widget, :sensitive, !running)
    end

    return nothing
end

function render!(ui::GtkApp, state::AppState)
    points = length(state.points)
    Gtk.set_gtk_property!(ui.status_label, :label, "measurement: $(state.measurement_state)")
    Gtk.set_gtk_property!(ui.device_label, :label, state.device_status)
    Gtk.set_gtk_property!(ui.power_label, :label, "power: $(round(state.current_power; digits=4))")
    Gtk.set_gtk_property!(ui.points_label, :label, "points: $(points)")
    file_lbl = state.last_saved_file === nothing ? "saved: -" : "saved: $(basename(state.last_saved_file))"
    Gtk.set_gtk_property!(ui.file_label, :label, file_lbl)
    Gtk.set_gtk_property!(ui.dir_label, :label, "dir: $(state.app_config.dir)")

    _update_plot_controls!(ui)
    _update_controls_state!(ui, state)
    _render_signal_canvas!(ui, state)
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
    power_cmd::Channel{PowerCommand},
    device_hub::DeviceHub;
    config_path::AbstractString="preset.json",
    title::AbstractString="SHades2.0",
)
    raw_p = load_config(config_path)
    state.raw_params = raw_p
    state.scan_params = build_scan_axis_set_from_text_specs(raw_p)

    win = Gtk.Window(String(title), 980, 700)
    root = Gtk.Box(:v, 10)

    status_label = Gtk.Label("measurement: $(state.measurement_state)")
    device_label = Gtk.Label(state.device_status)
    power_label = Gtk.Label("power: $(state.current_power)")
    points_label = Gtk.Label("points: 0")
    file_label = Gtk.Label("saved: -")
    dir_label = Gtk.Label("dir: $(state.app_config.dir)")
    header = Gtk.Box(:v, 4)
    push!(header, status_label)
    push!(header, device_label)
    push!(header, power_label)
    push!(header, points_label)
    push!(header, file_label)
    push!(header, dir_label)

    form, entries = _build_form_box(raw_p, event_ch)

    connect_btn = Gtk.Button("Connect")
    init_btn = Gtk.Button("Init")
    disconnect_btn = Gtk.Button("Disconnect")
    pick_dir_btn = Gtk.Button("Dir")
    scan_btn = Gtk.Button("Scan")
    focus_btn = Gtk.Button("Focus")
    stop_btn = Gtk.Button("Stop")
    power_btn = Gtk.ToggleButton("Power stab")
    save_dat_btn = Gtk.Button("Save DAT")
    save_png_btn = Gtk.Button("Save PNG")

    controls = Gtk.Box(:h, 8)
    push!(controls, connect_btn)
    push!(controls, init_btn)
    push!(controls, disconnect_btn)
    push!(controls, pick_dir_btn)
    push!(controls, scan_btn)
    push!(controls, focus_btn)
    push!(controls, stop_btn)
    push!(controls, power_btn)
    push!(controls, save_dat_btn)
    push!(controls, save_png_btn)

    xbox = Gtk.ComboBoxText()
    ybox = Gtk.ComboBoxText()
    zbox = Gtk.ComboBoxText()
    mode_box = Gtk.ComboBoxText()
    log_cb = Gtk.CheckButton("Log10")
    axis_choices = String.(DEFAULT_AXIS_CHOICES)
    for c in axis_choices
        push!(xbox, c)
        push!(ybox, c)
        push!(zbox, c)
    end
    for m in ("line", "polar", "heatmap")
        push!(mode_box, m)
    end
    _set_combo_active!(xbox, axis_choices, "wl")
    _set_combo_active!(ybox, axis_choices, "sig")
    _set_combo_active!(zbox, axis_choices, "sig")
    Gtk.set_gtk_property!(mode_box, :active, 0)
    Gtk.set_gtk_property!(log_cb, :active, false)

    plot_controls = Gtk.Box(:h, 8)
    push!(plot_controls, Gtk.Label("plot X"))
    push!(plot_controls, xbox)
    push!(plot_controls, Gtk.Label("plot Y"))
    push!(plot_controls, ybox)
    push!(plot_controls, Gtk.Label("plot C"))
    push!(plot_controls, zbox)
    push!(plot_controls, Gtk.Label("mode"))
    push!(plot_controls, mode_box)
    push!(plot_controls, log_cb)

    canvas_signal = Gtk.GtkCanvas(100, 100)
    canvas_raw = Gtk.GtkCanvas(100, 100)
    paned = Gtk.Paned(:h)
    paned[1] = canvas_signal
    paned[2] = canvas_raw
    Gtk.signal_connect((w, alloc) -> Gtk.set_gtk_property!(w, :position, alloc.width ÷ 2), paned, "size-allocate")
    # Настройка для полного использования пространства
    Gtk.set_gtk_property!(paned, :expand, true)
    Gtk.set_gtk_property!(paned, :shrink, true)


    push!(root, header)
    push!(root, controls)
    push!(root, form)
    push!(root, plot_controls)
    push!(root, paned)
    push!(win, root)

    ui = GtkApp(
        win, entries,
        status_label, device_label, power_label, points_label, file_label, dir_label,
        xbox, ybox, zbox, mode_box, log_cb,
        connect_btn, init_btn, disconnect_btn, pick_dir_btn, scan_btn, focus_btn, stop_btn, power_btn, save_dat_btn, save_png_btn,
        canvas_signal, canvas_raw,
    )

    function _emit_lifecycle_from_status(status_map::Dict{Symbol,NamedTuple{(:connected,:initialized,:healthy),Tuple{Bool,Bool,Bool}}})
        connected = !isempty(status_map) && all(v -> v.connected, values(status_map))
        initialized = !isempty(status_map) && all(v -> v.connected && v.initialized && v.healthy, values(status_map))
        if initialized
            msg = "devices: initialized"
        elseif connected
            msg = "devices: connected (not initialized)"
        else
            msg = "devices: disconnected"
        end
        put!(event_ch, SetDeviceLifecycle(connected, initialized, msg))
        return nothing
    end

    function _refresh_lifecycle!()
        try
            _emit_lifecycle_from_status(devices_status(device_hub))
        catch ex
            put!(event_ch, SetDeviceLifecycle(false, false, "devices: lifecycle error"))
            @warn "Failed to read device lifecycle status" exception=(ex, catch_backtrace())
        end
        return nothing
    end

    for widget in (xbox, ybox, zbox, mode_box)
        Gtk.signal_connect(widget, "changed") do _
            _update_plot_controls!(ui)
            render!(ui, state)
            return nothing
        end
    end
    Gtk.signal_connect(log_cb, "toggled") do _
        render!(ui, state)
        return nothing
    end

    Gtk.signal_connect(power_btn, "toggled") do w
        if !state.devices_initialized
            Gtk.GAccessor.active(w) && Gtk.set_gtk_property!(w, :active, false)
            return nothing
        end
        if Gtk.GAccessor.active(w)
            put!(power_cmd, StartStab())
        else
            put!(power_cmd, StopStab())
        end
    end

    Gtk.signal_connect(pick_dir_btn, "clicked") do _
        path = Gtk.open_dialog("Select output folder", win, action=Gtk.GtkFileChooserAction.SELECT_FOLDER)
        path === nothing && return nothing
        chosen = isdir(path) ? path : dirname(path)
        state.app_config.dir = chosen
        render!(ui, state)
        return nothing
    end

    Gtk.signal_connect(connect_btn, "clicked") do _
        try
            connect_devices!(device_hub)
            _refresh_lifecycle!()
        catch ex
            @warn "Connect failed" exception=(ex, catch_backtrace())
        end
        return nothing
    end

    Gtk.signal_connect(init_btn, "clicked") do _
        try
            init_devices!(device_hub)
            _refresh_lifecycle!()
        catch ex
            @warn "Init failed" exception=(ex, catch_backtrace())
        end
        return nothing
    end

    Gtk.signal_connect(disconnect_btn, "clicked") do _
        try
            disconnect_devices!(device_hub)
            Gtk.GAccessor.active(power_btn) && Gtk.set_gtk_property!(power_btn, :active, false)
            _refresh_lifecycle!()
        catch ex
            @warn "Disconnect failed" exception=(ex, catch_backtrace())
        end
        return nothing
    end

    Gtk.signal_connect(scan_btn, "clicked") do _
        if !state.devices_initialized
            put!(event_ch, SetDeviceLifecycle(state.devices_connected, state.devices_initialized, "devices: init required before scan"))
            return nothing
        end
        raw_now = _collect_raw_params(ui.entries, state.raw_params)
        state.raw_params = raw_now
        try
            state.scan_params = build_scan_axis_set_from_text_specs(raw_now)
        catch
            return nothing
        end
        out_dir = strip(state.app_config.dir)
        put!(meas_cmd, StartMeasurement(state.scan_params, isempty(out_dir) ? nothing : out_dir))
        return nothing
    end

    Gtk.signal_connect(focus_btn, "clicked") do _
        if !state.devices_initialized
            put!(event_ch, SetDeviceLifecycle(state.devices_connected, state.devices_initialized, "devices: init required before focus"))
            return nothing
        end
        raw_now = _collect_raw_params(ui.entries, state.raw_params)
        state.raw_params = raw_now
        try
            state.scan_params = build_scan_axis_set_from_text_specs(raw_now)
        catch
            return nothing
        end
        state.scan_params === nothing && return nothing
        put!(meas_cmd, StartMeasurement(_focus_axes(state.scan_params), nothing))
        return nothing
    end

    Gtk.signal_connect(stop_btn, "clicked") do _
        put!(meas_cmd, StopMeasurement())
        return nothing
    end

    Gtk.signal_connect(save_dat_btn, "clicked") do _
        pts = _signal_points(state)
        isempty(pts) && return nothing
        path = Gtk.save_dialog("Save spectrum .dat", win)
        path === nothing && return nothing
        ps = _plot_settings(ui)
        save_plot_dat(
            path,
            pts;
            xaxis=ps.xaxis,
            yaxis=ps.yaxis,
            zaxis=ps.zaxis,
            mode=ps.mode,
            log_scale=ps.log_scale,
            params=Dict{Symbol,Any}(:points => length(pts)),
        )
        return nothing
    end

    Gtk.signal_connect(save_png_btn, "clicked") do _
        pts = _signal_points(state)
        isempty(pts) && return nothing
        path = Gtk.save_dialog("Save spectrum .png", win)
        path === nothing && return nothing
        ps = _plot_settings(ui)
        save_plot_png(
            path,
            pts;
            xaxis=ps.xaxis,
            yaxis=ps.yaxis,
            zaxis=ps.zaxis,
            mode=ps.mode,
            log_scale=ps.log_scale,
        )
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
    _update_plot_controls!(ui)
    _refresh_lifecycle!()

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
