module Reducer

using ..State
using ..Measurement
using ..Power
using ..Device

export reduce!

function reduce!(state::AppState, ev)

    if ev isa MeasurementStep
        state.current_spectrum = ev.spectrum
        state.measurement_state = Running

    elseif ev isa MeasurementDone
        state.measurement_state = Finished

    elseif ev isa LaserPowerUpdate
        state.current_power = ev.power

    elseif ev isa DeviceError
        state.measurement_state = Error
        state.power_state = ErrorPower
    end
end

end