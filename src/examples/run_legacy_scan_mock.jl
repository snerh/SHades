include("../SHades.jl")
using .SHades

include("mock_devices.jl")
using .MockDevices

devices = MockDevices.build_bundle()

plan = ScanPlan(
    IndependentAxis(:wl, 500.0:2.0:508.0),
    FixedAxis(:inter, "SIG"),
    DependentAxis(:sol_wl, :wl, wl -> round((wl / 2) / 20) * 20),
    FixedAxis(:acq_time, (50, "ms")),
    FixedAxis(:frames, 2),
)

session = start_legacy_scan(devices, plan; delay_s=0.01, output_dir=nothing)
consume_events!(session.events)
wait(session.task)
