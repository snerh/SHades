include("../SHades.jl")
using .SHades

include("mock_devices.jl")
using .MockDevices

load_gtk_view!()
import Gtk

devices = MockDevices.build_bundle()
params = ScanParams(wavelengths=collect(500.0:2.0:540.0), acq_time_s=0.05)
session = start_measurement(devices, params)

win = Gtk.Window("SHades2.0 GTK View", 420, 160)
box = Gtk.Box(:v)
label = Gtk.Label("Waiting...")
stop_btn = Gtk.Button("Stop")
pause_btn = Gtk.ToggleButton("Pause")

push!(box, label)
push!(box, pause_btn)
push!(box, stop_btn)
push!(win, box)

handlers = GtkEventHandlers(
    on_started = ev -> Gtk.set_gtk_property!(label, :label, "Started: $(length(ev.params.wavelengths)) points"),
    on_step = ev -> Gtk.set_gtk_property!(label, :label, "Step $(ev.index), wl=$(round(ev.wavelength, digits=1)), sig=$(round(ev.signal, digits=2))"),
    on_finished = ev -> Gtk.set_gtk_property!(label, :label, "Finished: $(length(ev.spectrum.wavelength)) points"),
    on_stopped = _ -> Gtk.set_gtk_property!(label, :label, "Stopped"),
    on_error = ev -> Gtk.set_gtk_property!(label, :label, "Error: $(ev.message)"),
)

consume_events_gtk!(session.events; handlers=handlers)
bind_stop_button!(stop_btn, session)
bind_pause_toggle!(pause_btn, session)

Gtk.showall(win)
Gtk.gtk_main()
