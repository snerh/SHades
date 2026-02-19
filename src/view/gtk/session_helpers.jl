function _gtk_refresh_plots!(
    state::AppState,
    status,
    canvas_signal,
    canvas_raw,
    plot::GtkLegacyPlotRefs,
    ;
    status_text::Union{Nothing,String}=nothing,
    overlays::Vector{NamedTuple{(:label, :points, :color),Tuple{String,Vector{ScanPoint},NTuple{3,Float64}}}}=NamedTuple{(:label, :points, :color),Tuple{String,Vector{ScanPoint},NTuple{3,Float64}}}[],
)
    ps = _gtk_active_plot_settings(plot)
    _render_signal_canvas!(canvas_signal, state, ps.xaxis, ps.yaxis; mode=ps.mode, zaxis=ps.zaxis, log_scale=ps.log_scale, overlays=overlays)
    _render_raw_canvas!(canvas_raw, state)
    Gtk.set_gtk_property!(status, :label, status_text === nothing ? state.status : status_text)
    return nothing
end

function _gtk_attach_session!(
    session_ref::Base.RefValue{Union{Nothing,MeasurementSession}},
    stop_btn,
    pause_btn,
    state::AppState,
    refresh_plots!::Function,
    session::MeasurementSession,
    ;
    on_started_cb::Function = _ -> nothing,
    on_step_cb::Function = _ -> nothing,
    on_terminal_cb::Function = (_, _) -> nothing,
)
    session_ref[] = session
    handlers = GtkEventHandlers(
        on_started = ev -> begin
            apply_event!(state, ev)
            on_started_cb(ev)
            refresh_plots!()
        end,
        on_step = ev -> begin
            apply_event!(state, ev)
            on_step_cb(ev)
            refresh_plots!()
        end,
        on_finished = ev -> begin
            apply_event!(state, ev)
            session_ref[] = nothing
            on_terminal_cb(:finished, ev)
            refresh_plots!()
        end,
        on_stopped = ev -> begin
            apply_event!(state, ev)
            session_ref[] = nothing
            on_terminal_cb(:stopped, ev)
            refresh_plots!()
        end,
        on_error = ev -> begin
            apply_event!(state, ev)
            session_ref[] = nothing
            on_terminal_cb(:error, ev)
            refresh_plots!()
        end,
    )
    consume_events_gtk!(session.events; handlers=handlers)
    return nothing
end
