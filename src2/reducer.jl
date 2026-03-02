module Reducer

using ..State
using ..Measurement
using ..Power
using ..DeviceManager
using ..ParameterParser
using ..GtkUI: SetParam

export reduce!

function reduce!(state::AppState, ev)

    if ev isa MeasurementStarted
        state.measurement_state = State.Preparing
        state.current_spectrum = nothing
        empty!(state.points)
        empty!(state.current_raw)
        state.last_saved_file = nothing

    elseif ev isa MeasurementStep
        push!(state.points, copy(ev.point))
        state.current_spectrum = ev.spectrum
        state.current_raw = copy(ev.raw)
        state.last_saved_file = ev.file_path
        state.measurement_state = State.Running

    elseif ev isa MeasurementDone
        state.measurement_state = State.Finished

    elseif ev isa MeasurementStopped
        state.measurement_state = State.Idle

    elseif ev isa LaserPowerUpdate
        state.current_power = ev.power

    elseif ev isa SetParam
        param_index = findfirst(x -> x[1] == ev.name, state.raw_params)
        if param_index === nothing
            push!(state.raw_params, ev.name => ev.val)
        else
            state.raw_params[param_index] = ev.name => ev.val
        end
        try
            state.scan_params = build_scan_axis_set_from_text_specs(state.raw_params)
        catch
            # Keep previous scan_params while user is still editing.
        end

    elseif ev isa DeviceError
        state.measurement_state = State.Error
        state.power_state = State.ErrorPower
    end
end

end
