module Reducer

using ..State
using ..Measurement
using ..Power
using ..DeviceManager

export reduce!

function reduce!(state::AppState, ev)

    if ev isa MeasurementStep
        state.current_spectrum = ev.spectrum
        state.measurement_state = Running

    elseif ev isa MeasurementDone
        state.measurement_state = Finished

    elseif ev isa MeasurementStopped
        state.measurement_state = Idle

    elseif ev isa LaserPowerUpdate
        state.current_power = ev.power

    elseif ev ias SetParam
        param_index = findfirst(x->x[1] == ev.name, state.raw_params)
        state.raw_params[param_index] = name => ev.val
        state.scan_params = build_scan_axis_set_from_text_specs(state.raw_params)

    elseif ev isa DeviceError
        state.measurement_state = Error
        state.power_state = ErrorPower
    end
end

end
