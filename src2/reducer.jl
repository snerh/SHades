module Reducer

using ..State
using ..Measurement
using ..Power
using ..DeviceManager
using ..AppEvents: SyncRawParams, SetDeviceLifecycle, DirectoryLoaded
using ..AppLogic: sync_raw_params!

export reduce!

function reduce!(state::AppState, ev)

    if ev isa MeasurementStarted
        state.measurement_state = State.Preparing
        state.measurement.current_spectrum = nothing
        empty!(state.measurement.current_raw)
        state.measurement.last_saved_file = nothing

    elseif ev isa MeasurementStep
        point_copy = copy(ev.point)
        existing_idx = ev.file_path === nothing ? nothing : findfirst(p -> get(p, :__file_path, nothing) == ev.file_path, state.measurement.points)
        if existing_idx === nothing
            push!(state.measurement.points, point_copy)
        else
            state.measurement.points[existing_idx] = point_copy
        end
        state.measurement.current_spectrum = ev.spectrum
        state.measurement.current_raw = copy(ev.raw)
        state.measurement.last_saved_file = ev.file_path
        state.measurement_state = State.Running

    elseif ev isa MeasurementDone
        state.measurement_state = State.Finished

    elseif ev isa MeasurementStopped
        state.measurement_state = State.Idle
    
    elseif ev isa DirectoryLoaded
        state.session.config.dir = ev.dir
        state.measurement.points = copy(ev.points)
        state.measurement.current_spectrum = nothing
        empty!(state.measurement.current_raw)
        state.measurement.last_saved_file = nothing

    elseif ev isa LaserPowerUpdate
        state.devices.current_power = ev.power

    elseif ev isa SyncRawParams
        sync_raw_params!(state, ev.values)

    elseif ev isa SetDeviceLifecycle
        state.devices.connected = ev.connected
        state.devices.initialized = ev.initialized
        state.devices.status = ev.message

    elseif ev isa DeviceError
        state.measurement_state = State.Error
        state.power_state = State.ErrorPower
    end
end

end
