module GtkUI

using ..State
using ..Parameters
using ..Persistence
using ..ParameterParser
using ..DeviceManager: SystemEvent

export SetParam, AxisEntry, GtkApp, start_gtk_ui!, render!

const _gtk_mod = Ref{Any}(nothing)

function _gtk()
    if _gtk_mod[] === nothing
        @eval import Gtk
        _gtk_mod[] = Gtk
    end
    return _gtk_mod[]
end

struct SetParam <: SystemEvent
    name::Symbol
    val::String
end

mutable struct AxisEntry
    name::Symbol
    widget::Any
end

mutable struct GtkApp
    win::Any
    entries::Dict{Symbol,AxisEntry}
    status_label::Any
    power_label::Any
    points_label::Any
end

function AxisEntry(name::Symbol, event_ch, init_str::AbstractString)
    gtk = _gtk()
    entry = gtk.Entry()
    gtk.set_gtk_property!(entry, :text, String(init_str))

    function callback(_...)
        text = gtk.get_gtk_property(entry, "text", String)
        put!(event_ch, SetParam(name, text))
        return nothing
    end

    gtk.signal_connect(callback, entry, "activate")
    gtk.signal_connect(callback, entry, "editing-done")
    return AxisEntry(name, entry)
end

function _axis_to_text(ax::ScanAxis)
    if ax isa FixedAxis
        return string(ax.value)
    elseif ax isa IndependentAxis
        return join(string.(ax.values), ",")
    elseif ax isa LoopAxis
        if ax.stop === nothing
            return "$(ax.start):$(ax.step)"
        end
        return "$(ax.start):$(ax.step):$(ax.stop)"
    end
    return ""
end

function _raw_params_from_plan(plan::ScanAxisSet)
    raw = Pair{Symbol,String}[]
    for ax in plan.axes
        push!(raw, axis_name(ax) => _axis_to_text(ax))
    end
    return raw
end

function render!(ui::GtkApp, state::AppState)
    gtk = _gtk()
    points = state.current_spectrum === nothing ? 0 : length(state.current_spectrum.wavelength)
    gtk.set_gtk_property!(ui.status_label, :label, "measurement: $(state.measurement_state)")
    gtk.set_gtk_property!(ui.power_label, :label, "power: $(round(state.current_power; digits=4))")
    gtk.set_gtk_property!(ui.points_label, :label, "points: $(points)")
    return nothing
end

function _build_form_box(raw_params::Vector{Pair{Symbol,String}}, event_ch)
    gtk = _gtk()
    form = gtk.Box(:v, 6)
    entries = Dict{Symbol,AxisEntry}()

    for (name, value) in raw_params
        row = gtk.Box(:h, 8)
        label = gtk.Label(String(name))
        entry = AxisEntry(name, event_ch, value)
        push!(row, label)
        push!(row, entry.widget)
        push!(form, row)
        entries[name] = entry
    end
    return form, entries
end

function start_gtk_ui!(state::AppState, event_ch, ui_channel; config_path::AbstractString="preset.toml", title::AbstractString="SHades2.0")
    gtk = _gtk()
    GLib = gtk.GLib

    plan = load_config(config_path)
    raw_params = _raw_params_from_plan(plan)
    state.raw_params = raw_params
    state.scan_params = build_scan_axis_set_from_text_specs(raw_params)

    win = gtk.Window(String(title), 720, 520)
    root = gtk.Box(:v, 10)

    status_label = gtk.Label("measurement: $(state.measurement_state)")
    power_label = gtk.Label("power: $(state.current_power)")
    points_label = gtk.Label("points: 0")

    header = gtk.Box(:v, 4)
    push!(header, status_label)
    push!(header, power_label)
    push!(header, points_label)

    form, entries = _build_form_box(raw_params, event_ch)

    push!(root, header)
    push!(root, form)
    push!(win, root)

    ui = GtkApp(win, entries, status_label, power_label, points_label)

    GLib.idle_add() do
        while isready(ui_channel)
            take!(ui_channel)
            render!(ui, state)
        end
        return true
    end

    render!(ui, state)
    gtk.showall(win)
    return ui
end

end
