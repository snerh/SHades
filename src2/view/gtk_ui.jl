module GtkUI
abstract type UiEvent end

struct SpectrumUpdated <: UiEvent end
struct PowerUpdated <: UiEvent end

struct SetParam <: SystemEvent
    name::Symbol
    val::String
end

mutable struct AxisEntry <: Gtk.GtkEntry
    handle::Ptr{Gtk.GObject}
    
    function AxisEntry(s, event_ch, init_str)
        entry = Gtk.Entry()
        #set_gtk_property!(entry,:input_purpose,"GTK_INPUT_PURPOSE_NUMBER")
        function callback(w)
            try
                text = Gtk.get_gtk_property(w, "text", String)
                put!(event_ch, SetParam(s,text))
            catch
		        @warn "AxisEntry cant set params"
            end
        end
        
        set_gtk_property!(entry,:text, init_str)
        Gtk.set_gtk_property!(entry, :name, s)
        Gtk.signal_connect(callback, entry, "activate")
        Gtk.signal_connect(callback, entry, "editing-done")
        return Gtk.gobject_move_ref(new(entry.handle), entry)
    end
end

function _build_app_ui(title::String, default_output_dir::String)
    win = Gtk.Window(title, 1080, 720)
    root = Gtk.Box(:h)
    left = Gtk.Box(:v)
    right = Gtk.Box(:v)
    form = Gtk.Grid()

    box = GtkBox(:v)
    label = GtkLabel("0.0")

    push!(box, label)
    push!(win, box)

    showall(win)

end