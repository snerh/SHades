include("../SHades.jl")
using .SHades

include("mock_devices.jl")
using .MockDevices

load_gtk_view!()
import Gtk

devices = MockDevices.build_bundle()
session_ref = Ref{Union{Nothing,MeasurementSession}}(nothing)

win = Gtk.Window("SHades2.0 Legacy Scan (Safe Axis DSL)", 760, 460)
root = Gtk.Box(:v)
grid = Gtk.Grid()
status = Gtk.Label("Ready")

wl_spec = Gtk.Entry(); Gtk.set_gtk_property!(wl_spec, :text, "500:2:540")
sol_spec = Gtk.Entry(); Gtk.set_gtk_property!(sol_spec, :text, "=round(wl/40)*20")
pol_spec = Gtk.Entry(); Gtk.set_gtk_property!(pol_spec, :text, "")
ana_spec = Gtk.Entry(); Gtk.set_gtk_property!(ana_spec, :text, "")
power_spec = Gtk.Entry(); Gtk.set_gtk_property!(power_spec, :text, "")

interaction = Gtk.Entry(); Gtk.set_gtk_property!(interaction, :text, "SIG")
acq_ms = Gtk.Entry(); Gtk.set_gtk_property!(acq_ms, :text, "50")
frames = Gtk.Entry(); Gtk.set_gtk_property!(frames, :text, "2")
delay_s = Gtk.Entry(); Gtk.set_gtk_property!(delay_s, :text, "0.01")
out_dir = Gtk.Entry(); Gtk.set_gtk_property!(out_dir, :text, "")

help = Gtk.Label(
    "Axis DSL: fixed `500`; range `500:2:540`; list `500,510,520`; dependent `=polarizer+10`; multi-dep `=(wl/2)+polarizer`"
)

run_btn = Gtk.Button("Run")
stop_btn = Gtk.Button("Stop")
pause_btn = Gtk.ToggleButton("Pause")

fields = [
    ("wl spec", wl_spec),
    ("sol_wl spec", sol_spec),
    ("polarizer spec", pol_spec),
    ("analyzer spec", ana_spec),
    ("power spec", power_spec),
    ("interaction", interaction),
    ("acq time (ms)", acq_ms),
    ("frames", frames),
    ("delay (s)", delay_s),
    ("output dir", out_dir),
]

for (i, (lbl, w)) in enumerate(fields)
    grid[1, i] = Gtk.Label(lbl)
    grid[2, i] = w
end

btns = Gtk.Box(:h)
push!(btns, run_btn)
push!(btns, pause_btn)
push!(btns, stop_btn)

push!(root, grid)
push!(root, help)
push!(root, btns)
push!(root, status)
push!(win, root)

function parse_int_default(s, d)
    try
        parse(Int, strip(s))
    catch
        d
    end
end

function parse_float_default(s, d)
    try
        parse(Float64, replace(strip(s), "," => "."))
    catch
        d
    end
end

Gtk.signal_connect(run_btn, "clicked") do _
    if session_ref[] !== nothing
        stop_measurement!(session_ref[])
        session_ref[] = nothing
    end

    try
        specs = Pair{Symbol,String}[]
        for (sym, entry) in [
            :wl => wl_spec,
            :sol_wl => sol_spec,
            :polarizer => pol_spec,
            :analyzer => ana_spec,
            :power => power_spec,
        ]
            txt = strip(Gtk.get_gtk_property(entry, "text", String))
            isempty(txt) || push!(specs, sym => txt)
        end

        inter = strip(Gtk.get_gtk_property(interaction, "text", String))
        ms = max(parse_int_default(Gtk.get_gtk_property(acq_ms, "text", String), 50), 1)
        fr = max(parse_int_default(Gtk.get_gtk_property(frames, "text", String), 1), 1)
        dly = max(parse_float_default(Gtk.get_gtk_property(delay_s, "text", String), 0.01), 0.0)

        fixed = Pair{Symbol,Any}[
            :inter => (isempty(inter) ? "SIG" : inter),
            :acq_time => (ms, "ms"),
            :frames => fr,
        ]

        plan = build_scan_plan_from_text_specs(specs; fixed=fixed)

        out = strip(Gtk.get_gtk_property(out_dir, "text", String))
        out_path = isempty(out) ? nothing : out

        session = start_legacy_scan(devices, plan; delay_s=dly, output_dir=out_path)
        session_ref[] = session

        handlers = GtkEventHandlers(
            on_started = _ -> Gtk.set_gtk_property!(status, :label, "Started"),
            on_step = ev -> begin
                if ev isa LegacyScanStep
                    Gtk.set_gtk_property!(status, :label, "step=$(ev.index), sig=$(round(ev.params[:sig], digits=3)), file=$(ev.file_stem)")
                end
            end,
            on_finished = ev -> begin
                if ev isa LegacyScanFinished
                    Gtk.set_gtk_property!(status, :label, "Finished, points=$(ev.points)")
                else
                    Gtk.set_gtk_property!(status, :label, "Finished")
                end
            end,
            on_stopped = _ -> Gtk.set_gtk_property!(status, :label, "Stopped"),
            on_error = ev -> Gtk.set_gtk_property!(status, :label, "Error: $(ev.message)"),
        )

        consume_events_gtk!(session.events; handlers=handlers)
        bind_stop_button!(stop_btn, session)
        bind_pause_toggle!(pause_btn, session)
    catch e
        Gtk.set_gtk_property!(status, :label, "Parse/Run error: $(sprint(showerror, e))")
    end
end

Gtk.signal_connect(win, "destroy") do _
    if session_ref[] !== nothing
        stop_measurement!(session_ref[])
    end
end

Gtk.showall(win)
Gtk.gtk_main()
