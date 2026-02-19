Base.@kwdef struct GtkLegacyFormRefs
    wl_spec
    sol_spec
    pol_spec
    ana_spec
    power_spec
    cam_temp
    inter
    acq_ms
    frames
    delay_s
    out_dir
end

Base.@kwdef struct GtkLegacyPlotRefs
    xbox
    ybox
    zbox
    mode_box
    log_cb
end

const _GTK_CSS_PRIORITY_APPLICATION = Cuint(800)

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
    label.field-error {
        color: #b91c1c;
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

function _gtk_combo_count(box)::Int
    try
        return Int(Gtk.GAccessor.n_items(box))
    catch
    end
    try
        return length(Gtk.GtkListStoreLeaf(box))
    catch
    end
    return 0
end

function _gtk_set_combo_text!(box, text::String)
    n = _gtk_combo_count(box)
    n <= 0 && return
    for i in 0:(n - 1)
        item_text = try
            Gtk.bytestring(Gtk.GAccessor.get_text(box, i))
        catch
            nothing
        end
        if item_text !== nothing && item_text == text
            Gtk.set_gtk_property!(box, :active, i)
            return
        end
    end
end

function _gtk_set_field_error!(entry, msg::String; label=nothing)
    _gtk_set_style_class!(entry, "axis-error", true)
    Gtk.set_gtk_property!(entry, :tooltip_text, msg)
    try
        Gtk.set_gtk_property!(entry, :secondary_icon_name, "dialog-error-symbolic")
        Gtk.set_gtk_property!(entry, :secondary_icon_tooltip_text, msg)
    catch
    end
    if label !== nothing
        Gtk.set_gtk_property!(label, :label, msg)
        _gtk_set_style_class!(label, "field-error", true)
    end
end

function _gtk_clear_field_error!(entry; label=nothing)
    _gtk_set_style_class!(entry, "axis-error", false)
    Gtk.set_gtk_property!(entry, :tooltip_text, "")
    try
        Gtk.set_gtk_property!(entry, :secondary_icon_name, "")
        Gtk.set_gtk_property!(entry, :secondary_icon_tooltip_text, "")
    catch
    end
    if label !== nothing
        Gtk.set_gtk_property!(label, :label, "")
        _gtk_set_style_class!(label, "field-error", false)
    end
end

function _gtk_clear_errors!(spec_entries::Dict{Symbol,Any})
    _gtk_clear_errors!(spec_entries, Dict{Symbol,Any}())
end

function _gtk_clear_errors!(spec_entries::Dict{Symbol,Any}, field_error_labels::Dict{Symbol,Any})
    for (k, e) in spec_entries
        label = get(field_error_labels, k, nothing)
        _gtk_clear_field_error!(e; label=label)
    end
end

function _gtk_apply_errors!(spec_entries::Dict{Symbol,Any}, errs::Dict{Symbol,String})
    _gtk_apply_errors!(spec_entries, Dict{Symbol,Any}(), errs)
end

function _gtk_apply_errors!(spec_entries::Dict{Symbol,Any}, field_error_labels::Dict{Symbol,Any}, errs::Dict{Symbol,String})
    _gtk_clear_errors!(spec_entries, field_error_labels)
    for (k, msg) in errs
        if haskey(spec_entries, k)
            label = get(field_error_labels, k, nothing)
            _gtk_set_field_error!(spec_entries[k], msg; label=label)
        end
    end
end

function _gtk_collect_form_data(
    form::GtkLegacyFormRefs,
    stab_duration_val::Base.RefValue{Float64},
    stab_kp_val::Base.RefValue{Float64}
)
    return LegacyFormData(
        wl_spec = Gtk.get_gtk_property(form.wl_spec, "text", String),
        sol_spec = Gtk.get_gtk_property(form.sol_spec, "text", String),
        pol_spec = Gtk.get_gtk_property(form.pol_spec, "text", String),
        ana_spec = Gtk.get_gtk_property(form.ana_spec, "text", String),
        power_spec = Gtk.get_gtk_property(form.power_spec, "text", String),
        cam_temp = Gtk.get_gtk_property(form.cam_temp, "text", String),
        inter = Gtk.get_gtk_property(form.inter, "text", String),
        acq_ms = Gtk.get_gtk_property(form.acq_ms, "text", String),
        frames = Gtk.get_gtk_property(form.frames, "text", String),
        delay_s = Gtk.get_gtk_property(form.delay_s, "text", String),
        out_dir = Gtk.get_gtk_property(form.out_dir, "text", String),
        stab_duration_s = stab_duration_val[],
        stab_kp = stab_kp_val[],
    )
end

function _gtk_active_plot_settings(plot::GtkLegacyPlotRefs)
    return (
        xaxis = Symbol(Gtk.bytestring(Gtk.GAccessor.active_text(plot.xbox))),
        yaxis = Symbol(Gtk.bytestring(Gtk.GAccessor.active_text(plot.ybox))),
        zaxis = Symbol(Gtk.bytestring(Gtk.GAccessor.active_text(plot.zbox))),
        mode = Symbol(Gtk.bytestring(Gtk.GAccessor.active_text(plot.mode_box))),
        log_scale = Gtk.GAccessor.active(plot.log_cb),
    )
end
