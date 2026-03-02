import Gtk

Base.@kwdef struct GtkEventHandlers
    on_started::Function = _ -> nothing
    on_step::Function = _ -> nothing
    on_finished::Function = _ -> nothing
    on_stopped::Function = _ -> nothing
    on_error::Function = _ -> nothing
end

function _dispatch_event!(handlers::GtkEventHandlers, ev::MeasurementEvent)
    if ev isa MeasurementStarted
        handlers.on_started(ev)
    elseif ev isa StepResult
        handlers.on_step(ev)
    elseif ev isa MeasurementFinished
        handlers.on_finished(ev)
    elseif ev isa MeasurementStopped
        handlers.on_stopped(ev)
    elseif ev isa MeasurementError
        handlers.on_error(ev)
    elseif ev isa LegacyScanStarted
        handlers.on_started(ev)
    elseif ev isa LegacyScanStep
        handlers.on_step(ev)
    elseif ev isa LegacyScanFinished
        handlers.on_finished(ev)
    end
    return nothing
end

function _on_mainloop(f::Function)
    Gtk.GLib.g_idle_add(nothing) do _
        f()
        Cint(false)
    end
    return nothing
end

function consume_events_gtk!(events::Channel{MeasurementEvent}; handlers::GtkEventHandlers=GtkEventHandlers())
    @async begin
        for ev in events
            _on_mainloop(() -> _dispatch_event!(handlers, ev))
        end
    end
end

function bind_stop_button!(button, session::MeasurementSession)
    Gtk.signal_connect(button, "clicked") do _
        stop_measurement!(session)
    end
    return button
end

function bind_pause_toggle!(button, session::MeasurementSession)
    Gtk.signal_connect(button, "toggled") do w
        if Gtk.GAccessor.active(w)
            pause_measurement!(session)
        else
            resume_measurement!(session)
        end
    end
    return button
end
