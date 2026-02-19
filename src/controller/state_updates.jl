function apply_event!(state::AppState, ev::MeasurementEvent)
    if ev isa LegacyScanStarted
        empty!(state.points)
        empty!(state.last_raw)
        state.running = true
        state.status = "Scan started"
    elseif ev isa LegacyScanStep
        state.points = copy(ev.accumulated)
        state.last_raw = copy(ev.raw)
        state.status = "Step $(ev.index)"
    elseif ev isa LegacyScanFinished
        state.running = false
        state.status = "Finished: $(ev.points) points"
    elseif ev isa MeasurementStarted
        state.running = true
        state.status = "Measurement started"
    elseif ev isa StepResult
        state.spectrum = ev.spectrum
        state.last_raw = copy(ev.raw)
        state.status = "Step $(ev.index)"
    elseif ev isa MeasurementFinished
        state.running = false
        state.spectrum = ev.spectrum
        state.status = "Measurement finished"
    elseif ev isa MeasurementStopped
        state.running = false
        state.status = "Stopped"
    elseif ev isa MeasurementError
        state.running = false
        state.status = "Error: $(ev.message)"
    end
    return state
end
