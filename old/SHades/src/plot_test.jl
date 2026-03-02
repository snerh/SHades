#=
plot_test:
- Julia version: 
- Author: Computer
- Date: 2023-11-07
=#
using Gtk
using Immerse
import NativeFileDialog as NFD
import Base.Threads as Th
latex_fonts = Gadfly.Theme(background_color=Gadfly.colorant"white",
                    major_label_font="CMU Serif", major_label_font_size=26pt,
                    minor_label_font="CMU Serif", minor_label_font_size=26pt,
                    key_title_font="CMU Serif", key_title_font_size=26pt,
                    key_label_font="CMU Serif", key_label_font_size=26pt)
Gadfly.push_theme(latex_fonts)
w = Gtk.GtkWindow()
c = Gtk.GtkCanvas(500,500)
Gtk.set_gtk_property!(c,:expand,true)
b = Gtk.CheckButton("Check me!")
push!(w,c)

p = Gadfly.plot(y=rand(5),Geom.line)
f = Immerse.Figure(c,p)
Immerse.display(f)
signal_connect((a,x) -> open_dialog("Select Dataset Folder", action=GtkFileChooserAction.SELECT_FOLDER), c, "button-press-event")

Gtk.showall(w)
for i in 1:5
sleep(1)
Th.@spawn begin

  p = Gadfly.plot(y=rand(5),Geom.line)


  f = Immerse.Figure(c,p)
  Immerse.display(f)
  #Gadfly.pop_theme()

  end
end
Gadfly.pop_theme()
