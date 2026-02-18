include("../SHades.jl")
using .SHades

# Example wiring for real hardware. Keep this script as a template.
# It is not executed automatically.

legacy_src = "/home/snerh/YaD/Science/Установка/SHades/src"
mods = load_legacy_modules!(legacy_src)

# Optional: choose real Orpheus endpoint.
mods.Orpheus.init(test=false)
mods.PSI.init()

cam = mods.PSI.wait2open()
spec = mods.Sol.open(conf_dir=dirname(legacy_src))
lok = mods.Lockin.open()
ell = mods.ELL.open()

devices = build_legacy_bundle(
    mods;
    cam=cam,
    spec=spec,
    lok=lok,
    ell=ell,
    power_channel=nothing,
    half_wave=true,
)

plan = build_legacy_scan_plan(
    wl=500.0:1.0:510.0,
    interaction="SIG",
    sol_from_wl=wl -> round((wl / 2) / 20) * 20,
    acq_time=(100, "ms"),
    frames=1,
)

session = start_legacy_scan(devices, plan; delay_s=1.5, output_dir=nothing)
consume_events!(session.events)
wait(session.task)

mods.PSI.close(cam)
mods.Sol.close(spec)
mods.Lockin.close(lok)
mods.ELL.close(ell)
