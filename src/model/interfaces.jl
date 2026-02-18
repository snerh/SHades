# Device interfaces isolate hardware details from the controller logic.

abstract type AbstractCamera end
abstract type AbstractSpectrometer end
abstract type AbstractLockin end
abstract type AbstractEllipsometer end
abstract type AbstractLaser end

struct DeviceBundle
    camera::AbstractCamera
    spectrometer::AbstractSpectrometer
    lockin::AbstractLockin
    ellipsometer::AbstractEllipsometer
    laser::AbstractLaser
end

set_laser_wavelength!(::AbstractLaser, ::Float64, ::AbstractString) = error("set_laser_wavelength! is not implemented")
set_spectrometer_wavelength!(::AbstractSpectrometer, ::Float64) = error("set_spectrometer_wavelength! is not implemented")
set_spectrometer_slit!(::AbstractSpectrometer, ::Float64) = error("set_spectrometer_slit! is not implemented")
set_shutter!(::AbstractSpectrometer, ::Bool) = error("set_shutter! is not implemented")
set_polarizer!(::AbstractEllipsometer, ::Float64) = error("set_polarizer! is not implemented")
set_analyzer!(::AbstractEllipsometer, ::Float64) = error("set_analyzer! is not implemented")
set_camera_acquisition!(::AbstractCamera, ::Float64) = error("set_camera_acquisition! is not implemented")
acquire_spectrum(::AbstractCamera; frames::Int=1) = error("acquire_spectrum is not implemented")
read_lockin_power(::AbstractLockin) = error("read_lockin_power is not implemented")
set_target_power!(::AbstractLockin, ::Union{Nothing,Float64}) = nothing
