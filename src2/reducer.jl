module Reducer

using ..State
using ..Measurement
using ..Power
using ..DeviceManager
using ..ParameterParser
using ..GtkUI: SetParam

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

    elseif ev isa SetParam
        param_index = findfirst(x -> x[1] == ev.name, state.raw_params)
        println("==========SetParam==========")
        println("$(ev.name) -> $(ev.val)")
        if param_index === nothing
            push!(state.raw_params, ev.name => ev.val)
        else
            state.raw_params[param_index] = ev.name => ev.val
            println("===New state:===")
            println(state)
        end
        try
            state.scan_params = build_scan_axis_set_from_text_specs(state.raw_params)
        catch
            # Keep previous scan_params while user is still editing.
        end

    elseif ev isa DeviceError
        state.measurement_state = Error
        state.power_state = ErrorPower
    end
end

end
