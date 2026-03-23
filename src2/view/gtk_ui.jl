module GtkUI

import Gtk

using ..State
using ..AppLogic: is_measurement_active, is_focus_mode, signal_points, raw_points
using ..AppController: Controller, load_presets!, append_preset!, delete_preset_at!, build_preset, dispatch_raw_params!, validation_errors, publish_focus_params!, refresh_lifecycle!, connect_devices!, init_devices!, disconnect_devices!, toggle_power_stabilization!, select_output_dir!, start_scan!, start_focus!, stop_measurement!
using ..Processing: save_plot_dat, save_plot_png
using ..PlotRender: DEFAULT_AXIS_CHOICES, render_signal_plot!

export AxisEntry, GtkApp, start_gtk_ui!, render!, test_gtk

const _GTK_CSS_PRIORITY_APPLICATION = Cuint(800)

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

function AxisEntry(name::Symbol, init_str::AbstractString)
    gtk = Gtk
    entry = gtk.Entry()
    gtk.set_gtk_property!(entry, :text, String(init_str))
    return AxisEntry(name, entry)
end

function _gtk_install_error_css!(win)
    css = """
    entry.axis-error,
    entry.axis-error:focus {
        background-image: none;
        box-shadow: none;
        background-color: #ffe4e6;
        color: #7f1d1d;
        border-color: #dc2626;
    }
    """
    provider = Gtk.CssProviderLeaf(data=css)
    screen = Gtk.GAccessor.screen(win)
    ccall((:gtk_style_context_add_provider_for_screen, Gtk.libgtk), Nothing,
        (Ptr{Nothing}, Ptr{Gtk.GObject}, Cuint),
        screen, provider, _GTK_CSS_PRIORITY_APPLICATION)
    return provider
end

function _gtk_set_style_class!(widget, class_name::String, on::Bool)
    style_ctx = Gtk.GAccessor.style_context(widget)
    if on
        ccall((:gtk_style_context_add_class, Gtk.libgtk), Nothing,
            (Ptr{Nothing}, Cstring), style_ctx.handle, class_name)
    else
        ccall((:gtk_style_context_remove_class, Gtk.libgtk), Nothing,
            (Ptr{Nothing}, Cstring), style_ctx.handle, class_name)
    end
    ccall((:gtk_widget_queue_draw, Gtk.libgtk), Nothing, (Ptr{Gtk.GObject},), widget.handle)
    return nothing
end

function _gtk_set_field_error!(entry, msg::String)
    _gtk_set_style_class!(entry, "axis-error", true)
    Gtk.set_gtk_property!(entry, :tooltip_text, msg)
    try
        Gtk.set_gtk_property!(entry, :secondary_icon_name, "dialog-error-symbolic")
        Gtk.set_gtk_property!(entry, :secondary_icon_tooltip_text, msg)
    catch
    end
end

function _gtk_clear_field_error!(entry)
    _gtk_set_style_class!(entry, "axis-error", false)
    Gtk.set_gtk_property!(entry, :tooltip_text, "")
    try
        Gtk.set_gtk_property!(entry, :secondary_icon_name, "")
        Gtk.set_gtk_property!(entry, :secondary_icon_tooltip_text, "")
    catch
    end
end

function _gtk_clear_errors!(entries::Dict{Symbol,AxisEntry})
    for e in values(entries)
        _gtk_clear_field_error!(e.widget)
    end
    return nothing
end

function _gtk_apply_errors!(entries::Dict{Symbol,AxisEntry}, errs::Dict{Symbol,String})
    _gtk_clear_errors!(entries)
    for (k, msg) in errs
        haskey(entries, k) || continue
        _gtk_set_field_error!(entries[k].widget, msg)
    end
    return nothing
end

function _build_form_box(raw_params::Vector{Pair{Symbol,String}})
    gtk = Gtk
    form = gtk.Box(:v, 6)
    entries = Dict{Symbol,AxisEntry}()

    for (name, value) in raw_params
        row = gtk.Box(:h, 8)
        label = gtk.Label(String(name))
        entry = AxisEntry(name, value)
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

function _validation_help_text()
    return join([
        "Допустимые форматы:",
        "  1) Число: 500",
        "  1a) Время: 100 ms, 12 s, 250 us",
        "  2) Диапазон: 500:2:540 (start:step:stop)",
        "  3) Список: 500,510,520",
        "  4) Выражение: =round(wl/40)*20",
        "  5) Строка: \"SIG\"",
    ], "\n")
end

function _show_validation_dialog(win, errs::Dict{Symbol,String})
    isempty(errs) && return nothing
    fields = join(string.(collect(keys(errs))), ", ")
    msg = "Ошибки в полях: $fields"
    dialog = Gtk.MessageDialog(win, Gtk.DialogFlags.MODAL, Gtk.MessageType.ERROR, Gtk.ButtonsType.OK, msg)
    Gtk.set_gtk_property!(dialog, :secondary_text, _validation_help_text())
    Gtk.run(dialog)
    Gtk.destroy(dialog)
    return nothing
end

function _active_text(box, fallback::AbstractString)
    t = Gtk.GAccessor.active_text(box)
    (t === nothing || t == C_NULL) && return String(fallback)
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

function _combo_active_index(box)
    return Gtk.get_gtk_property(box, :active, Int) + 1
end

function _clear_combo_text!(box)
    ccall((:gtk_combo_box_text_remove_all, Gtk.libgtk), Nothing, (Ptr{Gtk.GObject},), box.handle)
    return nothing
end

function _set_combo_items!(box, labels::Vector{String})
    _clear_combo_text!(box)
    for label in labels
        push!(box, label)
    end
    Gtk.set_gtk_property!(box, :active, isempty(labels) ? -1 : 0)
    return nothing
end

function _with_blocked_signal(f::Function, widget, handler_id)
    if handler_id == 0
        return f()
    end
    Gtk.signal_handler_block(widget, handler_id)
    try
        return f()
    finally
        Gtk.signal_handler_unblock(widget, handler_id)
    end
end

function _set_entry_values!(entries::Dict{Symbol,AxisEntry}, raw_params::Vector{Pair{Symbol,String}})
    for entry in values(entries)
        Gtk.set_gtk_property!(entry.widget, :text, "")
    end
    for (name, value) in raw_params
        haskey(entries, name) || continue
        Gtk.set_gtk_property!(entries[name].widget, :text, value)
    end
    return nothing
end

function _update_plot_controls!(ui::GtkApp)
    mode_txt = _active_text(ui.mode_box, "line")
    Gtk.set_gtk_property!(ui.zbox, :sensitive, mode_txt == "heatmap")
    return nothing
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

function _render_signal_canvas!(ui::GtkApp, state::AppState)
    canvas = ui.canvas_signal
    ctx = _safe_canvas_ctx(canvas)
    ctx === nothing && return nothing
    w = Float64(Gtk.width(canvas))
    h = Float64(Gtk.height(canvas))
    ps = _plot_settings(ui)
    points = signal_points(state)
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
        ctx, w, h, raw_points(state);
        xaxis=:idx, yaxis=:value, mode=:line, zaxis=:value, log_scale=false, title="raw camera data",
    )
    Gtk.draw(canvas)
    return nothing
end

function _update_controls_state!(ui::GtkApp, state::AppState)
    running = is_measurement_active(state)
    focus_running = running && is_focus_mode(state)
    connected = state.devices.connected
    initialized = state.devices.initialized
    have_signal = !isempty(signal_points(state))

    Gtk.set_gtk_property!(ui.connect_btn, :sensitive, !running && !connected)
    Gtk.set_gtk_property!(ui.init_btn, :sensitive, !running && connected && !initialized)
    Gtk.set_gtk_property!(ui.disconnect_btn, :sensitive, !running && connected)
    Gtk.set_gtk_property!(ui.pick_dir_btn, :sensitive, !running)
    Gtk.set_gtk_property!(ui.scan_btn, :sensitive, !running && initialized && state.measurement.scan_params !== nothing)
    Gtk.set_gtk_property!(ui.focus_btn, :sensitive, !running && initialized && state.measurement.scan_params !== nothing)
    Gtk.set_gtk_property!(ui.stop_btn, :sensitive, running)
    Gtk.set_gtk_property!(ui.power_btn, :sensitive, initialized)
    Gtk.set_gtk_property!(ui.save_dat_btn, :sensitive, have_signal)
    Gtk.set_gtk_property!(ui.save_png_btn, :sensitive, have_signal)

    if !initialized && Gtk.GAccessor.active(ui.power_btn)
        Gtk.set_gtk_property!(ui.power_btn, :active, false)
    end

    for entry in values(ui.entries)
        Gtk.set_gtk_property!(entry.widget, :sensitive, !running || focus_running)
    end

    return nothing
end

function render!(ui::GtkApp, state::AppState)
    points = length(state.measurement.points)
    Gtk.set_gtk_property!(ui.status_label, :label, "measurement: $(state.measurement_state)")
    Gtk.set_gtk_property!(ui.device_label, :label, state.devices.status)
    Gtk.set_gtk_property!(ui.power_label, :label, "power: $(round(state.devices.current_power; digits=4))")
    Gtk.set_gtk_property!(ui.points_label, :label, "points: $(points)")
    file_lbl = state.measurement.last_saved_file === nothing ? "saved: -" : "saved: $(basename(state.measurement.last_saved_file))"
    Gtk.set_gtk_property!(ui.file_label, :label, file_lbl)
    Gtk.set_gtk_property!(ui.dir_label, :label, "dir: $(state.session.config.dir)")

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
    ui_channel,
    controller::Controller;
    title::AbstractString="SHades2.0",
)
    presets = load_presets!(controller)
    if isempty(presets)
        presets = [build_preset(presets, Pair{Symbol,String}[]; name="Preset 1")]
    end
    presets_ref = Ref(presets)
    selected_preset_idx = Ref(isempty(presets) ? 0 : 1)
    template_ref = Ref(copy(presets_ref[][selected_preset_idx[]].params))
    dispatch_raw_params!(controller, template_ref[])

    win = Gtk.Window(String(title), 980, 700)
    root = Gtk.Box(:v, 8)

    status_label = Gtk.Label("measurement: $(state.measurement_state)")
    device_label = Gtk.Label(state.devices.status)
    power_label = Gtk.Label("power: $(state.devices.current_power)")
    points_label = Gtk.Label("points: 0")
    file_label = Gtk.Label("saved: -")
    dir_label = Gtk.Label("dir: $(state.session.config.dir)")

    form, entries = _build_form_box(template_ref[])

    preset_box = Gtk.ComboBoxText()
    preset_add_btn = Gtk.Button("+")
    preset_del_btn = Gtk.Button("-")
    preset_controls = Gtk.Box(:h, 6)
    push!(preset_controls, Gtk.Label("Preset"))
    push!(preset_controls, preset_box)
    push!(preset_controls, preset_add_btn)
    push!(preset_controls, preset_del_btn)
    _set_combo_items!(preset_box, [p.name for p in presets_ref[]])

    connect_btn = Gtk.Button("Connect")
    init_btn = Gtk.Button("Init")
    disconnect_btn = Gtk.Button("Disconnect")
    pick_dir_btn = Gtk.Button("Output Dir")
    scan_btn = Gtk.Button("Scan")
    focus_btn = Gtk.Button("Focus")
    stop_btn = Gtk.Button("Stop")
    power_btn = Gtk.ToggleButton("Power Stabilization")
    save_dat_btn = Gtk.MenuItem("Save DAT")
    save_png_btn = Gtk.MenuItem("Save PNG")

    device_controls = Gtk.Box(:h, 8)
    push!(device_controls, connect_btn)
    push!(device_controls, init_btn)
    push!(device_controls, disconnect_btn)
    
    device_controls2 = Gtk.Box(:h, 8)
    push!(device_controls2, power_btn)
    push!(device_controls2, pick_dir_btn)

    measurement_controls = Gtk.Box(:h, 8)
    push!(measurement_controls, scan_btn)
    push!(measurement_controls, focus_btn)
    push!(measurement_controls, stop_btn)

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
    plot_menu = Gtk.Menu()
    push!(plot_menu, save_dat_btn)
    push!(plot_menu, save_png_btn)
    Gtk.showall(plot_menu)
    plots_paned = Gtk.Paned(:v)
    plots_paned[1] = canvas_signal
    plots_paned[2] = canvas_raw
    Gtk.signal_connect((w, alloc) -> Gtk.set_gtk_property!(w, :position, alloc.height ÷ 2), plots_paned, "size-allocate")
    Gtk.set_gtk_property!(plots_paned, :expand, true)
    Gtk.set_gtk_property!(plots_paned, :shrink, true)
    canvas_signal.mouse.button3press = (widget, event) -> Gtk.popup(plot_menu, event)
    canvas_raw.mouse.button3press = (widget, event) -> Gtk.popup(plot_menu, event)

    params_scroller = Gtk.Box(:h)
    #Gtk.set_gtk_property!(params_scroller, :vexpand, true)
    Gtk.set_gtk_property!(params_scroller, :vexpand, true)
    Gtk.set_gtk_property!(params_scroller, :hshrink, true)
    push!(params_scroller, form)

    params_expander = Gtk.Expander("Parameters")
    Gtk.set_gtk_property!(params_expander, :expanded, true)
    params_panel = Gtk.Box(:v, 8)
    push!(params_panel, preset_controls)
    push!(params_panel, params_scroller)
    push!(params_expander, params_panel)

    device_expander = Gtk.Expander("Devices")
    Gtk.set_gtk_property!(device_expander, :expanded, true)
    push!(device_expander, device_controls)

    measurement_expander = Gtk.Expander("Measurement")
    measurement_expander_panel = Gtk.Box(:v,8)
    Gtk.set_gtk_property!(measurement_expander, :expanded, true)
    push!(measurement_expander, measurement_expander_panel)
    push!(measurement_expander_panel, measurement_controls)
    push!(measurement_expander_panel, device_controls2)

    plot_expander = Gtk.Expander("Plot Settings")
    Gtk.set_gtk_property!(plot_expander, :expanded, true)
    push!(plot_expander, plot_controls)

    left_col = Gtk.Box(:v, 8)
    push!(left_col, device_expander)
    push!(left_col, measurement_expander)
    push!(left_col, params_expander)

    right_col = Gtk.Box(:v, 8)
    push!(right_col, plot_expander)
    push!(right_col, plots_paned)

    main_paned = Gtk.Box(:h)
    push!(main_paned, left_col)
    push!(main_paned, right_col)
    #main_paned[1] = left_col
    #main_paned[2] = right_col
    #Gtk.signal_connect((w, alloc) -> Gtk.set_gtk_property!(w, :position, Int(alloc.width * 0.35)), main_paned, "size-allocate")
    Gtk.set_gtk_property!(main_paned, :expand, true)
    Gtk.set_gtk_property!(main_paned, :shrink, true)

    status_bar = Gtk.Box(:h, 8)
    push!(status_bar, status_label)
    push!(status_bar, device_label)
    push!(status_bar, power_label)
    push!(status_bar, points_label)
    push!(status_bar, file_label)
    push!(status_bar, dir_label)
    
    Gtk.set_gtk_property!(status_bar, :shrink, true)

    push!(root, main_paned)
    push!(root, status_bar)
    push!(win, root)

    ui = GtkApp(
        win, entries,
        status_label, device_label, power_label, points_label, file_label, dir_label,
        xbox, ybox, zbox, mode_box, log_cb,
        connect_btn, init_btn, disconnect_btn, pick_dir_btn, scan_btn, focus_btn, stop_btn, power_btn, save_dat_btn, save_png_btn,
        canvas_signal, canvas_raw,
    )
    _gtk_install_error_css!(win)

    function _update_preset_controls!()
        Gtk.set_gtk_property!(preset_del_btn, :sensitive, !isempty(presets_ref[]))
        return nothing
    end

    function _apply_preset!(idx::Int)
        if idx < 1 || idx > length(presets_ref[])
            return nothing
        end
        selected_preset_idx[] = idx
        template_ref[] = copy(presets_ref[][idx].params)
        _set_entry_values!(ui.entries, template_ref[])
        raw_now, _ = _sync_form_params!()
        _gtk_clear_errors!(ui.entries)
        render!(ui, state)
        return raw_now
    end

    function _sync_form_params!()
        raw_now = _collect_raw_params(ui.entries, template_ref[])
        dispatch_raw_params!(controller, raw_now)
        errs = validation_errors(raw_now)
        _gtk_apply_errors!(ui.entries, errs)
        return raw_now, errs
    end

    function _maybe_update_focus_params!(raw_now, errs)
        isempty(errs) || return nothing
        if !(is_measurement_active(state) && is_focus_mode(state))
            return nothing
        end
        publish_focus_params!(controller, raw_now)
        return nothing
    end

    for entry in values(ui.entries)
        Gtk.signal_connect((_) -> begin
            raw_now, errs = _sync_form_params!()
            _maybe_update_focus_params!(raw_now, errs)
            return nothing
        end, entry.widget, "activate")
        Gtk.signal_connect((_) -> begin
            raw_now, errs = _sync_form_params!()
            _maybe_update_focus_params!(raw_now, errs)
            return nothing
        end, entry.widget, "editing-done")
    end

    function _refresh_lifecycle!()
        refresh_lifecycle!(controller)
        return nothing
    end

    preset_changed_handler = Ref{Culong}(0)

    function _refresh_preset_box!(idx::Int)
        labels = [p.name for p in presets_ref[]]
        active_idx = isempty(labels) ? 0 : clamp(idx, 1, length(labels))
        _with_blocked_signal(preset_box, preset_changed_handler[]) do
            _set_combo_items!(preset_box, labels)
            Gtk.set_gtk_property!(preset_box, :active, active_idx == 0 ? -1 : active_idx - 1)
        end
        selected_preset_idx[] = active_idx
        return active_idx
    end

    preset_changed_handler[] = Gtk.signal_connect(preset_box, "changed") do _
        idx = _combo_active_index(preset_box)
        _apply_preset!(idx)
        return nothing
    end

    Gtk.signal_connect(preset_add_btn, "clicked") do _
        raw_now = _collect_raw_params(ui.entries, template_ref[])
        preset = build_preset(presets_ref[], raw_now)
        presets_ref[] = append_preset!(controller, presets_ref[], preset)
        _update_preset_controls!()
        new_idx = _refresh_preset_box!(length(presets_ref[]))
        _apply_preset!(new_idx)
        return nothing
    end

    Gtk.signal_connect(preset_del_btn, "clicked") do _
        idx = _combo_active_index(preset_box)
        if idx < 1 || idx > length(presets_ref[])
            return nothing
        end
        presets_ref[] = delete_preset_at!(controller, presets_ref[], idx)
        _update_preset_controls!()
        if isempty(presets_ref[])
            _refresh_preset_box!(0)
        else
            new_idx = min(idx, length(presets_ref[]))
            _refresh_preset_box!(new_idx)
            _apply_preset!(new_idx)
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
        result = toggle_power_stabilization!(controller, state, Gtk.GAccessor.active(w))
        result.ok || (Gtk.GAccessor.active(w) && Gtk.set_gtk_property!(w, :active, false))
        return nothing
    end

    Gtk.signal_connect(pick_dir_btn, "clicked") do _
        path = Gtk.open_dialog("Select output folder", win, action=Gtk.GtkFileChooserAction.SELECT_FOLDER)
        path === nothing && return nothing
        chosen = isdir(path) ? path : dirname(path)
        select_output_dir!(controller, chosen)
        return nothing
    end

    Gtk.signal_connect(connect_btn, "clicked") do _
        connect_devices!(controller)
        return nothing
    end

    Gtk.signal_connect(init_btn, "clicked") do _
        init_devices!(controller)
        return nothing
    end

    Gtk.signal_connect(disconnect_btn, "clicked") do _
        Gtk.GAccessor.active(power_btn) && Gtk.set_gtk_property!(power_btn, :active, false)
        disconnect_devices!(controller)
        return nothing
    end

    Gtk.signal_connect(scan_btn, "clicked") do _
        raw_now = _collect_raw_params(ui.entries, template_ref[])
        result = start_scan!(controller, state, raw_now)
        errs = result.errors
        if !isempty(errs)
            _gtk_apply_errors!(ui.entries, errs)
            _show_validation_dialog(win, errs)
            return nothing
        else
            _gtk_clear_errors!(ui.entries)
        end
        return nothing
    end

    Gtk.signal_connect(focus_btn, "clicked") do _
        raw_now = _collect_raw_params(ui.entries, template_ref[])
        result = start_focus!(controller, state, raw_now)
        errs = result.errors
        if !isempty(errs)
            _gtk_apply_errors!(ui.entries, errs)
            _show_validation_dialog(win, errs)
            return nothing
        else
            _gtk_clear_errors!(ui.entries)
        end
        return nothing
    end

    Gtk.signal_connect(stop_btn, "clicked") do _
        stop_measurement!(controller)
        return nothing
    end

    Gtk.signal_connect(save_dat_btn, "activate") do _
        pts = signal_points(state)
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

    Gtk.signal_connect(save_png_btn, "activate") do _
        pts = signal_points(state)
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
        Gtk.gtk_main_running[] && Gtk.gtk_quit()
        return nothing
    end

    Gtk.showall(win)
    _update_plot_controls!(ui)
    _update_preset_controls!()
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
