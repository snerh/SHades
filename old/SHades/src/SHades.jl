module SHades
using Gtk
using Immerse
import Gadfly
import Gtk
import Cairo
import Compose
import Base.Threads as Th
import JSON

#include("Log.jl")
include("base_aux.jl")
state = Dict()
text_state = Dict()
state[:dir] = "C:\\work\\test\\"
state[:dir] = "."
state[:data] = [1]
state[:cam_data] = [1]
state[:pl_fun] = ()-> ()
cam = spec = lok = ell = pow_ch = nothing
statelk = ReentrantLock()
  
mutable struct MyEntry <: Gtk.GtkEntry
    handle::Ptr{Gtk.GObject}
    
    function MyEntry(s)
        entry = Gtk.Entry()
        #set_gtk_property!(entry,:input_purpose,"GTK_INPUT_PURPOSE_NUMBER")
        function callback(w)
          try
            text = Gtk.get_gtk_property(w, "text", String)
            val = eval(Meta.parse(text))
			text_state[s] = text
            state[s] = val
            save_state(text_state)
          catch
		  @warn "MyEntry callback error"
          end
        end
        if haskey(text_state,s)
            set_gtk_property!(entry,:text, string(text_state[s]))
			state[s] = eval(Meta.parse(text_state[s]))
        end
        Gtk.set_gtk_property!(entry, :name,String(s))
        Gtk.signal_connect(callback, entry, "changed")
        return Gtk.gobject_move_ref(new(entry.handle), entry)
    end
end

mutable struct MyEntry2 <: Gtk.GtkEntry
    handle::Ptr{Gtk.GObject}
    
    function MyEntry2(s)
        entry = Gtk.Entry()
        #set_gtk_property!(entry,:input_purpose,"GTK_INPUT_PURPOSE_NUMBER")
        function callback(w)
          try
            text = Gtk.get_gtk_property(w, "text", String)
            val = eval(Meta.parse(text))
            set_params(Dict(),Dict(s=>val,:inter=>state[:inter]), cam, spec, lok, ell, pow_ch)
          catch
		  @warn "MyEntry2 cant set params"
          end
        end
        if haskey(state,s)
            set_gtk_property!(entry,:text, string(text_state[s]))
        end
        Gtk.set_gtk_property!(entry, :name,String(s))
        Gtk.signal_connect(callback, entry, "activate")
        Gtk.signal_connect(callback, entry, "editing-done")
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
			text_state[s] = text
            state[s] = text
        end
        if haskey(state,s)
            set_gtk_property!(box,:active_text, string(text_state[s]))
			state[s] = text_state[s]
        end
        Gtk.set_gtk_property!(box, :name, String(s))
        Gtk.signal_connect(callback, box, "changed")
        return Gtk.gobject_move_ref(new(box.handle), box)
    end
end

mutable struct MyPlot <: Gtk.GtkBox
    handle::Ptr{Gtk.GObject}
	canvas
    fig
	draw_plot
    function MyPlot(s)
        latex_fonts = Theme(major_label_font="CMU Serif", major_label_font_size=16pt,
                minor_label_font="CMU Serif", minor_label_font_size=16pt,
                key_title_font="CMU Serif", key_title_font_size=12pt,
                key_label_font="CMU Serif", key_label_font_size=10pt,
				line_width = 2pt)
        vb = GtkBox(:v)
        expand = GtkExpander("Settings")
        
        g = GtkGrid()
        if !haskey(text_state,s)
            state[s] = Dict()
            state[s][:pol]=false
            state[s][:log]=false
            state[s][:map]=false
            state[s][:cam]=false
            state[s][:x]=:wl
            state[s][:y]=:wl
            state[s][:c]=:wl
			text_state[s] = state[s]
		else
			state[s]=text_state[s]
        end
        choices = String.([:n,:wl,:sig,:sol_wl,:slit,:time_s,:real_power,:power,:polarizer,:analyzer])
        xbox = Gtk.ComboBoxText()
        ybox = Gtk.ComboBoxText()
        cbox = Gtk.ComboBoxText()
        xcb = Gtk.CheckButton("Polar")
        ycb = Gtk.CheckButton("Log")
        ccb = Gtk.CheckButton("Map")
        camcb = Gtk.CheckButton("Cam data")
        Log.printlog("\n=======MyPlot()==========")
        Log.printlog(state[s])
        #Log.printlog(findfirst(x->x==state[s][:x],choices))
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
        g[3,5] = camcb

        canvas = GtkCanvas(100,100)
		#Gtk.GAccessor.double_buffered(plot_canvas,false)
        set_gtk_property!(canvas,:expand,true)
        push!(vb, expand)
        push!(expand,g)
        push!(vb, canvas)
        show(canvas)
        fig = Immerse.Figure(Immerse.plot())
        Immerse.display(canvas,fig)
		    
		#function get_plot()
		#	Immerse.plot(y=[1 2 3 4])
		#end
        function get_plot()
			#Log.printlog("\n=======get_plot=======")
			#Log.printlog(state)
			#Log.printlog("=======get_plot_end===\n")
			Log.printlog("Lock statelk")
			lock(statelk)
			try
				if haskey(state,:data)
					df = state[:data]
				else 
					return plot()
				end
				cam_data = haskey(state,:cam_data) ? state[:cam_data] : [1]
				sig = maximum(cam_data)-median(cam_data)

				p = if haskey(state[s],:cam) && state[s][:cam]
					plot(
					y = cam_data, 
					Guide.title(string(sig)), Guide.xlabel("Pixel"), Geom.line,
					Scale.x_continuous(format=:plain),
					Scale.y_continuous(format=:plain))
				else
					if state[s][:pol]
						sdf = sort(df,state[s][:x])
						r = sdf[!,state[s][:y]]
						rm = maximum(r)
						Log.printlog("r = ", r)
						phi = sdf[!,state[s][:x]] * (pi/180)
						color = sdf[!,state[s][:c]]
						Log.printlog("phi = ", phi)
						plot(x = r .* cos.(phi), 
							y = r .* sin.(phi),
							color = color,
							Geom.path,
							Coord.cartesian(xmin=-rm, xmax=rm, ymin= -rm,ymax = rm,aspect_ratio=1),
							Scale.x_continuous(format=:plain),
							Scale.y_continuous(format=:plain))
					else
						plot(df, 
						x = state[s][:x]==:n ? (1:1:size(df,1)) : state[s][:x], 
						y = state[s][:y], 
						color = state[s][:c],
						Guide.xlabel(toname(state[s][:x])),
						Guide.ylabel(toname(state[s][:y])),
						state[s][:log] ? Scale.y_log10(format=:plain) : Scale.y_continuous(format=:plain),
						state[s][:map] ? Geom.rectbin : Geom.line,
						Scale.color_continuous)
					end
				end
				return p
			catch e
				Log.printlog("get_plot error: ", e)
				return Immerse.plot()
			finally
				unlock(statelk)
				Log.printlog("Unlock statelk")
			end
        end
        function draw_cb()
            Log.printlog("Plot.draw_plot function")
            function put_plot(plt)
				ctx = getgc(canvas)
				h = height(canvas)
				w = width(canvas)
				# Paint red rectangle
				rectangle(ctx, 0, 0, w, h)
				set_source_rgb(ctx, 1, 1, 1)
				fill(ctx)
                fig.prepped = Gadfly.render_prepare(plt)
				#Log.printlog("\n===== fig.prepped ====")
				#Log.printlog(fig.prepped)
                cc = Immerse.render_finish(fig.prepped; dynamic=false)
                fig.cc = Immerse.apply_tweaks!(cc, fig.tweaks)
				
                #Immerse.display(canvas,fig)
            end

			try 
			#Gadfly.push_theme(latex_fonts)
                plt = try 
                    get_plot()
                catch e
					Log.printlog("get_plot() error: ", e)
                    @warn "get_plot() error"
                    Immerse.plot()
                end
            #Log.printlog("figno = ", fig.figno)
            #put_plot(Immerse.plot())
			#Gtk.draw(canvas)
            put_plot(plt)
			
            Gtk.draw(canvas)
			#Gtk.show(canvas)
            Log.printlog("draw_cb() end")
            catch
				Log.printlog("get_plot() 2 error")
                @warn "get_plot() 2 error"
			end
            nothing
			#Gtk.draw(plot_canvas)
            #Gadfly.pop_theme()
			
        end
		function draw_plot()
			try
				draw_cb()
			catch
				Log.printlog("draw_plot error")
				@warn "draw_plot error"
			end
		end
		#signal_connect(draw_cb,plot_canvas,"draw")


        function save_fig(c,event)
            if event.button == 3 # right button
                file = save_dialog("Save as...", GtkNullContainer(), (GtkFileFilter("*.png, *.svg", name="All supported formats"), "*.png", "*.svg"))
                if file == ""
                            return nothing
                end
                ext = match(r"\.([^.]+)$",file)[1]
                #Gadfly.push_theme(latex_fonts)
                if ext == "png"
					get_plot() |> PNG(file,400,300)
                elseif ext == "svg"
					get_plot() |> SVG(file,12pt,9pt)
                end
                #Gadfly.pop_theme()
                nothing
            end
        end
        signal_connect(save_fig, canvas, "button-press-event")

        function callback(w,axes)
            text = Gtk.bytestring( GAccessor.active_text(w) )
			text_state[s][axes] = text
            state[s][axes] = Symbol(text)
			save_state(text_state)
            draw_plot()
        end
        function callback_cb(w,axes)
            b = GAccessor.active(w)
			text_state[s][axes] = b
            state[s][axes] = b
			save_state(text_state)
            draw_plot()
        end
        Gtk.signal_connect(w->callback(w,:x), xbox, "changed")
        Gtk.signal_connect(w->callback(w,:y), ybox, "changed")
        Gtk.signal_connect(w->callback(w,:c), cbox, "changed")
        Gtk.signal_connect(w->callback_cb(w,:pol), xcb, "toggled")
        Gtk.signal_connect(w->callback_cb(w,:log), ycb, "toggled")
        Gtk.signal_connect(w->callback_cb(w,:map), ccb, "toggled")
        Gtk.signal_connect(w->callback_cb(w,:cam), camcb, "toggled")
		#Gtk.signal_connect(w -> draw_plot(), vb,"notify")
        #Gtk.set_gtk_property!(xbox, "active", 0)
        #Gtk.set_gtk_property!(ybox, "active", 1)
        #Gtk.set_gtk_property!(cbox, "active", 8)
		
		set_gtk_property!(xbox,:active,findfirst(x->x==string(text_state[s][:x]),choices)-1)
		set_gtk_property!(ybox,:active,findfirst(x->x==string(text_state[s][:y]),choices)-1)
		set_gtk_property!(cbox,:active,findfirst(x->x==string(text_state[s][:c]),choices)-1)
		set_gtk_property!(xcb,:active,text_state[s][:pol])
		set_gtk_property!(ycb,:active,text_state[s][:log])
		set_gtk_property!(ccb,:active,text_state[s][:map])
		set_gtk_property!(camcb,:active,text_state[s][:cam])
		set_gtk_property!(g[1,2],:hexpand,true)
        set_gtk_property!(g[1,3],:hexpand,true)
        set_gtk_property!(g[1,4],:hexpand,true)
        return Gtk.gobject_move_ref(new(vb.handle, canvas, fig, draw_plot), vb)
    end
end
function save_state(text_state)
    json = JSON.json(text_state)
    #Log.printlog(json)
    io = open(conf_dir * "\\.state","w")
    write(io, json)
    #Log.printlog("writing state file")
    close(io)
end
function read_state()
    try        
        io = open(conf_dir * "\\.state","r")
        s = readline(io)
        p = JSON.Parser.parse(s,dicttype=Dict{Symbol,Any})
        if haskey(p,"acq_time")
            try
                p["acq_time"] = (p["acq_time"][1],p["acq_time"][2]) ## Vector{Any} -> Tuple{Int,String} временный фикс
            catch 
                @warn "Unexpected acq_time in JSON: $(p[acq_time])"
                p["acq_time"]=(1,"s") # fallback constant
            end
              time_u = p["acq_time"]
        end
        global text_state = p
		try
			state[:dir] = text_state[:dir]
			state[:inter] = text_state[:inter]
		catch
		end
		Log.printlog("\n=========text_state=============")
		Log.printlog(text_state)
        close(io)
    catch
        @warn "No .state backup file"
        global text_state = Dict()
    end
end
function start_app()
		Log.printlog("ARGS = ", ARGS)
		global conf_dir = length(ARGS) > 0 ? ARGS[1] : "."
        read_state()
		latex_fonts = Theme(major_label_font="CMU Serif", major_label_font_size=16pt,
                minor_label_font="CMU Serif", minor_label_font_size=16pt,
                key_title_font="CMU Serif", key_title_font_size=16pt,
                key_label_font="CMU Serif", key_label_font_size=16pt,
				line_width = 2pt)
		Gadfly.push_theme(latex_fonts)
		
        win = Gtk.Window("SHades", 640,480)
        pages = Gtk.GtkNotebook()
        hbox1 = GtkBox(:h)
        exp1 = GtkExpander("")
        plot_paned1 = GtkPaned(:v)
        plot_paned1[1]=GtkPaned(:h)
        plot_paned1[2]=GtkPaned(:h)
        plot_paned1[1][1] = MyPlot(:p1)
        plot_paned1[1][2] = MyPlot(:p2)
        plot_paned1[2][1] = MyPlot(:p3)
        plot_paned1[2][2] = MyPlot(:p4)

        #Gtk.signal_connect(w->callback_cb(w,:cam), plot_paned1, "toggled")
        Gtk.signal_connect((w,alloc)->set_gtk_property!(w,:position, alloc.height/2), plot_paned1, "size-allocate")
        Gtk.signal_connect((w,alloc)->set_gtk_property!(w,:position, alloc.width/2), plot_paned1[1], "size-allocate")
        Gtk.signal_connect((w,alloc)->set_gtk_property!(w,:position, alloc.width/2), plot_paned1[2], "size-allocate")

        g1 = GtkGrid()
        push!(win, pages)
        push!(pages, hbox1, "Scan")
        push!(hbox1,exp1)
        push!(hbox1,plot_paned1)
        push!(exp1,g1)
        
        i_wl = MyEntry(:wl)
        i_sol_wl = MyEntry(:sol_wl)
        i_slit = MyEntry(:slit)
        i_time  = MyEntry(:acq_time)
        i_power = MyEntry(:power)
        i_polarizer   = MyEntry(:polarizer)
        i_analyzer    = MyEntry(:analyzer)
        i_frames = MyEntry(:frames)
        i_delay = MyEntry(:delay)
        i_inter = MyList(:inter,["SIG","IDL"])
        b_pick_dir = Gtk.Button("Dir")
        b_scan = Gtk.Button("Run")
        #b_focus = Gtk.Button("Focus")
        b_stop = Gtk.Button("Stop")
        #s1=Gtk.Box(:v)
        
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
            ("",b_scan),
            #("",b_focus),
            ("",b_stop),
            #("",s1)
            ]
        for (ind,el) in enumerate(l)
            g1[1,ind] = GtkLabel(el[1])
            g1[2,ind] = el[2]
        end

        hbox2 = GtkBox(:h)
        exp2 = GtkExpander("")
        plot_paned2 = GtkPaned(:v)
        plot_paned2[1] = MyPlot(:fp1)
        plot_paned2[2] = MyPlot(:fp2)
        g2 = GtkGrid()
        i2_wl = MyEntry2(:wl,)
        i2_sol_wl = MyEntry2(:sol_wl)
        i2_slit = MyEntry2(:slit)
        i2_time  = MyEntry2(:acq_time)
        i2_power = MyEntry2(:power)
        i2_polarizer   = MyEntry2(:polarizer)
        i2_analyzer    = MyEntry2(:analyzer)
		i2_temperature = MyEntry2(:temp)
		i2_t_ind = GtkLabel("")
		i2_testOrpheus = Gtk.CheckButton("Test_Orpheus")
        tb_connect = Gtk.ToggleButton("Connect")
        b_focus = Gtk.Button("Focus")
        tb_power = Gtk.ToggleButton("Power stab")
        b_stop2 = Gtk.Button("Stop")
        #s1=Gtk.Box(:v)
        l = [("",tb_connect),
            ("laser λ", i2_wl),
            ("SOL λ", i2_sol_wl),
            ("slit, μm", i2_slit),
            ("time",i2_time),
            ("power",i2_power),
            ("polarizer",i2_polarizer),
            ("analyzer",i2_analyzer),
			("temperature", i2_temperature),
			("Tcam = ",i2_t_ind),
			("",i2_testOrpheus),
            ("",tb_power),
            ("",b_focus),
            ("",b_stop2),
            ]
        for (ind,el) in enumerate(l)
            g2[1,ind] = GtkLabel(el[1])
            g2[2,ind] = el[2]
        end
        push!(pages, hbox2, "Focus")
        push!(hbox2,exp2)
        push!(hbox2,plot_paned2)
        push!(exp2,g2)
        #Gtk.signal_connect((w,alloc)->set_gtk_property!(w,:position, alloc.width/2), plot_paned2, "size-allocate")

        function pl_fun()
			Log.printlog("pl_fun")
			#Log.printlog(plot_paned1[1][1])
			try
            plot_paned1[1][1].draw_plot()
            plot_paned1[1][2].draw_plot()
            plot_paned1[2][1].draw_plot()
            plot_paned1[2][2].draw_plot()
            plot_paned2[1].draw_plot()
            plot_paned2[2].draw_plot()
			catch
				Log.printlog("pl_fun error")
				@warn "pl_fun error"
			end
        end

        function on_connect_toggled(w)
            b = GAccessor.active(w)
			Log.printlog("conf_dir = ", conf_dir)
            if b
				test = GAccessor.active(i2_testOrpheus)
				Log.printlog("Connect: orpheus")
                Orpheus.init(test=test) # set false for real experiment
				Log.printlog("Connect: camera")
                PSI.init()
                global cam = PSI.wait2open()
				Log.printlog("Connect: MS5204i")
                global spec = Sol.open(conf_dir = conf_dir)
				Log.printlog("Connect: Lockin")
                global lok = Lockin.open()
                #Lockin.init(lok)
				Log.printlog("Connect: ELL")
                global ell = ELL.open()
				Log.printlog("Connect: power channel")
                global pow_ch = Channel(Inf)
				preset(conf_dir*"\\preset.json")
            else
				print("Disconnection...")
                PSI.close(cam)
                Sol.close(spec)
                Lockin.close(lok)
                ELL.close(ell)
				Log.printlog(" done.")
            end
        end

        function on_power_toggled(w)
            b = GAccessor.active(w)
            if b
                task_stab = Th.@spawn stabilize(ell,1,lok,pow_ch ,0.3);
            else
                try
                    put!(pow_ch, -1.)
                catch
                    @warn "Stab macro error catched"
                end
            end
        end

        function on_scan_clicked(w)
            global global_stop = false
            Log.printlog("acq start!")
            #Log.printlog(collect(state))
            state_clean = copy(state)
            delete!(state_clean,:p1)
            delete!(state_clean,:p2)
            delete!(state_clean,:p3)
            delete!(state_clean,:p4)
            delete!(state_clean,:fp1)
            delete!(state_clean,:fp2)
            delete!(state_clean,:fp3)
            delete!(state_clean,:delay)
            delete!(state_clean,:plist)
            delete!(state_clean,:pl_fun)
            delete!(state_clean,:data)
            delete!(state_clean,:cam_data)
            devs = (cam, spec, lok, ell, pow_ch)
            
            task = Th.@async begin
                Log.printlog("inside spawn")
                state_list = reverse(sort(collect(state_clean),by=x->x[1]))
				Log.printlog(state_list)
                acq_loop2(state_list, devs=devs, dir=state[:dir], pl_fun = 
                   (data,cam_data)-> begin
				     Log.printlog("Lock statelk acq")
				     lock(statelk)
					 try
						state[:data]=data; 
						state[:cam_data]=cam_data;
					 finally
						unlock(statelk)
						Log.printlog("Unlock statelk acq")
					 end						
                     pl_fun()
                   end
                   , delay=state[:delay])
            end
			#sleep(1)
            Log.printlog("callback exit")
        end

        function on_focus_clicked(w)
            global global_stop = false
            Log.printlog("focus start!")
            devs = (cam, spec, lok, ell, pow_ch)
            
            task = Th.@async begin
                Log.printlog("inside spawn")
                state_list = [:loop=>1,:acq_time => state[:acq_time],:frames=>1]
                Log.printlog(state_list)
                acq_loop2(state_list, devs=devs, dir=nothing, pl_fun = 
                   (data,cam_data)-> begin
					 Log.printlog("Lock statelk Focus")
				     lock(statelk)
					 try
						state[:data]=data; 
						state[:cam_data]=cam_data;
					 finally
						unlock(statelk)
						Log.printlog("Unlock statelk focus")
					 end						
                     pl_fun()
                   end
                   , delay=state[:delay])
            end
            Log.printlog("callback exit")
        end
		
		function on_win_destroy(w)
			Gadfly.pop_theme()
			if GAccessor.active(tb_connect)
				print("Disconnection...")
				PSI.close(cam)
				Sol.close(spec)
				Lockin.close(lok)
				ELL.close(ell)
				Log.printlog(" done.")
			end
		end

		signal_connect(w ->
			begin
				text_entry = get_gtk_property(i2_temperature, "text", String)
				PSI.set_temp(cam,temp=Meta.parse(text_entry))
				Th.@spawn begin
					while true
						temp = PSI.get_temp(cam)
						Log.printlog("temp = ", temp)
						set_gtk_property!(i2_t_ind,:label,string(PSI.get_temp(cam)))
						text_entry = get_gtk_property(i2_temperature, "text", String)
						Log.printlog("text_entry = ", text_entry)
						if string(temp) == text_entry
							return ()
						else
							sleep(2)
						end
					end
				end
			end,
				i2_temperature,"activate")
				
        signal_connect(on_connect_toggled,tb_connect, "toggled")
        signal_connect(on_power_toggled,tb_power, "toggled")
        signal_connect(on_scan_clicked,b_scan, "clicked")
        signal_connect(on_focus_clicked,b_focus, "clicked")
		signal_connect(on_win_destroy, win, "destroy")
        signal_connect(x-> 
        begin
            global global_stop = true
        end, b_stop, "clicked")
        signal_connect(x->
        begin
            global global_stop = true
        end, b_stop2, "clicked")

        signal_connect(x-> 
        begin
            state[:dir] = open_dialog("Select Dataset Folder", action=GtkFileChooserAction.SELECT_FOLDER)
            if state[:dir] == ""
                return ()
            end
            tbl = import_dir(state[:dir])
            state[:data] = tbl
            if size(tbl,1)>0
                pl_fun()       # включить отрисовку!!!!!!
            end
        end
        ,b_pick_dir, "clicked")

        showall(win)
    end

    function julia_main()
        start_app()
        while true
            input = readline()
            if input == ""
                break
            end
        end
    end
end
