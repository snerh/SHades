using Dates

Base.@kwdef mutable struct GtkLegacyAppCtx
    win
    state::AppState
    session_ref::Base.RefValue{Union{Nothing,MeasurementSession}}
    form_refs::GtkLegacyFormRefs
    plot_refs::GtkLegacyPlotRefs
    spec_entries::Dict{Symbol,Any}
    field_error_labels::Dict{Symbol,Any}
    stab_duration_val::Base.RefValue{Float64}
    stab_kp_val::Base.RefValue{Float64}
    error_css_provider
    status
    canvas_signal
    canvas_raw
    run_btn
    focus_btn
    stop_btn
    pause_btn
    stab_btn
    preset_open_btn
    preset_save_btn
    save_raw_btn
    out_dir_pick_btn
    history_combo
    history_repeat_btn
    queue_combo
    queue_add_btn
    queue_run_btn
    queue_remove_btn
    compare_add_btn
    compare_clear_btn
    autosave_every_entry
    save_spec_dat_item
    save_spec_png_item
    spectrum_menu
    autosave_path::String
    history_entries::Vector{Any}
    queue_items::Vector{Any}
    queue_running::Base.RefValue{Bool}
    compare_overlays::Vector{NamedTuple{(:label, :points, :color),Tuple{String,Vector{ScanPoint},NTuple{3,Float64}}}}
    current_run_label::Base.RefValue{String}
    current_run_kind::Base.RefValue{Symbol}
    xbox
    ybox
    zbox
    mode_box
    log_cb
end

function _stop_active_session!(ctx::GtkLegacyAppCtx; timeout_s::Float64=5.0)
    session = ctx.session_ref[]
    session === nothing && return true
    ok = stop_and_wait!(session; timeout_s=timeout_s)
    ctx.session_ref[] = nothing
    return ok
end

function _gtk_session_active(ctx::GtkLegacyAppCtx)
    session = ctx.session_ref[]
    session === nothing && return false
    return !istaskdone(session.task)
end

function _gtk_sync_controls_state!(ctx::GtkLegacyAppCtx)
    running = _gtk_session_active(ctx)
    queue_busy = ctx.queue_running[]
    Gtk.set_gtk_property!(ctx.run_btn, :sensitive, !running)
    Gtk.set_gtk_property!(ctx.focus_btn, :sensitive, !running)
    Gtk.set_gtk_property!(ctx.stab_btn, :sensitive, !running)
    Gtk.set_gtk_property!(ctx.stop_btn, :sensitive, running)
    Gtk.set_gtk_property!(ctx.pause_btn, :sensitive, running)
    Gtk.set_gtk_property!(ctx.history_repeat_btn, :sensitive, !running && !isempty(ctx.history_entries))
    Gtk.set_gtk_property!(ctx.queue_add_btn, :sensitive, !running && !queue_busy)
    Gtk.set_gtk_property!(ctx.queue_run_btn, :sensitive, !running && !isempty(ctx.queue_items) && !queue_busy)
    Gtk.set_gtk_property!(ctx.queue_remove_btn, :sensitive, !running && !isempty(ctx.queue_items) && !queue_busy)
    Gtk.set_gtk_property!(ctx.compare_add_btn, :sensitive, !isempty(ctx.state.points))
    Gtk.set_gtk_property!(ctx.compare_clear_btn, :sensitive, !isempty(ctx.compare_overlays))
    if !running && Gtk.GAccessor.active(ctx.pause_btn)
        Gtk.set_gtk_property!(ctx.pause_btn, :active, false)
    end
    return nothing
end

function _gtk_try_parse_int(txt::String)
    v = parse(Int, strip(txt))
    v > 0 || error("must be a positive integer")
    return v
end

function _gtk_try_parse_float(txt::String)
    return parse(Float64, replace(strip(txt), "," => "."))
end

function _gtk_validate_common_fields!(errs::Dict{Symbol,String}, data::LegacyFormData)
    try
        _gtk_try_parse_int(data.acq_ms)
    catch e
        errs[:acq_ms] = sprint(showerror, e)
    end
    try
        _gtk_try_parse_int(data.frames)
    catch e
        errs[:frames] = sprint(showerror, e)
    end
    try
        dly = _gtk_try_parse_float(data.delay_s)
        dly >= 0 || error("must be >= 0")
    catch e
        errs[:delay_s] = sprint(showerror, e)
    end
    if !isempty(strip(data.cam_temp))
        try
            _gtk_try_parse_float(data.cam_temp)
        catch e
            errs[:cam_temp] = sprint(showerror, e)
        end
    end
    return errs
end

function _gtk_validate_run_request(data::LegacyFormData)
    req = build_run_request(data)
    errs = Dict{Symbol,String}()
    _gtk_validate_common_fields!(errs, data)
    merge!(errs, req.errors)
    return (
        ok = isempty(errs) && req.ok,
        request = req,
        errors = errs,
    )
end

function _gtk_validate_focus_request(data::LegacyFormData)
    errs = Dict{Symbol,String}()
    _gtk_validate_common_fields!(errs, data)

    wl_txt = strip(data.wl_spec)
    wl_val = nothing
    if isempty(wl_txt)
        errs[:wl] = "wl spec is empty"
    else
        try
            wl_val = _axis_first_value(:wl, wl_txt)
            wl_val === nothing && error("wl spec is empty")
        catch e
            errs[:wl] = sprint(showerror, e)
        end
    end

    sol_txt = strip(data.sol_spec)
    if !isempty(sol_txt) && wl_val !== nothing
        try
            _axis_first_value(:sol_wl, sol_txt; wl=wl_val)
        catch e
            errs[:sol_wl] = sprint(showerror, e)
        end
    end

    for (key, txt) in ((:polarizer, data.pol_spec), (:analyzer, data.ana_spec))
        t = strip(txt)
        if !isempty(t)
            try
                _gtk_try_parse_float(t)
            catch e
                errs[key] = sprint(showerror, e)
            end
        end
    end

    if !isempty(errs)
        return (ok=false, params=nothing, errors=errs)
    end

    params = build_focus_params(data; require_wl=true)
    return (ok=true, params=params, errors=Dict{Symbol,String}())
end

function _gtk_validate_stabilize_request(data::LegacyFormData)
    errs = Dict{Symbol,String}()
    ptxt = strip(data.power_spec)
    if isempty(ptxt)
        errs[:power] = "power spec is empty"
    else
        try
            _axis_first_value(:power, ptxt)
        catch e
            errs[:power] = sprint(showerror, e)
        end
    end
    if !isempty(errs)
        return (ok=false, request=nothing, errors=errs)
    end
    return (ok=true, request=build_stabilize_request(data), errors=Dict{Symbol,String}())
end

function _gtk_validation_summary(errs::Dict{Symbol,String})
    items = sort(collect(errs); by=x -> string(x[1]))
    chunks = ["$(k): $(v)" for (k, v) in items]
    return isempty(chunks) ? "Validation error" : "Validation error: $(join(chunks, " | "))"
end

function _gtk_axis_points(ax::ScanAxis)::Union{Nothing,Int}
    if ax isa IndependentAxis
        return length(ax.values)
    elseif ax isa LoopAxis
        ax.stop === nothing && return nothing
        ax.step <= 0 && return nothing
        ax.stop < ax.start && return 0
        return Int(fld(ax.stop - ax.start, ax.step) + 1)
    end
    return 1
end

function _gtk_estimate_total_steps(plan::ScanPlan)::Union{Nothing,Int}
    total = 1
    for ax in plan.axes
        n = _gtk_axis_points(ax)
        n === nothing && return nothing
        total *= n
    end
    return total
end

function _gtk_format_duration(total_s::Float64)
    total = max(round(Int, total_s), 0)
    h = total ÷ 3600
    m = (total % 3600) ÷ 60
    s = total % 60
    if h > 0
        return lpad(string(h), 2, '0') * ":" * lpad(string(m), 2, '0') * ":" * lpad(string(s), 2, '0')
    end
    return lpad(string(m), 2, '0') * ":" * lpad(string(s), 2, '0')
end

function _gtk_progress_status(state::AppState)
    n = max(state.progress_step, 0)
    total = state.progress_total
    step_text = total === nothing ? "$(n)/?" : "$(n)/$(total)"

    wl_text = "-"
    if state.current_wl !== nothing
        wl_text = string(round(state.current_wl, digits=3)) * " nm"
    end

    eta_text = "--:--"
    if total !== nothing && state.started_at !== nothing && n > 0
        left = max(total - n, 0)
        elapsed = time() - state.started_at
        if elapsed >= 0
            eta_text = _gtk_format_duration((elapsed / n) * left)
        end
    end

    return "Step $(step_text) | wl=$(wl_text) | ETA $(eta_text)"
end

function _gtk_status_text(state::AppState)
    state.running || return state.status
    return _gtk_progress_status(state)
end

function _gtk_combo_active_index1(combo)::Int
    idx0 = Gtk.get_gtk_property(combo, :active, Int)
    return idx0 + 1
end

function _gtk_overlay_color(i::Int)::NTuple{3,Float64}
    palette = (
        (0.77, 0.20, 0.19),
        (0.14, 0.55, 0.22),
        (0.73, 0.49, 0.10),
        (0.53, 0.20, 0.70),
        (0.02, 0.53, 0.67),
        (0.58, 0.36, 0.17),
    )
    return palette[mod1(i, length(palette))]
end

function _gtk_now_hms()
    return Dates.format(Dates.now(), "HH:MM:SS")
end

function _gtk_refresh_history_widget!(ctx::GtkLegacyAppCtx)
    empty!(ctx.history_combo)
    for (i, item) in enumerate(ctx.history_entries)
        push!(ctx.history_combo, "$(i). $(item.label)")
    end
    if !isempty(ctx.history_entries)
        Gtk.set_gtk_property!(ctx.history_combo, :active, length(ctx.history_entries) - 1)
    end
    return nothing
end

function _gtk_refresh_queue_widget!(ctx::GtkLegacyAppCtx)
    empty!(ctx.queue_combo)
    for (i, item) in enumerate(ctx.queue_items)
        push!(ctx.queue_combo, "$(i). $(item.label)")
    end
    if !isempty(ctx.queue_items)
        Gtk.set_gtk_property!(ctx.queue_combo, :active, 0)
    end
    return nothing
end

function _gtk_push_history!(ctx::GtkLegacyAppCtx, label::String, kind::Symbol, state_dict::Dict{String,Any})
    push!(ctx.history_entries, (label=label, kind=kind, state=deepcopy(state_dict)))
    if length(ctx.history_entries) > 50
        deleteat!(ctx.history_entries, 1)
    end
    _gtk_refresh_history_widget!(ctx)
    return nothing
end

function _gtk_push_overlay_from_points!(ctx::GtkLegacyAppCtx, label::String, points::Vector{ScanPoint})
    isempty(points) && return nothing
    color = _gtk_overlay_color(length(ctx.compare_overlays) + 1)
    push!(ctx.compare_overlays, (label=label, points=copy(points), color=color))
    if length(ctx.compare_overlays) > 8
        deleteat!(ctx.compare_overlays, 1)
    end
    return nothing
end

function _gtk_autosave_every_n(ctx::GtkLegacyAppCtx)::Int
    txt = Gtk.get_gtk_property(ctx.autosave_every_entry, "text", String)
    s = strip(txt)
    isempty(s) && return 0
    try
        n = parse(Int, s)
        return n > 0 ? n : 0
    catch
        return 0
    end
end

function _gtk_scanpoint_to_toml_dict(p::ScanPoint)
    d = Dict{String,Any}()
    for (k, v) in scan_point_to_dict(p)
        d[String(k)] = v
    end
    return d
end

function _gtk_toml_dict_to_scanpoint(d)::Union{Nothing,ScanPoint}
    d isa AbstractDict || return nothing
    p = Dict{Symbol,Any}()
    for (k, v) in pairs(d)
        p[Symbol(String(k))] = v
    end
    return scan_point_from_params(p)
end

function _gtk_write_autosave!(ctx::GtkLegacyAppCtx; force::Bool=false)
    if !force
        every = _gtk_autosave_every_n(ctx)
        every <= 0 && return nothing
        step = max(ctx.state.progress_step, 0)
        (step == 0 || step % every != 0) && return nothing
    end

    dump_points = [_gtk_scanpoint_to_toml_dict(p) for p in ctx.state.points]
    snapshot = Dict{String,Any}(
        "saved_at" => string(Dates.now()),
        "form_state" => _gtk_collect_preset_state(ctx.form_refs, ctx.plot_refs, ctx.stab_duration_val, ctx.stab_kp_val),
        "points" => dump_points,
        "last_raw" => collect(ctx.state.last_raw),
        "status" => ctx.state.status,
        "progress_step" => ctx.state.progress_step,
        "run_label" => ctx.current_run_label[],
        "run_kind" => String(ctx.current_run_kind[]),
    )
    save_preset_state(ctx.autosave_path, snapshot)
    return nothing
end

function _gtk_clear_autosave!(ctx::GtkLegacyAppCtx)
    isfile(ctx.autosave_path) || return nothing
    try
        rm(ctx.autosave_path)
    catch
    end
    return nothing
end

function _gtk_try_restore_autosave!(ctx::GtkLegacyAppCtx)
    isfile(ctx.autosave_path) || return false
    d = try
        load_preset_state(ctx.autosave_path)
    catch
        return false
    end

    form_state = get(d, "form_state", nothing)
    if form_state isa AbstractDict
        _gtk_apply_preset_state!(Dict{String,Any}(String(k) => v for (k, v) in pairs(form_state)), ctx.form_refs, ctx.plot_refs, ctx.stab_duration_val, ctx.stab_kp_val)
    end

    raw_points = get(d, "points", Any[])
    empty!(ctx.state.points)
    if raw_points isa AbstractVector
        for row in raw_points
            sp = _gtk_toml_dict_to_scanpoint(row)
            sp === nothing || push!(ctx.state.points, sp)
        end
    end
    _maybe_update_spectrum_from_points!(ctx.state)

    raw = get(d, "last_raw", Any[])
    if raw isa AbstractVector
        try
            ctx.state.last_raw = Float64.(raw)
        catch
            ctx.state.last_raw = Float64[]
        end
    end

    ctx.state.progress_step = Int(get(d, "progress_step", length(ctx.state.points)))
    ctx.state.status = "Recovered autosave: $(length(ctx.state.points)) points"
    return true
end

function _gtk_make_history_label(kind::Symbol, data::LegacyFormData)
    base = kind == :focus ? "Focus" : "Run"
    wl = strip(data.wl_spec)
    wl = isempty(wl) ? "wl=?" : "wl=$(wl)"
    return "[$(_gtk_now_hms())] $(base), $(wl)"
end

function _gtk_slug(s::String)
    t = replace(strip(s), r"[^0-9A-Za-z._-]+" => "_")
    return isempty(t) ? "item" : t
end

function _gtk_run_req_with_output_dir(req, out_dir::String)
    return (
        ok = req.ok,
        plan = req.plan,
        errors = req.errors,
        delay_s = req.delay_s,
        output_dir = out_dir,
        camera_temp_c = req.camera_temp_c,
    )
end

function _gtk_select_folder_dialog(title::String, parent; start_dir::String="")
    dlg = Gtk.GtkFileChooserDialog(
        title,
        parent,
        Gtk.GConstants.GtkFileChooserAction.SELECT_FOLDER,
        (
            ("_Cancel", Gtk.GConstants.GtkResponseType.CANCEL),
            ("_Select", Gtk.GConstants.GtkResponseType.ACCEPT),
        ),
    )
    chooser = Gtk.GtkFileChooser(dlg)
    if !isempty(start_dir)
        try
            Gtk.GAccessor.current_folder(chooser, start_dir)
        catch
        end
    end
    resp = Gtk.run(dlg)
    selected = ""
    if resp == Gtk.GConstants.GtkResponseType.ACCEPT
        try
            selected = Gtk.bytestring(Gtk.GAccessor.filename(chooser))
        catch
            selected = ""
        end
    end
    Gtk.destroy(dlg)
    return isempty(strip(selected)) ? nothing : selected
end

function _gtk_resolve_output_base_dir!(ctx::GtkLegacyAppCtx; prompt_if_empty::Bool=true)
    current = strip(Gtk.get_gtk_property(ctx.form_refs.out_dir, "text", String))
    if isempty(current) && prompt_if_empty
        start_dir = pwd()
        picked = _gtk_select_folder_dialog("Select output folder", ctx.win; start_dir=start_dir)
        picked === nothing && return nothing
        current = picked
        Gtk.set_gtk_property!(ctx.form_refs.out_dir, :text, current)
    end
    isempty(current) && return nothing
    mkpath(current)
    return current
end

function _build_legacy_app_ui(title::String, default_output_dir::String)
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

    form_refs = GtkLegacyFormRefs(
        wl_spec=wl_spec,
        sol_spec=sol_spec,
        pol_spec=pol_spec,
        ana_spec=ana_spec,
        power_spec=power_spec,
        cam_temp=cam_temp,
        inter=inter,
        acq_ms=acq_ms,
        frames=frames,
        delay_s=delay_s,
        out_dir=out_dir,
    )

    xbox = Gtk.ComboBoxText(); ybox = Gtk.ComboBoxText()
    zbox = Gtk.ComboBoxText()
    mode_box = Gtk.ComboBoxText()
    log_cb = Gtk.CheckButton("Log10")
    plot_refs = GtkLegacyPlotRefs(xbox=xbox, ybox=ybox, zbox=zbox, mode_box=mode_box, log_cb=log_cb)

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
    out_dir_pick_btn = Gtk.Button("Browse...")
    history_combo = Gtk.ComboBoxText()
    history_repeat_btn = Gtk.Button("Repeat selected")
    queue_combo = Gtk.ComboBoxText()
    queue_add_btn = Gtk.Button("Queue current")
    queue_run_btn = Gtk.Button("Run queue")
    queue_remove_btn = Gtk.Button("Remove queued")
    compare_add_btn = Gtk.Button("Add current curve")
    compare_clear_btn = Gtk.Button("Clear compare")
    autosave_every_entry = Gtk.Entry()
    Gtk.set_gtk_property!(autosave_every_entry, :text, "10")
    save_spec_dat_item = Gtk.MenuItem("Save spectrum .dat...")
    save_spec_png_item = Gtk.MenuItem("Save spectrum .png...")
    spectrum_menu = Gtk.Menu()
    push!(spectrum_menu, save_spec_dat_item)
    push!(spectrum_menu, save_spec_png_item)
    Gtk.showall(spectrum_menu)
    status = Gtk.Label("Idle")

    out_dir_row = Gtk.Box(:h)
    push!(out_dir_row, out_dir)
    push!(out_dir_row, out_dir_pick_btn)

    rows = [
        (:wl, "wl spec", wl_spec),
        (:sol_wl, "sol_wl spec", sol_spec),
        (:polarizer, "polarizer spec", pol_spec),
        (:analyzer, "analyzer spec", ana_spec),
        (:power, "power spec", power_spec),
        (:cam_temp, "camera temp (C)", cam_temp),
        (:inter, "interaction", inter),
        (:acq_ms, "acq time (ms)", acq_ms),
        (:frames, "frames", frames),
        (:delay_s, "delay (s)", delay_s),
        (:out_dir, "output dir", out_dir_row),
        (nothing, "plot X", xbox),
        (nothing, "plot Y", ybox),
        (nothing, "plot C (heatmap)", zbox),
        (nothing, "plot mode", mode_box),
        (nothing, "log scale", log_cb),
    ]

    field_error_labels = Dict{Symbol,Any}()
    for (i, (key, lbl, w)) in enumerate(rows)
        form[1, i] = Gtk.Label(lbl)
        form[2, i] = w
        err_lbl = Gtk.Label("")
        Gtk.set_gtk_property!(err_lbl, :xalign, 0.0f0)
        form[3, i] = err_lbl
        key === nothing || (field_error_labels[key] = err_lbl)
    end

    btn_panel = Gtk.Box(:v)
    btn_row_main = Gtk.Box(:h)
    btn_row_preset = Gtk.Box(:h)
    btn_row_save = Gtk.Box(:h)
    push!(btn_row_main, run_btn)
    push!(btn_row_main, focus_btn)
    push!(btn_row_main, pause_btn)
    push!(btn_row_main, stop_btn)
    push!(btn_row_main, stab_btn)
    push!(btn_row_preset, preset_open_btn)
    push!(btn_row_preset, preset_save_btn)
    push!(btn_row_save, save_raw_btn)
    push!(btn_panel, btn_row_main)
    push!(btn_panel, btn_row_preset)
    push!(btn_panel, btn_row_save)

    bottom_panel = Gtk.Box(:v)
    history_row = Gtk.Box(:h)
    queue_row = Gtk.Box(:h)
    compare_row = Gtk.Box(:h)
    autosave_row = Gtk.Box(:h)

    push!(history_row, Gtk.Label("History"))
    push!(history_row, history_combo)
    push!(history_row, history_repeat_btn)

    push!(queue_row, Gtk.Label("Queue"))
    push!(queue_row, queue_combo)
    push!(queue_row, queue_add_btn)
    push!(queue_row, queue_run_btn)
    push!(queue_row, queue_remove_btn)

    push!(compare_row, Gtk.Label("Compare"))
    push!(compare_row, compare_add_btn)
    push!(compare_row, compare_clear_btn)

    push!(autosave_row, Gtk.Label("Autosave every N points"))
    push!(autosave_row, autosave_every_entry)

    push!(bottom_panel, history_row)
    push!(bottom_panel, queue_row)
    push!(bottom_panel, compare_row)
    push!(bottom_panel, autosave_row)

    canvas_signal = Gtk.GtkCanvas(800, 320)
    canvas_raw = Gtk.GtkCanvas(800, 320)
    Gtk.set_gtk_property!(canvas_signal, :expand, true)
    Gtk.set_gtk_property!(canvas_raw, :expand, true)

    push!(left, form)
    push!(left, btn_panel)
    push!(left, status)
    push!(left, bottom_panel)

    push!(right, canvas_signal)
    push!(right, canvas_raw)

    push!(root, left)
    push!(root, right)
    push!(win, root)

    error_css_provider = _gtk_install_error_css!(win)

    spec_entries = Dict{Symbol,Any}(
        :wl => wl_spec,
        :sol_wl => sol_spec,
        :polarizer => pol_spec,
        :analyzer => ana_spec,
        :power => power_spec,
        :cam_temp => cam_temp,
        :inter => inter,
        :acq_ms => acq_ms,
        :frames => frames,
        :delay_s => delay_s,
    )

    autosave_path = joinpath(pwd(), "gtk_recovery.toml")
    history_entries = Any[]
    queue_items = Any[]
    queue_running = Ref(false)
    compare_overlays = NamedTuple{(:label, :points, :color),Tuple{String,Vector{ScanPoint},NTuple{3,Float64}}}[]
    current_run_label = Ref("")
    current_run_kind = Ref(:run)

    return GtkLegacyAppCtx(
        win = win,
        state = state,
        session_ref = session_ref,
        form_refs = form_refs,
        plot_refs = plot_refs,
        spec_entries = spec_entries,
        field_error_labels = field_error_labels,
        stab_duration_val = stab_duration_val,
        stab_kp_val = stab_kp_val,
        error_css_provider = error_css_provider,
        status = status,
        canvas_signal = canvas_signal,
        canvas_raw = canvas_raw,
        run_btn = run_btn,
        focus_btn = focus_btn,
        stop_btn = stop_btn,
        pause_btn = pause_btn,
        stab_btn = stab_btn,
        preset_open_btn = preset_open_btn,
        preset_save_btn = preset_save_btn,
        save_raw_btn = save_raw_btn,
        out_dir_pick_btn = out_dir_pick_btn,
        history_combo = history_combo,
        history_repeat_btn = history_repeat_btn,
        queue_combo = queue_combo,
        queue_add_btn = queue_add_btn,
        queue_run_btn = queue_run_btn,
        queue_remove_btn = queue_remove_btn,
        compare_add_btn = compare_add_btn,
        compare_clear_btn = compare_clear_btn,
        autosave_every_entry = autosave_every_entry,
        save_spec_dat_item = save_spec_dat_item,
        save_spec_png_item = save_spec_png_item,
        spectrum_menu = spectrum_menu,
        autosave_path = autosave_path,
        history_entries = history_entries,
        queue_items = queue_items,
        queue_running = queue_running,
        compare_overlays = compare_overlays,
        current_run_label = current_run_label,
        current_run_kind = current_run_kind,
        xbox = xbox,
        ybox = ybox,
        zbox = zbox,
        mode_box = mode_box,
        log_cb = log_cb,
    )
end

function _bind_legacy_actions!(ctx::GtkLegacyAppCtx, devices::DeviceBundle)
    refresh_plots! = () -> begin
        _gtk_sync_controls_state!(ctx)
        _gtk_refresh_plots!(ctx.state, ctx.status, ctx.canvas_signal, ctx.canvas_raw, ctx.plot_refs;
            status_text=_gtk_status_text(ctx.state),
            overlays=ctx.compare_overlays,
        )
    end

    launch_next_from_queue_ref = Ref{Function}(() -> nothing)

    function start_run_session!(req, run_label::String; state_snapshot::Union{Nothing,Dict{String,Any}}=nothing, queue_mode::Bool=false)
        _gtk_session_active(ctx) && return false
        snap = state_snapshot === nothing ? _gtk_collect_preset_state(ctx.form_refs, ctx.plot_refs, ctx.stab_duration_val, ctx.stab_kp_val) : deepcopy(state_snapshot)
        _gtk_push_history!(ctx, run_label, :run, snap)

        ctx.current_run_label[] = run_label
        ctx.current_run_kind[] = :run
        ctx.state.progress_total = _gtk_estimate_total_steps(req.plan)
        ctx.state.progress_step = 0
        ctx.state.current_wl = nothing
        ctx.state.started_at = time()
        req.camera_temp_c !== nothing && set_camera_temperature!(devices.camera, req.camera_temp_c)

        session = start_legacy_scan(devices, req.plan; delay_s=req.delay_s, output_dir=req.output_dir)
        _gtk_attach_session!(
            ctx.session_ref,
            ctx.stop_btn,
            ctx.pause_btn,
            ctx.state,
            refresh_plots!,
            session;
            on_step_cb = _ -> _gtk_write_autosave!(ctx),
            on_terminal_cb = (term, _) -> begin
                if term == :finished
                    _gtk_push_overlay_from_points!(ctx, run_label, ctx.state.points)
                    _gtk_clear_autosave!(ctx)
                    if queue_mode && ctx.queue_running[]
                        _on_mainloop(() -> launch_next_from_queue_ref[]())
                    end
                elseif term == :stopped
                    _gtk_clear_autosave!(ctx)
                    ctx.queue_running[] = false
                else
                    _gtk_write_autosave!(ctx; force=true)
                    ctx.queue_running[] = false
                end
            end,
        )
        refresh_plots!()
        return true
    end

    function start_focus_session!(params, run_label::String; state_snapshot::Union{Nothing,Dict{String,Any}}=nothing)
        _gtk_session_active(ctx) && return false
        snap = state_snapshot === nothing ? _gtk_collect_preset_state(ctx.form_refs, ctx.plot_refs, ctx.stab_duration_val, ctx.stab_kp_val) : deepcopy(state_snapshot)
        _gtk_push_history!(ctx, run_label, :focus, snap)

        ctx.current_run_label[] = run_label
        ctx.current_run_kind[] = :focus
        ctx.state.progress_total = nothing
        ctx.state.progress_step = 0
        ctx.state.current_wl = nothing
        ctx.state.started_at = time()

        session = start_focus_measurement(devices, params)
        _gtk_attach_session!(
            ctx.session_ref,
            ctx.stop_btn,
            ctx.pause_btn,
            ctx.state,
            refresh_plots!,
            session;
            on_step_cb = _ -> _gtk_write_autosave!(ctx),
            on_terminal_cb = (term, _) -> begin
                if term == :finished || term == :stopped
                    _gtk_clear_autosave!(ctx)
                else
                    _gtk_write_autosave!(ctx; force=true)
                end
                ctx.queue_running[] = false
            end,
        )
        refresh_plots!()
        return true
    end

    launch_next_from_queue_ref[] = function ()
        _gtk_session_active(ctx) && return
        if isempty(ctx.queue_items)
            ctx.queue_running[] = false
            ctx.state.status = "Queue finished"
            refresh_plots!()
            return
        end

        item = popfirst!(ctx.queue_items)
        _gtk_refresh_queue_widget!(ctx)

        ok = false
        try
            _gtk_apply_preset_state!(item.state, ctx.form_refs, ctx.plot_refs, ctx.stab_duration_val, ctx.stab_kp_val)
            if item.kind == :run
                ok = start_run_session!(item.request, item.label; state_snapshot=item.state, queue_mode=true)
            elseif item.kind == :focus
                ok = start_focus_session!(item.request, item.label; state_snapshot=item.state)
            end
        catch e
            ctx.state.status = "Queue item failed: $(sprint(showerror, e))"
            ok = false
        end

        if !ok
            ctx.queue_running[] = false
            ctx.state.status = startswith(ctx.state.status, "Queue item failed:") ? ctx.state.status : "Queue interrupted"
            refresh_plots!()
        end
    end

    Gtk.signal_connect(ctx.stop_btn, "clicked") do _
        session = ctx.session_ref[]
        session === nothing && return
        stop_measurement!(session)
        ctx.queue_running[] = false
        ctx.state.status = "Stopping..."
        refresh_plots!()
    end

    Gtk.signal_connect(ctx.pause_btn, "toggled") do w
        session = ctx.session_ref[]
        session === nothing && return
        if Gtk.GAccessor.active(w)
            pause_measurement!(session)
            ctx.state.status = "Paused"
        else
            resume_measurement!(session)
            ctx.state.status = "Resumed"
        end
        refresh_plots!()
    end

    Gtk.signal_connect(ctx.run_btn, "clicked") do _
        try
            if !_stop_active_session!(ctx)
                ctx.state.status = "Failed to stop previous session"
                refresh_plots!()
                return
            end

            form_data = _gtk_collect_form_data(ctx.form_refs, ctx.stab_duration_val, ctx.stab_kp_val)
            vr = _gtk_validate_run_request(form_data)
            if !vr.ok
                _gtk_apply_errors!(ctx.spec_entries, ctx.field_error_labels, vr.errors)
                ctx.state.status = _gtk_validation_summary(vr.errors)
                refresh_plots!()
                return
            end
            _gtk_clear_errors!(ctx.spec_entries, ctx.field_error_labels)
            label = _gtk_make_history_label(:run, form_data)
            start_run_session!(vr.request, label)
        catch e
            ctx.state.status = "Error: $(sprint(showerror, e))"
            refresh_plots!()
        end
    end

    Gtk.signal_connect(ctx.focus_btn, "clicked") do _
        try
            if !_stop_active_session!(ctx)
                ctx.state.status = "Failed to stop previous session"
                refresh_plots!()
                return
            end

            form_data = _gtk_collect_form_data(ctx.form_refs, ctx.stab_duration_val, ctx.stab_kp_val)
            vr = _gtk_validate_focus_request(form_data)
            if !vr.ok
                _gtk_apply_errors!(ctx.spec_entries, ctx.field_error_labels, vr.errors)
                ctx.state.status = _gtk_validation_summary(vr.errors)
                refresh_plots!()
                return
            end
            _gtk_clear_errors!(ctx.spec_entries, ctx.field_error_labels)
            label = _gtk_make_history_label(:focus, form_data)
            start_focus_session!(vr.params, label)
        catch e
            ctx.state.status = "Error: $(sprint(showerror, e))"
            refresh_plots!()
        end
    end

    Gtk.signal_connect(ctx.stab_btn, "clicked") do _
        try
            form_data = _gtk_collect_form_data(ctx.form_refs, ctx.stab_duration_val, ctx.stab_kp_val)
            vr = _gtk_validate_stabilize_request(form_data)
            if !vr.ok
                _gtk_apply_errors!(ctx.spec_entries, ctx.field_error_labels, vr.errors)
                ctx.state.status = _gtk_validation_summary(vr.errors)
                refresh_plots!()
                return
            end
            _gtk_clear_errors!(ctx.spec_entries, ctx.field_error_labels)

            req = vr.request
            ctx.state.status = "Stabilizing..."
            refresh_plots!()
            @async begin
                final_status = "Stabilized"
                try
                    stabilize_power!(devices; target_power=req.target_power, duration_s=req.duration_s, k_p=req.k_p)
                catch e
                    final_status = "Error: $(sprint(showerror, e))"
                end
                _on_mainloop(() -> begin
                    ctx.state.status = final_status
                    refresh_plots!()
                end)
            end
        catch e
            ctx.state.status = "Error: $(sprint(showerror, e))"
            refresh_plots!()
        end
    end

    Gtk.signal_connect(ctx.history_repeat_btn, "clicked") do _
        idx = _gtk_combo_active_index1(ctx.history_combo)
        (idx <= 0 || idx > length(ctx.history_entries)) && return
        item = ctx.history_entries[idx]
        _gtk_apply_preset_state!(item.state, ctx.form_refs, ctx.plot_refs, ctx.stab_duration_val, ctx.stab_kp_val)
        if item.kind == :focus
            Gtk.signal_emit(ctx.focus_btn, "clicked", Nothing)
        else
            Gtk.signal_emit(ctx.run_btn, "clicked", Nothing)
        end
    end

    Gtk.signal_connect(ctx.queue_add_btn, "clicked") do _
        try
            data = _gtk_collect_form_data(ctx.form_refs, ctx.stab_duration_val, ctx.stab_kp_val)
            vr = _gtk_validate_run_request(data)
            if !vr.ok
                _gtk_apply_errors!(ctx.spec_entries, ctx.field_error_labels, vr.errors)
                ctx.state.status = _gtk_validation_summary(vr.errors)
                refresh_plots!()
                return
            end
            _gtk_clear_errors!(ctx.spec_entries, ctx.field_error_labels)
            label = _gtk_make_history_label(:run, data) * " [Q]"
            snap = _gtk_collect_preset_state(ctx.form_refs, ctx.plot_refs, ctx.stab_duration_val, ctx.stab_kp_val)
            push!(ctx.queue_items, (label=label, kind=:run, request=vr.request, state=deepcopy(snap)))
            _gtk_refresh_queue_widget!(ctx)
            ctx.state.status = "Queued: $(label)"
            refresh_plots!()
        catch e
            ctx.state.status = "Error: $(sprint(showerror, e))"
            refresh_plots!()
        end
    end

    Gtk.signal_connect(ctx.queue_remove_btn, "clicked") do _
        idx = _gtk_combo_active_index1(ctx.queue_combo)
        (idx <= 0 || idx > length(ctx.queue_items)) && return
        deleteat!(ctx.queue_items, idx)
        _gtk_refresh_queue_widget!(ctx)
        ctx.state.status = "Queue item removed"
        refresh_plots!()
    end

    Gtk.signal_connect(ctx.queue_run_btn, "clicked") do _
        isempty(ctx.queue_items) && return
        ctx.queue_running[] = true
        ctx.state.status = "Queue started: $(length(ctx.queue_items)) item(s)"
        refresh_plots!()
        launch_next_from_queue_ref[]()
    end

    Gtk.signal_connect(ctx.compare_add_btn, "clicked") do _
        if isempty(ctx.state.points)
            ctx.state.status = "No points to compare"
            refresh_plots!()
            return
        end
        label = "Overlay $(_gtk_now_hms())"
        _gtk_push_overlay_from_points!(ctx, label, ctx.state.points)
        ctx.state.status = "Added compare curve: $(label)"
        refresh_plots!()
    end

    Gtk.signal_connect(ctx.compare_clear_btn, "clicked") do _
        empty!(ctx.compare_overlays)
        ctx.state.status = "Compare overlays cleared"
        refresh_plots!()
    end

    Gtk.signal_connect(ctx.preset_save_btn, "clicked") do _
        try
            state_dict = _gtk_collect_preset_state(ctx.form_refs, ctx.plot_refs, ctx.stab_duration_val, ctx.stab_kp_val)
            path = Gtk.save_dialog("Save preset", ctx.win)
            path === nothing && return
            save_preset_state(path, state_dict)
            ctx.state.status = "Preset saved"
            refresh_plots!()
        catch e
            ctx.state.status = "Error: $(sprint(showerror, e))"
            refresh_plots!()
        end
    end

    Gtk.signal_connect(ctx.preset_open_btn, "clicked") do _
        try
            path = Gtk.open_dialog("Open preset", ctx.win)
            path === nothing && return
            state_dict = load_preset_state(path)
            _gtk_apply_preset_state!(state_dict, ctx.form_refs, ctx.plot_refs, ctx.stab_duration_val, ctx.stab_kp_val)
            ctx.state.status = "Preset loaded"
            refresh_plots!()
        catch e
            ctx.state.status = "Error: $(sprint(showerror, e))"
            refresh_plots!()
        end
    end

    Gtk.signal_connect(ctx.save_raw_btn, "clicked") do _
        try
            isempty(ctx.state.last_raw) && error("No raw data")
            path = Gtk.save_dialog("Save raw spectrum", ctx.win)
            path === nothing && return
            params = isempty(ctx.state.points) ? Dict{Symbol,Any}() : scan_point_to_dict(ctx.state.points[end])
            save_raw_spectrum(path, ctx.state.last_raw; params=params)
            ctx.state.status = "Raw saved"
            refresh_plots!()
        catch e
            ctx.state.status = "Error: $(sprint(showerror, e))"
            refresh_plots!()
        end
    end

    Gtk.signal_connect(ctx.save_spec_dat_item, "activate") do _
        try
            ctx.state.spectrum === nothing && error("No spectrum")
            path = Gtk.save_dialog("Save spectrum .dat", ctx.win)
            path === nothing && return
            save_spectrum_dat(path, ctx.state.spectrum)
            ctx.state.status = "Spectrum .dat saved"
            refresh_plots!()
        catch e
            ctx.state.status = "Error: $(sprint(showerror, e))"
            refresh_plots!()
        end
    end

    Gtk.signal_connect(ctx.save_spec_png_item, "activate") do _
        try
            ctx.state.spectrum === nothing && error("No spectrum")
            path = Gtk.save_dialog("Save spectrum .png", ctx.win)
            path === nothing && return
            ps = _gtk_active_plot_settings(ctx.plot_refs)
            out = save_plot_from_points(path, ctx.state.points; xaxis=ps.xaxis, yaxis=ps.yaxis, zaxis=ps.zaxis, mode=ps.mode, log_scale=ps.log_scale)
            ctx.state.status = "Spectrum .png saved: $out"
            refresh_plots!()
        catch e
            ctx.state.status = "Error: $(sprint(showerror, e))"
            refresh_plots!()
        end
    end

    return refresh_plots!
end

function _bind_legacy_shortcuts!(ctx::GtkLegacyAppCtx)
    accel = Gtk.AccelGroupLeaf()
    push!(ctx.win, accel)

    ctrl = Int(Gtk.GdkModifierType.CONTROL)
    no_mod = 0
    visible = Int(Gtk.GtkAccelFlags.VISIBLE)

    push!(ctx.run_btn, "clicked", accel, Int(Gtk.keyval("r")), ctrl, visible)
    push!(ctx.save_raw_btn, "clicked", accel, Int(Gtk.keyval("s")), ctrl, visible)
    push!(ctx.stop_btn, "clicked", accel, Int(Gtk.GdkKeySyms.Escape), no_mod, visible)
    push!(ctx.pause_btn, "clicked", accel, Int(Gtk.keyval("space")), no_mod, visible)
    return nothing
end

function _bind_legacy_plot_signals!(ctx::GtkLegacyAppCtx, refresh_plots!::Function)
    ctx.canvas_signal.mouse.button3press = (widget, event) -> begin
        Gtk.popup(ctx.spectrum_menu, event)
        return true
    end

    Gtk.signal_connect(ctx.xbox, "changed") do _
        refresh_plots!()
    end
    Gtk.signal_connect(ctx.ybox, "changed") do _
        refresh_plots!()
    end
    Gtk.signal_connect(ctx.zbox, "changed") do _
        refresh_plots!()
    end
    Gtk.signal_connect(ctx.mode_box, "changed") do _
        refresh_plots!()
    end
    Gtk.signal_connect(ctx.log_cb, "toggled") do _
        refresh_plots!()
    end
    return nothing
end

function _bind_legacy_lifecycle!(ctx::GtkLegacyAppCtx, refresh_plots!::Function)
    preset_autopath = joinpath(pwd(), "preset.toml")
    try
        isfile(preset_autopath) && _gtk_apply_preset_state!(load_preset_state(preset_autopath), ctx.form_refs, ctx.plot_refs, ctx.stab_duration_val, ctx.stab_kp_val)
    catch
    end

    restored = false
    try
        restored = _gtk_try_restore_autosave!(ctx)
    catch
        restored = false
    end
    if restored
        ctx.state.status = "Recovered from autosave: $(length(ctx.state.points)) points"
    end

    _gtk_refresh_history_widget!(ctx)
    _gtk_refresh_queue_widget!(ctx)

    Gtk.signal_connect(ctx.win, "destroy") do _
        try
            state_dict = _gtk_collect_preset_state(ctx.form_refs, ctx.plot_refs, ctx.stab_duration_val, ctx.stab_kp_val)
            save_preset_state(preset_autopath, state_dict)
        catch
        end
        try
            _gtk_session_active(ctx) && _gtk_write_autosave!(ctx; force=true)
        catch
        end
        _stop_active_session!(ctx; timeout_s=2.0)
    end

    refresh_plots!()
    return nothing
end
