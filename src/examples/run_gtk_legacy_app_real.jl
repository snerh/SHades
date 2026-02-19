include("../SHades.jl")
using .SHades

# Real hardware entry point.
legacy_src = "/home/snerh/YaD/Science/Установка/SHades/src"
mods = load_legacy_modules!(legacy_src)

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

load_gtk_view!()

try
    start_gtk_legacy_app(devices; title="SHades2.0 Legacy App", default_output_dir="")
finally
    mods.PSI.close(cam)
    mods.Sol.close(spec)
    mods.Lockin.close(lok)
    mods.ELL.close(ell)
end
