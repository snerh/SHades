module GtkUI

import Gtk

using ..State
using ..Parameters
using ..Persistence
using ..ParameterParser
using ..DeviceManager: SystemEvent

export SetParam, AxisEntry, GtkApp, start_gtk_ui!, render!, test_gtk

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
    gtk = Gtk
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
    elseif ax isa ListAxis
        return join(string.(ax.values), ",")
    elseif ax isa RangeAxis
        return "$(ax.range[1]):$(step(ax.range)):$(ax.range[end])"
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
    points = state.current_spectrum === nothing ? 0 : length(state.current_spectrum.wavelength)
    Gtk.set_gtk_property!(ui.status_label, :label, "measurement: $(state.measurement_state)")
    Gtk.set_gtk_property!(ui.power_label, :label, "power: $(round(state.current_power; digits=4))")
    Gtk.set_gtk_property!(ui.points_label, :label, "points: $(points)")
    return nothing
end

function _build_form_box(raw_params::Vector{Pair{Symbol,String}}, event_ch)
    gtk = Gtk
    form = gtk.Box(:v, 10)
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

function start_gtk_ui!(state::AppState, event_ch, ui_channel; config_path::AbstractString="./preset2.json", title::AbstractString="SHades2.0")
    raw_p = load_config(config_path)
    state.raw_params = raw_p 
    state.scan_params = build_scan_axis_set_from_text_specs(raw_p)

    win = Gtk.Window(String(title), 720, 520)
    root = Gtk.Box(:v, 10)

    status_label = Gtk.Label("measurement: $(state.measurement_state)")
    power_label = Gtk.Label("power: $(state.current_power)")
    points_label = Gtk.Label("points: 0")

    header = Gtk.Box(:v, 4)
    push!(header, status_label)
    push!(header, power_label)
    push!(header, points_label)

    form, entries = _build_form_box(raw_p, event_ch)
    #println(form)
    #println(entries)
    #form = Gtk.Button("testste")
    push!(root, header)
    push!(root, form)
    push!(win, root)

    println("5")
    ui = GtkApp(win, entries, status_label, power_label, points_label)

    println("4")
    Gtk.signal_connect(win, "destroy") do _
        println("Window destruction!")
        save_config(config_path, state.raw_params)
        Gtk.gtk_main_running[] && Gtk.gtk_quit()
        return nothing
    end

    Gtk.showall(win)
    println("1")
    function _on_mainloop(f::Function)
        Gtk.GLib.g_idle_add(nothing) do _
            f()
            Cint(false)
        end
        return nothing
    end
    @async begin
        for ui_cmd in ui_channel
            _on_mainloop( () -> render!(ui,state))
        end
    end
    #Gtk.g_idle_add(nothing) do _
    #    while isready(ui_channel)
    #        take!(ui_channel)
    #        render!(ui, state)
    #        println("2")
    #    end
    #    return true
    #end

    render!(ui, state)
    println("3")
    Gtk.gtk_main()
    println(6)
    return ui
end

function test_gtk()
    win = Gtk.Window("test window", 720, 520)
    Gtk.signal_connect(win, "destroy") do _
        Gtk.gtk_main_running[] && Gtk.gtk_quit()
        return nothing
    end
    button = Gtk.Button("123")
    push!(win, button)
    Gtk.showall(win)

    Gtk.gtk_main()
end

end
