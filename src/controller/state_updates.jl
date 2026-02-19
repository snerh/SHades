function apply_event!(state::AppState, ev::MeasurementEvent)
    if ev isa LegacyScanStarted
        empty!(state.points)
        empty!(state.last_raw)
        state.spectrum = nothing
        state.running = true
        state.status = "Scan started"
        state.progress_step = 0
        state.current_wl = nothing
        state.started_at = time()
    elseif ev isa LegacyScanStep
        push!(state.points, ev.point)
        state.last_raw = copy(ev.raw)
        _maybe_update_spectrum_from_points!(state)
        state.status = "Step $(ev.index)"
        state.progress_step = ev.index
        state.current_wl = isfinite(ev.point.wl) ? ev.point.wl : nothing
    elseif ev isa LegacyScanFinished
        state.running = false
        _maybe_update_spectrum_from_points!(state)
        state.status = "Finished: $(ev.points) points"
        state.progress_step = ev.points
        state.started_at = nothing
    elseif ev isa MeasurementStarted
        state.running = true
        state.status = "Measurement started"
        state.progress_step = 0
        state.current_wl = nothing
        state.started_at = time()
    elseif ev isa StepResult
        state.spectrum = ev.spectrum
        state.last_raw = copy(ev.raw)
        state.status = "Step $(ev.index)"
        state.progress_step = ev.index
        state.current_wl = ev.wavelength
    elseif ev isa MeasurementFinished
        state.running = false
        state.spectrum = ev.spectrum
        state.status = "Measurement finished"
        state.started_at = nothing
    elseif ev isa MeasurementStopped
        state.running = false
        state.status = "Stopped"
        state.started_at = nothing
    elseif ev isa MeasurementError
        state.running = false
        state.status = "Error: $(ev.message)"
        state.started_at = nothing
    end
    return state
end

function _maybe_update_spectrum_from_points!(state::AppState)
    xs = Float64[]
    ys = Float64[]
    for p in state.points
        if isfinite(p.wl) && isfinite(p.sig)
            push!(xs, p.wl)
            push!(ys, p.sig)
        end
    end
    if !isempty(xs)
        state.spectrum = Spectrum(xs, ys)
    end
    return state
end
