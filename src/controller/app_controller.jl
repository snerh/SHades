mutable struct MeasurementSession
    ctrl::MeasurementControl
    events::Channel{MeasurementEvent}
    task::Task
end

function start_measurement(devices::DeviceBundle, params::ScanParams; buffer_size::Int=32)
    ctrl = MeasurementControl()
    events = Channel{MeasurementEvent}(buffer_size)
    task = @async run_measurement!(devices, params, events, ctrl)
    MeasurementSession(ctrl, events, task)
end

stop_measurement!(session::MeasurementSession) = (session.ctrl.stop = true; nothing)
pause_measurement!(session::MeasurementSession) = (session.ctrl.pause = true; nothing)
resume_measurement!(session::MeasurementSession) = (session.ctrl.pause = false; nothing)
