module Reducer

using ..State
using ..Measurement
using ..Power
using ..DeviceManager
using ..ParameterParser
using ..GtkUI: SetParam, SetDeviceLifecycle

export reduce!

function reduce!(state::AppState, ev)

    if ev isa MeasurementStarted
        state.measurement_state = State.Preparing
        state.current_spectrum = nothing
        empty!(state.current_raw)
        state.last_saved_file = nothing

    elseif ev isa MeasurementStep
        point_copy = copy(ev.point)
        existing_idx = ev.file_path === nothing ? nothing : findfirst(p -> get(p, :__file_path, nothing) == ev.file_path, state.points)
        if existing_idx === nothing
            push!(state.points, point_copy)
        else
            state.points[existing_idx] = point_copy
        end
        state.current_spectrum = ev.spectrum
        state.current_raw = copy(ev.raw)
        state.last_saved_file = ev.file_path
        state.measurement_state = State.Running

    elseif ev isa MeasurementDone
        state.measurement_state = State.Finished

    elseif ev isa MeasurementStopped
        state.measurement_state = State.Idle
    
    elseif ev isa DirChosen
        state.app_config.dir = ev.dir
        state.points = Measurement.import_dir(ev.dir)
        state.current_spectrum = nothing
        empty!(state.current_raw)
        state.last_saved_file = nothing

    elseif ev isa LaserPowerUpdate
        state.current_power = ev.power

    elseif ev isa SetParam
        param_index = findfirst(x -> x[1] == ev.name, state.raw_params)
        if param_index === nothing
            push!(state.raw_params, ev.name => ev.val)
        else
            state.raw_params[param_index] = ev.name => ev.val
        end
        running = state.measurement_state in (State.Preparing, State.Running, State.Paused, State.Stopping)
        if !running
            try
                state.scan_params = build_scan_axis_set_from_text_specs(state.raw_params)
            catch
                # Keep previous scan_params while user is still editing.
            end
        end

    elseif ev isa SetDeviceLifecycle
        state.devices_connected = ev.connected
        state.devices_initialized = ev.initialized
        state.device_status = ev.message

    elseif ev isa DeviceError
        state.measurement_state = State.Error
        state.power_state = State.ErrorPower
    end
end

end
