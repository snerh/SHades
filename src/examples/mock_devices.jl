module MockDevices

using ..SHades

struct MockCamera <: SHades.AbstractCamera end
struct MockSpectrometer <: SHades.AbstractSpectrometer end
struct MockLockin <: SHades.AbstractLockin
    power::Float64
end
struct MockEllipsometer <: SHades.AbstractEllipsometer end
struct MockLaser <: SHades.AbstractLaser end

SHades.set_laser_wavelength!(::MockLaser, ::Float64, ::AbstractString) = nothing
SHades.set_spectrometer_wavelength!(::MockSpectrometer, ::Float64) = nothing
SHades.set_spectrometer_slit!(::MockSpectrometer, ::Float64) = nothing
SHades.set_shutter!(::MockSpectrometer, ::Bool) = nothing
SHades.set_polarizer!(::MockEllipsometer, ::Float64) = nothing
SHades.set_analyzer!(::MockEllipsometer, ::Float64) = nothing
SHades.set_camera_acquisition!(::MockCamera, ::Float64) = nothing
SHades.read_lockin_power(lockin::MockLockin) = lockin.power

function SHades.acquire_spectrum(::MockCamera; frames::Int=1)
    n = 256
    base = randn(n) .* 0.8
    peak_pos = rand(80:180)
    base[peak_pos] += 80 + 5 * frames
    return base
end

function build_bundle()
    SHades.DeviceBundle(
        MockCamera(),
        MockSpectrometer(),
        MockLockin(1.0),
        MockEllipsometer(),
        MockLaser(),
    )
end

end
