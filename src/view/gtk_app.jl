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

function _render_signal_canvas!(
    canvas,
    state::AppState,
    xaxis::Symbol,
    yaxis::Symbol;
    mode::Symbol=:line,
    zaxis::Symbol=:sig,
    log_scale::Bool=false
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
    render_signal_plot!(ctx, w, h, state.points; xaxis=xaxis, yaxis=yaxis, mode=mode, zaxis=zaxis, log_scale=log_scale)
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
    cam_temp = Gtk.Entry(); Gtk.set_gtk_property!(cam_temp, :text, "")
    stab_duration_val = Ref(5.0)
    stab_kp_val = Ref(0.5)

    inter = Gtk.Entry(); Gtk.set_gtk_property!(inter, :text, "SIG")
    acq_ms = Gtk.Entry(); Gtk.set_gtk_property!(acq_ms, :text, "50")
    frames = Gtk.Entry(); Gtk.set_gtk_property!(frames, :text, "2")
    delay_s = Gtk.Entry(); Gtk.set_gtk_property!(delay_s, :text, "0.01")
    out_dir = Gtk.Entry(); Gtk.set_gtk_property!(out_dir, :text, default_output_dir)

    xbox = Gtk.ComboBoxText(); ybox = Gtk.ComboBoxText()
    zbox = Gtk.ComboBoxText()
    mode_box = Gtk.ComboBoxText()
    log_cb = Gtk.CheckButton("Log10")
    axis_choices = String.([:wl, :polarizer, :analyzer, :power, :loop, :real_power, :sig, :time_s])
    for c in axis_choices
        push!(xbox, c)
        push!(ybox, c)
        push!(zbox, c)
    end
    for m in ("line", "polar", "heatmap")
        push!(mode_box, m)
    end
    Gtk.set_gtk_property!(xbox, :active, 0)
    Gtk.set_gtk_property!(ybox, :active, 6)
    Gtk.set_gtk_property!(zbox, :active, 6)
    Gtk.set_gtk_property!(mode_box, :active, 0)
    Gtk.set_gtk_property!(log_cb, :active, false)

    run_btn = Gtk.Button("Run")
    focus_btn = Gtk.Button("Focus")
    stop_btn = Gtk.Button("Stop")
    pause_btn = Gtk.ToggleButton("Pause")
    stab_btn = Gtk.Button("Stabilize")
    preset_open_btn = Gtk.Button("Open preset...")
    preset_save_btn = Gtk.Button("Save preset...")
    save_raw_btn = Gtk.Button("Save raw...")
    save_spec_dat_btn = Gtk.Button("Save spectrum .dat...")
    save_spec_png_btn = Gtk.Button("Save spectrum .png...")
    status = Gtk.Label("Idle")

    rows = [
        ("wl spec", wl_spec),
        ("sol_wl spec", sol_spec),
        ("polarizer spec", pol_spec),
        ("analyzer spec", ana_spec),
        ("power spec", power_spec),
        ("camera temp (C)", cam_temp),
        ("interaction", inter),
        ("acq time (ms)", acq_ms),
        ("frames", frames),
        ("delay (s)", delay_s),
        #("output dir", out_dir),
        ("plot X", xbox),
        ("plot Y", ybox),
        ("plot C (heatmap)", zbox),
        ("plot mode", mode_box),
        ("log scale", log_cb),
    ]

    for (i, (lbl, w)) in enumerate(rows)
        form[1, i] = Gtk.Label(lbl)
        form[2, i] = w
    end

    btn_row = Gtk.Box(:h)
    push!(btn_row, run_btn)
    push!(btn_row, focus_btn)
    push!(btn_row, pause_btn)
    push!(btn_row, stop_btn)
    push!(btn_row, stab_btn)
    push!(btn_row, preset_open_btn)
    push!(btn_row, preset_save_btn)
    push!(btn_row, save_raw_btn)
    push!(btn_row, save_spec_dat_btn)
    push!(btn_row, save_spec_png_btn)

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

    function _opt_float(entry)::Union{Nothing,Float64}
        txt = strip(Gtk.get_gtk_property(entry, "text", String))
        isempty(txt) && return nothing
        return _safe_parse_float(txt, NaN)
    end

    function _axis_first_value(name::Symbol, spec::AbstractString; wl::Union{Nothing,Float64}=nothing)
        ax = parse_axis_spec(name, spec; numeric_only=true)
        ax === nothing && return nothing
        if ax isa FixedAxis
            return Float64(ax.value)
        elseif ax isa IndependentAxis
            isempty(ax.values) && return nothing
            return Float64(ax.values[1])
        elseif ax isa DependentAxis
            ax.depends_on == :wl || error("Dependent axis '$name' requires '$(ax.depends_on)'")
            wl === nothing && error("Dependent axis '$name' needs wl")
            return Float64(ax.f(wl))
        else
            error("Axis '$name' is not supported for focus mode")
        end
    end

    function _update_entries_from_params!(p::ScanParams)
        if !isempty(p.wavelengths)
            txt = length(p.wavelengths) == 1 ? string(p.wavelengths[1]) : join(p.wavelengths, ",")
            Gtk.set_gtk_property!(wl_spec, :text, txt)
        end
        Gtk.set_gtk_property!(inter, :text, p.interaction)
        Gtk.set_gtk_property!(acq_ms, :text, string(round(Int, p.acq_time_s * 1000)))
        Gtk.set_gtk_property!(frames, :text, string(p.frames))
        Gtk.set_gtk_property!(delay_s, :text, string(p.delay_s))
        Gtk.set_gtk_property!(pol_spec, :text, string(p.polarizer_deg))
        Gtk.set_gtk_property!(ana_spec, :text, string(p.analyzer_deg))
        if p.fixed_sol_wavelength !== nothing
            Gtk.set_gtk_property!(sol_spec, :text, string(p.fixed_sol_wavelength))
        end
        if p.camera_temp_c !== nothing
            Gtk.set_gtk_property!(cam_temp, :text, string(p.camera_temp_c))
        end
    end

    function _set_combo_text!(box, text::String)
        n = Gtk.GAccessor.n_items(box)
        for i in 0:(n - 1)
            if Gtk.bytestring(Gtk.GAccessor.get_text(box, i)) == text
                Gtk.set_gtk_property!(box, :active, i)
                return
            end
        end
    end

    function _collect_preset_state()
        return Dict{String,Any}(
            "wl_spec" => Gtk.get_gtk_property(wl_spec, "text", String),
            "sol_spec" => Gtk.get_gtk_property(sol_spec, "text", String),
            "pol_spec" => Gtk.get_gtk_property(pol_spec, "text", String),
            "ana_spec" => Gtk.get_gtk_property(ana_spec, "text", String),
            "power_spec" => Gtk.get_gtk_property(power_spec, "text", String),
            "cam_temp" => Gtk.get_gtk_property(cam_temp, "text", String),
            "inter" => Gtk.get_gtk_property(inter, "text", String),
            "acq_ms" => Gtk.get_gtk_property(acq_ms, "text", String),
            "frames" => Gtk.get_gtk_property(frames, "text", String),
            "delay_s" => Gtk.get_gtk_property(delay_s, "text", String),
            "plot_x" => Gtk.bytestring(Gtk.GAccessor.active_text(xbox)),
            "plot_y" => Gtk.bytestring(Gtk.GAccessor.active_text(ybox)),
            "plot_z" => Gtk.bytestring(Gtk.GAccessor.active_text(zbox)),
            "plot_mode" => Gtk.bytestring(Gtk.GAccessor.active_text(mode_box)),
            "plot_log" => Gtk.GAccessor.active(log_cb),
            "stab_duration" => stab_duration_val[],
            "stab_kp" => stab_kp_val[],
        )
    end

    function _apply_preset_state!(d::Dict{String,Any})
        haskey(d, "wl_spec") && Gtk.set_gtk_property!(wl_spec, :text, string(d["wl_spec"]))
        haskey(d, "sol_spec") && Gtk.set_gtk_property!(sol_spec, :text, string(d["sol_spec"]))
        haskey(d, "pol_spec") && Gtk.set_gtk_property!(pol_spec, :text, string(d["pol_spec"]))
        haskey(d, "ana_spec") && Gtk.set_gtk_property!(ana_spec, :text, string(d["ana_spec"]))
        haskey(d, "power_spec") && Gtk.set_gtk_property!(power_spec, :text, string(d["power_spec"]))
        haskey(d, "cam_temp") && Gtk.set_gtk_property!(cam_temp, :text, string(d["cam_temp"]))
        haskey(d, "inter") && Gtk.set_gtk_property!(inter, :text, string(d["inter"]))
        haskey(d, "acq_ms") && Gtk.set_gtk_property!(acq_ms, :text, string(d["acq_ms"]))
        haskey(d, "frames") && Gtk.set_gtk_property!(frames, :text, string(d["frames"]))
        haskey(d, "delay_s") && Gtk.set_gtk_property!(delay_s, :text, string(d["delay_s"]))
        haskey(d, "plot_x") && _set_combo_text!(xbox, string(d["plot_x"]))
        haskey(d, "plot_y") && _set_combo_text!(ybox, string(d["plot_y"]))
        haskey(d, "plot_z") && _set_combo_text!(zbox, string(d["plot_z"]))
        haskey(d, "plot_mode") && _set_combo_text!(mode_box, string(d["plot_mode"]))
        haskey(d, "plot_log") && Gtk.set_gtk_property!(log_cb, :active, Bool(d["plot_log"]))
        haskey(d, "stab_duration") && (stab_duration_val[] = Float64(d["stab_duration"]))
        haskey(d, "stab_kp") && (stab_kp_val[] = Float64(d["stab_kp"]))
    end

    function _build_params_from_entries(; require_wl::Bool=false)
        wl_txt = strip(Gtk.get_gtk_property(wl_spec, "text", String))
        wl_val = _axis_first_value(:wl, wl_txt)
        (wl_val === nothing && require_wl) && error("wl spec is empty")
        wl_val === nothing && (wl_val = 0.0)

        sol_txt = strip(Gtk.get_gtk_property(sol_spec, "text", String))
        sol_val = isempty(sol_txt) ? nothing : _axis_first_value(:sol_wl, sol_txt; wl=wl_val)

        inter_txt = strip(Gtk.get_gtk_property(inter, "text", String))
        inter_txt = isempty(inter_txt) ? "SIG" : inter_txt

        acq_s = max(_safe_parse_int(Gtk.get_gtk_property(acq_ms, "text", String), 50), 1) / 1000
        fr = max(_safe_parse_int(Gtk.get_gtk_property(frames, "text", String), 1), 1)
        dly = max(_safe_parse_float(Gtk.get_gtk_property(delay_s, "text", String), 0.01), 0.0)
        pol = _safe_parse_float(Gtk.get_gtk_property(pol_spec, "text", String), 0.0)
        ana = _safe_parse_float(Gtk.get_gtk_property(ana_spec, "text", String), 0.0)
        ct = _opt_float(cam_temp)

        return ScanParams(
            wavelengths=[wl_val],
            interaction=inter_txt,
            acq_time_s=acq_s,
            frames=fr,
            delay_s=dly,
            fixed_sol_wavelength=sol_val,
            polarizer_deg=pol,
            analyzer_deg=ana,
            camera_temp_c=ct,
        )
    end

    function refresh_plots!()
        xaxis = Symbol(Gtk.bytestring(Gtk.GAccessor.active_text(xbox)))
        yaxis = Symbol(Gtk.bytestring(Gtk.GAccessor.active_text(ybox)))
        zaxis = Symbol(Gtk.bytestring(Gtk.GAccessor.active_text(zbox)))
        mode = Symbol(Gtk.bytestring(Gtk.GAccessor.active_text(mode_box)))
        log_scale = Gtk.GAccessor.active(log_cb)
        _render_signal_canvas!(canvas_signal, state, xaxis, yaxis; mode=mode, zaxis=zaxis, log_scale=log_scale)
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
            cam_t = _opt_float(cam_temp)

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
            cam_t !== nothing && set_camera_temperature!(devices.camera, cam_t)

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

    Gtk.signal_connect(focus_btn, "clicked") do _
        try
            if session_ref[] !== nothing
                stop_measurement!(session_ref[])
                session_ref[] = nothing
            end

            params = _build_params_from_entries(require_wl=true)

            session = start_focus_measurement(devices, params)
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

    Gtk.signal_connect(stab_btn, "clicked") do _
        try
            pow_txt = strip(Gtk.get_gtk_property(power_spec, "text", String))
            tgt = _axis_first_value(:power, pow_txt)
            dur = stab_duration_val[]
            kp = stab_kp_val[]
            tgt === nothing && error("power spec is empty")
            state.status = "Stabilizing..."
            refresh_plots!()
            @async begin
                try
                    stabilize_power!(devices; target_power=Float64(tgt), duration_s=dur, k_p=kp)
                    state.status = "Stabilized"
                catch e
                    state.status = "Error: $(sprint(showerror, e))"
                end
                refresh_plots!()
            end
        catch e
            state.status = "Error: $(sprint(showerror, e))"
            refresh_plots!()
        end
    end

    Gtk.signal_connect(preset_save_btn, "clicked") do _
        try
            state_dict = _collect_preset_state()
            path = Gtk.save_dialog("Save preset", win)
            path === nothing && return
            save_preset_state(path, state_dict)
            state.status = "Preset saved"
            refresh_plots!()
        catch e
            state.status = "Error: $(sprint(showerror, e))"
            refresh_plots!()
        end
    end

    Gtk.signal_connect(preset_open_btn, "clicked") do _
        try
            path = Gtk.open_dialog("Open preset", win)
            path === nothing && return
            state_dict = load_preset_state(path)
            _apply_preset_state!(state_dict)
            state.status = "Preset loaded"
            refresh_plots!()
        catch e
            state.status = "Error: $(sprint(showerror, e))"
            refresh_plots!()
        end
    end

    Gtk.signal_connect(save_raw_btn, "clicked") do _
        try
            isempty(state.last_raw) && error("No raw data")
            path = Gtk.save_dialog("Save raw spectrum", win)
            path === nothing && return
            params = isempty(state.points) ? Dict{Symbol,Any}() : state.points[end]
            save_raw_spectrum(path, state.last_raw; params=params)
            state.status = "Raw saved"
            refresh_plots!()
        catch e
            state.status = "Error: $(sprint(showerror, e))"
            refresh_plots!()
        end
    end

    Gtk.signal_connect(save_spec_dat_btn, "clicked") do _
        try
            state.spectrum === nothing && error("No spectrum")
            path = Gtk.save_dialog("Save spectrum .dat", win)
            path === nothing && return
            save_spectrum_dat(path, state.spectrum)
            state.status = "Spectrum .dat saved"
            refresh_plots!()
        catch e
            state.status = "Error: $(sprint(showerror, e))"
            refresh_plots!()
        end
    end

    Gtk.signal_connect(save_spec_png_btn, "clicked") do _
        try
            state.spectrum === nothing && error("No spectrum")
            path = Gtk.save_dialog("Save spectrum .png", win)
            path === nothing && return
            xaxis = Symbol(Gtk.bytestring(Gtk.GAccessor.active_text(xbox)))
            yaxis = Symbol(Gtk.bytestring(Gtk.GAccessor.active_text(ybox)))
            zaxis = Symbol(Gtk.bytestring(Gtk.GAccessor.active_text(zbox)))
            mode = Symbol(Gtk.bytestring(Gtk.GAccessor.active_text(mode_box)))
            log_scale = Gtk.GAccessor.active(log_cb)
            out = save_plot_from_points(path, state.points; xaxis=xaxis, yaxis=yaxis, zaxis=zaxis, mode=mode, log_scale=log_scale)
            state.status = "Spectrum .png saved: $out"
            refresh_plots!()
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
    Gtk.signal_connect(zbox, "changed") do _
        refresh_plots!()
    end
    Gtk.signal_connect(mode_box, "changed") do _
        refresh_plots!()
    end
    Gtk.signal_connect(log_cb, "toggled") do _
        refresh_plots!()
    end

    preset_autopath = joinpath(pwd(), "preset.json")
    try
        isfile(preset_autopath) && _apply_preset_state!(load_preset_state(preset_autopath))
    catch
    end

    Gtk.signal_connect(win, "destroy") do _
        try
            state_dict = _collect_preset_state()
            save_preset_state(preset_autopath, state_dict)
        catch
        end
        if session_ref[] !== nothing
            stop_measurement!(session_ref[])
        end
    end

    refresh_plots!()
    Gtk.showall(win)
    Gtk.gtk_main()
    return nothing
end
