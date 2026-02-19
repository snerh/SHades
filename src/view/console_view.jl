function consume_events!(events::Channel{MeasurementEvent}; on_step::Function=(::StepResult)->nothing)
    for ev in events
        if ev isa StepResult
            on_step(ev)
        elseif ev isa MeasurementStarted
            println("Measurement started: $(length(ev.params.wavelengths)) points")
        elseif ev isa MeasurementFinished
            println("Measurement finished: $(length(ev.spectrum.wavelength)) points")
        elseif ev isa MeasurementStopped
            println("Measurement stopped")
        elseif ev isa MeasurementError
            println("Measurement error: $(ev.message)")
        elseif ev isa LegacyScanStarted
            println("Legacy scan started")
        elseif ev isa LegacyScanStep
            println("legacy-step=$(ev.index) file=$(ev.file_stem) sig=$(round(ev.point.sig, digits=3))")
        elseif ev isa LegacyScanFinished
            println("Legacy scan finished: $(ev.points) points")
        end
    end
    nothing
end
