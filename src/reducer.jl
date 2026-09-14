module Reducer

using ..State
using ..Measurement
using ..Power
using ..DeviceManager
using ..AppEvents: SyncRawParams, SetDeviceLifecycle, DirectoryLoaded
using ..AppLogic: sync_raw_params!
using ..GtkUI: UIUpdate, PlotUpdate, UICommand

export reduce!

function _is_power_device_error(msg::AbstractString)
    startswith(msg, "Power loop failed:") && return true
    startswith(msg, "Read timeout pd.") && return true
    startswith(msg, "Retry read timeout pd.") && return true
    startswith(msg, "Read error pd.") && return true
    startswith(msg, "Retry read error pd.") && return true
    startswith(msg, "Timeout setting pd.") && return true
    startswith(msg, "Retry timeout setting pd.") && return true
    startswith(msg, "Error setting pd.") && return true
    startswith(msg, "Retry error setting pd.") && return true
    startswith(msg, "Recover connect timeout on pd") && return true
    startswith(msg, "Recover connect error on pd") && return true
    startswith(msg, "Connect timeout on pd") && return true
    startswith(msg, "Connect error on pd") && return true
    startswith(msg, "Init timeout on pd") && return true
    startswith(msg, "Init error on pd") && return true
    startswith(msg, "Disconnect failed on pd") && return true
    startswith(msg, "Close failed on pd") && return true
    return false
end

function reduce!(state::AppState, ev)

    if ev isa MeasurementStarted
        state.measurement_state = State.Preparing
        #state.measurement.current_spectrum = nothing
        empty!(state.measurement.current_cam_df)
        state.measurement.last_saved_file = nothing

    elseif ev isa MeasurementStep
        #print("Event measurement step")
        point_copy = copy(ev.point)
        existing_idx = ev.file_path === nothing ? nothing : findfirst(p -> get(p, :__file_path, nothing) == ev.file_path, state.measurement.points)
        if existing_idx === nothing
            #print("New point. Push it to state")
            push!(state.measurement.points, point_copy)
            #println("state.measurement:points: ", state.measurement.points)
        else
            #print("Existing point. Rewrite it!")
            state.measurement.points[existing_idx] = point_copy
        end
        #state.measurement.current_spectrum = ev.spectrum
        state.measurement.current_cam_df = copy(ev.cam_df)
        state.measurement.last_saved_file = ev.file_path
        state.measurement_state = State.Running
        return PlotUpdate()
        #print("Event exit")

    elseif ev isa MeasurementDone
        state.measurement_state = State.Finished

    elseif ev isa MeasurementStopped
        state.measurement_state = State.Idle
    
    elseif ev isa DirectoryLoaded
        state.session.config.dir = ev.dir
        state.measurement.points = copy(ev.points)
        #state.measurement.current_spectrum = nothing
        empty!(state.measurement.current_cam_df)
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
        if _is_power_device_error(ev.message)
            state.power_state = State.ErrorPower
        else
            state.measurement_state = State.Error
            state.power_state = State.ErrorPower
        end
    end
    return UIUpdate()
end

end
