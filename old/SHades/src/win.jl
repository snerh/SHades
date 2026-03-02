using Gtk
using Immerse
import Gtk
import Cairo
import Compose
import Base.Threads as Th
import NativeFileDialog as NFD

include("base_aux.jl")
state = Dict()
state[:dir] = "C:\\work\\test\\"
state[:dir] = "."
state[:data] = [1]
state[:cam_data] = [1]
state[:pl_fun] = ()-> ()
mutable struct MyNum <: Gtk.GtkEntry
    handle::Ptr{Gtk.GObject}
    
    function MyNum(s)
        entry = Gtk.Entry()
        #set_gtk_property!(entry,:input_purpose,"GTK_INPUT_PURPOSE_NUMBER")
        function callback(w)
          try
            text = Gtk.get_gtk_property(w, "text", String)
            val = eval(Meta.parse(text))
            state[s] = val
          catch
          end
        end
        Gtk.set_gtk_property!(entry, :name,String(s))
        Gtk.signal_connect(callback, entry, "changed")
        return Gtk.gobject_move_ref(new(entry.handle), entry)
    end
end
mutable struct MyList <: Gtk.GtkComboBoxText
    handle::Ptr{Gtk.GObject}
    
    function MyList(s, choices)
        box = Gtk.ComboBoxText()
        for choice in choices
          push!(box,choice)
        end
        function callback(w)
						text = Gtk.bytestring( GAccessor.active_text(w) )
            state[s] = text
        end
        Gtk.set_gtk_property!(box, :name,String(s))
        Gtk.signal_connect(callback, box, "changed")
        return Gtk.gobject_move_ref(new(box.handle), box)
    end
end

mutable struct MyPlot <: Gtk.GtkComboBoxText
    handle::Ptr{Gtk.GObject}

    function MyPlot(s)
    		g = GtkGrid()
				state[s] = Dict()
				choices = String.([:wl,:sig,:sol_wl,:slit,:time_s,:real_power,:power,:polarizer,:analyzer])
        xbox = Gtk.ComboBoxText()
				ybox = Gtk.ComboBoxText()
				cbox = Gtk.ComboBoxText()
				xcb = Gtk.CheckButton("Polar")
				ycb = Gtk.CheckButton("Log")
				ccb = Gtk.CheckButton("Map")
				for choice in choices
          push!(xbox,choice)
					push!(ybox,choice)
					push!(cbox,choice)
        end
				g[1:2,1] = GtkLabel(String(s))
				g[1,2] = GtkLabel("x")
				g[1,3] = GtkLabel("y")
				g[1,4] = GtkLabel("c")
				g[2,2] = xbox
				g[2,3] = ybox
				g[2,4] = cbox
				g[3,2] = xcb
				g[3,3] = ycb
				g[3,4] = ccb
        function callback(w,axes)
            text = Gtk.bytestring( GAccessor.active_text(w) )
            state[s][axes] = Symbol(text)
            state[:pl_fun]()
        end
				function callback_cb(w,axes)
            b = GAccessor.active(w)
            state[s][axes] = b
            state[:pl_fun]()
        end
        Gtk.signal_connect(w->callback(w,:x), xbox, "changed")
				Gtk.signal_connect(w->callback(w,:y), ybox, "changed")
				Gtk.signal_connect(w->callback(w,:c), cbox, "changed")
				Gtk.signal_connect(w->callback_cb(w,:pol), xcb, "toggled")
				Gtk.signal_connect(w->callback_cb(w,:log), ycb, "toggled")
				Gtk.signal_connect(w->callback_cb(w,:map), ccb, "toggled")
				Gtk.set_gtk_property!(xbox, "active", 0)
				Gtk.set_gtk_property!(ybox, "active", 1)
				Gtk.set_gtk_property!(cbox, "active", 8)
				set_gtk_property!(g[1,2],:hexpand,true)
				set_gtk_property!(g[1,3],:hexpand,true)
				set_gtk_property!(g[1,4],:hexpand,true)
				state[s][:pol]=false
				state[s][:log]=false
				state[s][:map]=false
        return Gtk.gobject_move_ref(new(g.handle), g)
    end
end

function plot_fig_local(df, cam_data)
  sdf = df #drop_eq(df)
	println(sdf)
	sig = maximum(cam_data)-median(cam_data)
	#th = Theme(style(line_width=1mm))
	#latex_fonts = Theme(major_label_font="Serif", major_label_font_size=26pt,
  #                  minor_label_font="Seirf", minor_label_font_size=24pt,
  #                  key_title_font="Serif", key_title_font_size=22pt,
  #                  key_label_font="Serif", key_label_font_size=20pt)
  #Gadfly.push_theme(latex_fonts)
	#Gadfly.push_theme(th)
  #p1 = plot(x = x, y = getindex.(acc, 6), Geom.line, ); # сигнал гармоники в зависимости от длины волны лазера
  #p2 = plot(x = x, y = getindex.(acc, 6), Geom.line, Scale.y_log10); # p1 в логарифмическом масштабе + мощность
  #p3 = plot(y = abs.(getindex.(acc, 5)), Geom.line);
  #p4 = plot(y = raw, Guide.title(string(sig)) , Geom.line); # сырой спектр с Sol-а
  p1 = plot(sdf, x = state[:p1][:x], y = state[:p1][:y], color = state[:p1][:c],
				Guide.xlabel(toname(state[:p1][:x])), Guide.ylabel(toname(state[:p1][:y])),
				state[:p1][:log] ? Scale.y_log10 : Scale.y_continuous,
				state[:p1][:map] ? Geom.rectbin : Geom.line,
				state[:p1][:map] ? Scale.color_continuous : Scale.color_continuous)
  p2 = plot(sdf, x = state[:p2][:x], y = state[:p2][:y], color = state[:p2][:c],
				Guide.xlabel(toname(state[:p2][:x])), Guide.ylabel(toname(state[:p2][:y])),
				state[:p2][:log] ? Scale.y_log10 : Scale.y_continuous,
				state[:p2][:map] ? Geom.rectbin : Geom.line,
				state[:p2][:map] ? Scale.color_continuous : Scale.color_continuous)
  p3 = plot(sdf, y = state[:p3][:y], color = state[:p3][:c],
				Guide.xlabel("Count"), Guide.ylabel(toname(state[:p3][:y])),
				state[:p3][:log] ? Scale.y_log10 : Scale.y_continuous,
				state[:p3][:map] ? Geom.rectbin : Geom.line,
				state[:p3][:map] ? Scale.color_continuous : Scale.color_continuous)
  p4 = plot(y = cam_data, Guide.title(string(sig)), Guide.xlabel("Pixel"), Geom.line); # сырой спектр с Sol-а
  fig = [p1;  p2; p3; p4];
  #Gadfly.pop_theme()
  fig
end



win = Gtk.Window("test window", 640, 480)

i_wl = MyNum(:wl)
i_sol_wl = MyNum(:sol_wl)
i_slit = MyNum(:slit)
i_time  = MyNum(:acq_time)
i_power = MyNum(:power)
i_polarizer   = MyNum(:polarizer)
i_analyzer    = MyNum(:analyzer)
i_frames = MyNum(:frames)
i_delay = MyNum(:delay)
i_inter = MyList(:inter,["SIG","IDL"])
b_pick_dir = Gtk.Button("Dir")
b_run = Gtk.Button("Run")
b_focus = Gtk.Button("Focus")
b_stop = Gtk.Button("Stop")
s1=Gtk.Box(:v)


g = GtkGrid()
l = [("laser λ", i_wl),
     ("interaction",i_inter),
		 ("SOL λ", i_sol_wl),
     ("slit, μm", i_slit),
     ("time",i_time),
		 ("power",i_power),
     ("polarizer",i_polarizer),
     ("analyzer",i_analyzer),
     ("frames", i_frames),
		 ("delay", i_delay),
		 ("",b_pick_dir),
     ("",b_run),
     ("",b_focus),
     ("",b_stop),
     ("",s1)
    ]
for (ind,el) in enumerate(l)
    g[1,ind] = GtkLabel(el[1])
    g[2,ind] = el[2]
end
canvas_grid = Gtk.Grid()
pl1 = g[2,length(l)+1] = MyPlot(:p1)
pl2 = g[2,length(l)+2] = MyPlot(:p2)
pl3 = g[2,length(l)+3] = MyPlot(:p3)
g[3,1:length(l)+3] = canvas_grid

clist = map(x->GtkCanvas(100,100),1:4)
canvas_grid[1,1]=clist[1]
canvas_grid[1,3]=clist[2]
canvas_grid[3,1]=clist[3]
canvas_grid[3,3]=clist[4]
#Gtk.
set_gtk_property!(g, :column_homogeneous, false)
set_gtk_property!(g, :column_spacing, 5)  # introduce a 15-pixel gap between columns
set_gtk_property!(canvas_grid,:expand,true)
set_gtk_property!(s1,:vexpand,true)
set_gtk_property!(clist[1],:expand,true)
set_gtk_property!(clist[2],:expand,true)
set_gtk_property!(clist[3],:expand,true)
set_gtk_property!(clist[4],:expand,true)
set_gtk_property!(pl1,:expand,false)
set_gtk_property!(pl2,:expand,false)
set_gtk_property!(pl3,:expand,false)
push!(win,g)

latex_fonts = Gadfly.Theme(background_color=Gadfly.colorant"white",
										style(line_width=1mm),
                    major_label_font="CMU Serif", major_label_font_size=26pt,
                    minor_label_font="CMU Serif", minor_label_font_size=26pt,
                    key_title_font="CMU Serif", key_title_font_size=26pt,
                    key_label_font="CMU Serif", key_label_font_size=26pt)
Gadfly.push_theme(latex_fonts)

function pl_fun()
  println("pl_fun running")
  state[:plist] = plist = plot_fig_local(state[:data],state[:cam_data])
  function aux(p, c)
    f = Immerse.Figure(c,p)
    Immerse.display(f)
  end
  map(aux, plist, clist)
  ()
end
state[:pl_fun] = pl_fun

function on_run_clicked(w)
  global global_stop = false
  println("acq start!")
  println(collect(state))
  state_clean = copy(state)
  delete!(state_clean,:p1)
  delete!(state_clean,:p2)
  delete!(state_clean,:p3)
  delete!(state_clean,:delay)
  delete!(state_clean,:plist)
  delete!(state_clean,:pl_fun)
	delete!(state_clean,:data)
	delete!(state_clean,:cam_data)
  task = Th.@spawn begin
    println("inside spawn")
    state_list = reverse(sort(collect(state_clean),by=x->x[1]))
		println(state_list)
    acq_loop(state_list, dir=state[:dir], pl_fun = 
         (data,cam_data)-> begin 
           state[:data]=data; 
           state[:cam_data]=cam_data; 
           pl_fun()
         end
         , delay=state[:delay])
  end
  println("callback exit")
end

function on_focus_clicked(w)
  global global_stop = false
  println("focus start!")
  println(collect(state))
  state_clean = copy(state)
  delete!(state_clean,:p1)
  delete!(state_clean,:p2)
  delete!(state_clean,:p3)
  delete!(state_clean,:delay)
  delete!(state_clean,:plist)
  delete!(state_clean,:pl_fun)
	delete!(state_clean,:data)
	delete!(state_clean,:cam_data)
  task = Th.@spawn begin
    println("inside spawn")
    state_list = reverse(sort(collect(state_clean),by=x->x[1]))
		prepend!(state_list,[:loop=>1])
		println(state_list)
    acq_loop(state_list, pl_fun =
         (data,cam_data)-> begin
           state[:data]=data;
           state[:cam_data]=cam_data;
           pl_fun()
         end
         , delay=state[:delay])
  end
  println("callback exit")
end

signal_connect(on_run_clicked,b_run, "clicked")
signal_connect(on_focus_clicked,b_focus, "clicked")
signal_connect(x-> begin
		global global_stop = true
		close_all()
	end, b_stop, "clicked")
signal_connect(x-> begin
	#state[:dir] = NFD.pick_folder(state[:dir])
  state[:dir] = open_dialog("Select Dataset Folder", action=GtkFileChooserAction.SELECT_FOLDER)
  if state[:dir] == ""
    	return ()
			end
	tbl = import_dir(state[:dir])
  state[:data] = tbl
  if size(tbl,1)>0
    	pl_fun()
	end
	end
,b_pick_dir, "clicked")

map( (c, pn) -> begin
      function save_fig(c,button)
	      #file = NFD.save_file(state[:dir])
        file = save_dialog("Save as...", GtkNullContainer(), (GtkFileFilter("*.png, *.svg", name="All supported formats"), "*.png", "*.svg"))
        if file == ""
    				return ()
						end
				ext = match(r"\.([^.]+)$",file)[1]
        Gadfly.push_theme(latex_fonts)
        if ext == "png"
          state[:plist][pn] |> PNG(file,400,300)
        elseif ext == "svg"
          state[:plist][pn] |> SVG(file,12pt,9pt)
        end
        Gadfly.pop_theme()
        ()
      end
      signal_connect(save_fig, c, "button-press-event")
    end
    , clist, 1:4)

showall(win)
#Gadfly.pop_theme()



