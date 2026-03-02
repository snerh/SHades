struct LegacyModules
    PSI::Module
    Sol::Module
    Lockin::Module
    ELL::Module
    Orpheus::Module
end

mutable struct LegacyCamera <: AbstractCamera
    mod::LegacyModules
    handle::Any
    acq_time_s::Float64
end

struct LegacySpectrometer <: AbstractSpectrometer
    mod::LegacyModules
    handle::Any
end

mutable struct LegacyLockin <: AbstractLockin
    mod::LegacyModules
    handle::Any
    power_channel::Union{Nothing,Channel{Float64}}
end

struct LegacyEllipsometer <: AbstractEllipsometer
    mod::LegacyModules
    handle::Any
    half_wave::Bool
end

struct LegacyLaser <: AbstractLaser
    mod::LegacyModules
end

function _include_if_missing!(path::AbstractString, modsym::Symbol)
    isdefined(@__MODULE__, modsym) || include(path)
    return getfield(@__MODULE__, modsym)
end

function load_legacy_modules!(legacy_src_dir::AbstractString)
    _include_if_missing!(joinpath(legacy_src_dir, "Orpheus.jl"), :Orpheus)
    _include_if_missing!(joinpath(legacy_src_dir, "psi_base.jl"), :PSI)
    _include_if_missing!(joinpath(legacy_src_dir, "Lockin_ESP.jl"), :Lockin)
    _include_if_missing!(joinpath(legacy_src_dir, "ELL.jl"), :ELL)
    _include_if_missing!(joinpath(legacy_src_dir, "Sol.jl"), :Sol)
    LegacyModules(PSI, Sol, Lockin, ELL, Orpheus)
end

function _sec_to_legacy_time(t_s::Float64)
    if t_s < 1.0
        ms = Int(max(1, round(t_s * 1000)))
        return (ms, "ms")
    end
    return (Int(round(t_s)), "s")
end

_deg_to_legacy_rad(deg::Float64, half_wave::Bool) = deg2rad(deg) / (half_wave ? 2.0 : 1.0)

function set_laser_wavelength!(laser::LegacyLaser, wl::Float64, interaction::AbstractString)
    laser.mod.Orpheus.setWL(wl, interaction)
    return nothing
end

function set_spectrometer_wavelength!(spec::LegacySpectrometer, wl::Float64)
    spec.mod.Sol.set_wl(spec.handle, wl)
    return nothing
end

function set_spectrometer_slit!(spec::LegacySpectrometer, slit::Float64)
    spec.mod.Sol.set_slit(spec.handle, slit)
    return nothing
end

function set_shutter!(spec::LegacySpectrometer, is_open::Bool)
    spec.mod.Sol.set_shutter(spec.handle, is_open ? 1 : 0)
    return nothing
end

function set_polarizer!(ell::LegacyEllipsometer, deg::Float64)
    ell.mod.ELL.ma(ell.handle, 0, _deg_to_legacy_rad(deg, ell.half_wave))
    return nothing
end

function set_analyzer!(ell::LegacyEllipsometer, deg::Float64)
    ell.mod.ELL.ma(ell.handle, 2, _deg_to_legacy_rad(deg, ell.half_wave))
    return nothing
end

function set_camera_acquisition!(cam::LegacyCamera, acq_time_s::Float64)
    cam.acq_time_s = acq_time_s
    cam.mod.PSI.set_params(cam.handle, time=_sec_to_legacy_time(acq_time_s))
    return nothing
end

function acquire_spectrum(cam::LegacyCamera; frames::Int=1)
    frames < 1 && error("frames must be >= 1")
    acc = Vector{Float64}()
    for i in 1:frames
        cam.mod.PSI.start_scan(cam.handle)
        sleep(cam.acq_time_s + 0.1)
        raw = Float64.(cam.mod.PSI.get_data(cam.handle))
        if i == 1
            acc = raw
        else
            acc .+= raw
        end
    end
    return acc ./ frames
end

function read_lockin_power(lockin::LegacyLockin)
    value = lockin.mod.Lockin.get(lockin.handle)
    return value === nothing ? NaN : value
end

function set_target_power!(lockin::LegacyLockin, target::Union{Nothing,Float64})
    if lockin.power_channel !== nothing && target !== nothing
        put!(lockin.power_channel, target)
    end
    return nothing
end

function build_legacy_bundle(mod::LegacyModules; cam, spec, lok, ell, power_channel::Union{Nothing,Channel{Float64}}=nothing, half_wave::Bool=true, acq_time_s::Float64=0.1)
    devices = DeviceBundle(
        LegacyCamera(mod, cam, acq_time_s),
        LegacySpectrometer(mod, spec),
        LegacyLockin(mod, lok, power_channel),
        LegacyEllipsometer(mod, ell, half_wave),
        LegacyLaser(mod),
    )
    return devices
end
