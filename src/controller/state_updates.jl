function apply_event!(state::AppState, ev::MeasurementEvent)
    if ev isa LegacyScanStarted
        empty!(state.points)
        empty!(state.last_raw)
        state.running = true
        state.status = "Scan started"
    elseif ev isa LegacyScanStep
        state.points = copy(ev.accumulated)
        state.last_raw = copy(ev.raw)
        _maybe_update_spectrum_from_points!(state)
        state.status = "Step $(ev.index)"
    elseif ev isa LegacyScanFinished
        state.running = false
        _maybe_update_spectrum_from_points!(state)
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

function _maybe_update_spectrum_from_points!(state::AppState)
    xs = Float64[]
    ys = Float64[]
    for p in state.points
        x = get(p, :wl, NaN)
        y = get(p, :sig, NaN)
        x isa Number || continue
        y isa Number || continue
        xf = Float64(x)
        yf = Float64(y)
        if isfinite(xf) && isfinite(yf)
            push!(xs, xf)
            push!(ys, yf)
        end
    end
    if !isempty(xs)
        state.spectrum = Spectrum(xs, ys)
    end
    return state
end
