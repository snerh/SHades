import Gtk

include("gtk/canvas_helpers.jl")
include("gtk/form_helpers.jl")
include("gtk/preset_helpers.jl")
include("gtk/session_helpers.jl")
include("gtk/app_wiring.jl")

function start_gtk_legacy_app(devices::DeviceBundle; title::String="SHades2.0", default_output_dir::String="")
    ctx = _build_legacy_app_ui(title, default_output_dir)
    refresh_plots! = _bind_legacy_actions!(ctx, devices)
    _bind_legacy_shortcuts!(ctx)
    _bind_legacy_plot_signals!(ctx, refresh_plots!)
    _bind_legacy_lifecycle!(ctx, refresh_plots!)

    Gtk.showall(ctx.win)
    Gtk.gtk_main()
    return nothing
end
