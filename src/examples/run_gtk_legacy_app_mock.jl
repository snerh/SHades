include("../SHades.jl")
using .SHades

include("mock_devices.jl")
using .MockDevices

load_gtk_view!()

devices = MockDevices.build_bundle()
start_gtk_legacy_app(devices; title="SHades2.0 Legacy App (Mock)", default_output_dir="")
