include("../SHades.jl")
using .SHades

include("mock_devices.jl")
using .MockDevices

devices = MockDevices.build_bundle()
params = ScanParams(wavelengths=collect(500.0:2.0:530.0), acq_time_s=0.05, frames=2, delay_s=0.02)
session = start_measurement(devices, params)

consume_events!(session.events; on_step = ev -> println("step=$(ev.index) wl=$(ev.wavelength) sig=$(round(ev.signal, digits=2))"))
wait(session.task)
