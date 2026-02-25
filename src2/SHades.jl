module SHades

include("domain.jl")
include("parameters.jl")
include("parameters_parser.jl")
include("state.jl")
include("device_manager.jl")
include("measurement.jl")
include("power.jl")
include("reducer.jl")
include("persistence.jl")

using .Domain
using .Parameters
using .ParameterParser
using .State
using .DeviceManager
using .Measurement
using .Power
using .Reducer

function run()

    state = AppState()

    device_cmd = Channel{DeviceCommand}(32)
    meas_cmd = Channel{MeasurementCommand}(16)
    meas_events = Channel{SystemEvent}(32)

    power_cmd = Channel{PowerCommand}(16)
    power_events = Channel{SystemEvent}(32)
    md = MockDevice()
    device_manager = DeviceManager.DeviceManager(Dict(
        :laser => md.device_cmd,
        :spec => md.device_cmd,
        :ell => md.device_cmd,
        :cam => md.device_cmd,
        :pd => md.device_cmd,
    ))
    @async device_loop(md) ## тут должны быть все приборы, пока заглушка с одним
    @async measurement_loop(meas_cmd, meas_events, device_manager)
    @async power_loop(power_cmd, power_events, device_manager)

    # Центральный event bus
    event_bus = Channel{SystemEvent}(64)

    @async forward(meas_events, event_bus)
    @async forward(power_events, event_bus)
    @async forward(md.device_events, event_bus)

    # UI event pump (Gtk должен вызывать reduce! из main thread)
    @async begin
        for ev in event_bus
            reduce!(state, ev)
        end
    end

    return state
end

function forward(src, dst)
    for ev in src
        put!(dst, ev)
    end
end

end
