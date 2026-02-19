function _gtk_collect_preset_state(
    form::GtkLegacyFormRefs,
    plot::GtkLegacyPlotRefs,
    stab_duration_val::Base.RefValue{Float64},
    stab_kp_val::Base.RefValue{Float64}
)
    return Dict{String,Any}(
        "wl_spec" => Gtk.get_gtk_property(form.wl_spec, "text", String),
        "sol_spec" => Gtk.get_gtk_property(form.sol_spec, "text", String),
        "pol_spec" => Gtk.get_gtk_property(form.pol_spec, "text", String),
        "ana_spec" => Gtk.get_gtk_property(form.ana_spec, "text", String),
        "power_spec" => Gtk.get_gtk_property(form.power_spec, "text", String),
        "cam_temp" => Gtk.get_gtk_property(form.cam_temp, "text", String),
        "inter" => Gtk.get_gtk_property(form.inter, "text", String),
        "acq_ms" => Gtk.get_gtk_property(form.acq_ms, "text", String),
        "frames" => Gtk.get_gtk_property(form.frames, "text", String),
        "delay_s" => Gtk.get_gtk_property(form.delay_s, "text", String),
        "plot_x" => Gtk.bytestring(Gtk.GAccessor.active_text(plot.xbox)),
        "plot_y" => Gtk.bytestring(Gtk.GAccessor.active_text(plot.ybox)),
        "plot_z" => Gtk.bytestring(Gtk.GAccessor.active_text(plot.zbox)),
        "plot_mode" => Gtk.bytestring(Gtk.GAccessor.active_text(plot.mode_box)),
        "plot_log" => Gtk.GAccessor.active(plot.log_cb),
        "stab_duration" => stab_duration_val[],
        "stab_kp" => stab_kp_val[],
    )
end

function _gtk_apply_preset_state!(
    d::Dict{String,Any},
    form::GtkLegacyFormRefs,
    plot::GtkLegacyPlotRefs,
    stab_duration_val::Base.RefValue{Float64},
    stab_kp_val::Base.RefValue{Float64}
)
    haskey(d, "wl_spec") && Gtk.set_gtk_property!(form.wl_spec, :text, string(d["wl_spec"]))
    haskey(d, "sol_spec") && Gtk.set_gtk_property!(form.sol_spec, :text, string(d["sol_spec"]))
    haskey(d, "pol_spec") && Gtk.set_gtk_property!(form.pol_spec, :text, string(d["pol_spec"]))
    haskey(d, "ana_spec") && Gtk.set_gtk_property!(form.ana_spec, :text, string(d["ana_spec"]))
    haskey(d, "power_spec") && Gtk.set_gtk_property!(form.power_spec, :text, string(d["power_spec"]))
    haskey(d, "cam_temp") && Gtk.set_gtk_property!(form.cam_temp, :text, string(d["cam_temp"]))
    haskey(d, "inter") && Gtk.set_gtk_property!(form.inter, :text, string(d["inter"]))
    haskey(d, "acq_ms") && Gtk.set_gtk_property!(form.acq_ms, :text, string(d["acq_ms"]))
    haskey(d, "frames") && Gtk.set_gtk_property!(form.frames, :text, string(d["frames"]))
    haskey(d, "delay_s") && Gtk.set_gtk_property!(form.delay_s, :text, string(d["delay_s"]))
    haskey(d, "plot_x") && _gtk_set_combo_text!(plot.xbox, string(d["plot_x"]))
    haskey(d, "plot_y") && _gtk_set_combo_text!(plot.ybox, string(d["plot_y"]))
    haskey(d, "plot_z") && _gtk_set_combo_text!(plot.zbox, string(d["plot_z"]))
    haskey(d, "plot_mode") && _gtk_set_combo_text!(plot.mode_box, string(d["plot_mode"]))
    haskey(d, "plot_log") && Gtk.set_gtk_property!(plot.log_cb, :active, Bool(d["plot_log"]))
    haskey(d, "stab_duration") && (stab_duration_val[] = Float64(d["stab_duration"]))
    haskey(d, "stab_kp") && (stab_kp_val[] = Float64(d["stab_kp"]))
    return nothing
end
