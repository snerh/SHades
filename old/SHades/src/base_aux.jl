import  HTTP
import JSON
#import SerialPorts as SP
import DelimitedFiles as DFiles
using Statistics
using Gadfly
using Cairo

import DataFrames as DF

import Base.Threads as Th

include("Lockin_ESP.jl") # ESP32
#include("Lockin.jl") # SR
#include("Lockin0.jl") # SR
include("ELL.jl")
include("Sol.jl")
include("psi_base.jl")
include("Orpheus.jl")
include("Log.jl")

global global_stop = false

function plot_fig(x,acc,raw)
	th = Theme(style(line_width=1mm))
  #Gadfly.push_theme(latex_fonts)
	Gadfly.push_theme(th)
  p1 = plot(x = x, y = getindex.(acc, 6), Geom.line, ); # сигнал гармоники в зависимости от длины волны лазера
  p2 = plot(x = x, y = getindex.(acc, 6), Geom.line, Scale.y_log10); # p1 в логарифмическом масштабе + мощность
  p3 = plot(y = abs.(getindex.(acc, 5)), Geom.line);
  sig = maximum(raw)-median(raw)
  p4 = plot(y = raw, Guide.title(string(sig)) , Geom.line); # сырой спектр с Sol-а
  fig = hstack(vstack(p1, p2), vstack(p3, p4));
  fig |> PNG("./dyn.png",400,250)
  Gadfly.pop_theme()
	#Gadfly.pop_theme()
end

function toname(s)
    s = Symbol(s)
    if s == :wl
        "Wavelength, nm"
    elseif s == :polarizer
        "Polarizer, deg"
    elseif s == :analyzer
        "Analyzer, deg"
    elseif s == :power
        "Power, mV"
    elseif s == :sol_wl
        "Sol wavelength, nm"
    else
      String(s)
    end
end

function plot_fig2(df, cam_data)
		 dep_names = ["1","2","3"]
  function drop_eq(df)
    names = DF.names(df)
    acc = []
    for name in names
      grouped = DF.groupby(df,name)
      if length(grouped) > 1 
        push!(acc,name)
      end
    end
    DF.view(df,:,acc) # dataframe /wo constant columns
  end
  sdf = df #drop_eq(df)
	Log.printlog(sdf)
	sig = maximum(cam_data)-median(cam_data)
	th = Theme(style(line_width=1mm))
  first = dep_names[1]
  if length(dep_names)>1 
      second = dep_names[2]
  else 
      second = first
  end
	latex_fonts = Theme(major_label_font="CMU Serif", major_label_font_size=16pt,
                    minor_label_font="CMU Serif", minor_label_font_size=14pt,
                    key_title_font="CMU Serif", key_title_font_size=12pt,
                    key_label_font="CMU Serif", key_label_font_size=10pt)
  Gadfly.push_theme(latex_fonts)
	Gadfly.push_theme(th)
  #p1 = plot(x = x, y = getindex.(acc, 6), Geom.line, ); # сигнал гармоники в зависимости от длины волны лазера
  #p2 = plot(x = x, y = getindex.(acc, 6), Geom.line, Scale.y_log10); # p1 в логарифмическом масштабе + мощность
  #p3 = plot(y = abs.(getindex.(acc, 5)), Geom.line);
  #p4 = plot(y = raw, Guide.title(string(sig)) , Geom.line); # сырой спектр с Sol-а
  p1 = plot(sdf, x = first, y =:sig, color = second, Scale.color_discrete, Guide.xlabel(toname(first)), Geom.line)
  p2 = plot(sdf, x = first, y =:sig, color = second, Scale.color_discrete, Guide.xlabel(toname(first)), Geom.line, Scale.y_log10)
  p3 = plot(sdf, x = first, y =:real_power, Guide.xlabel(toname(first)), Geom.line)
  p4 = plot(y = cam_data, Guide.title(string(sig)), Guide.xlabel("Pixel"), Geom.line); # сырой спектр с Sol-а
  fig = [p1  p2; p3 p4];
  Gadfly.pop_theme()
	Gadfly.pop_theme()
  fig
end

function read_file_JSON(fname)
  io = open(fname,"r")
  read(io,Char)
  s = readline(io)
  p = JSON.Parser.parse(s)
  if haskey(p,"time")
    	time_u = p["time"]
			p["acq_time"] = p["time"]
	end
	if haskey(p,"acq_time")
      try
          p["acq_time"] = (p["acq_time"][1],p["acq_time"][2]) ## Vector{Any} -> Tuple{Int,String} временный фикс
      catch 
          @warn "Unexpected acq_time in JSON: $(p[acq_time])"
          p["acq_time"]=(1,"s") # fallback constant
      end
    	time_u = p["acq_time"]
	end
	data = DFiles.readdlm(io)
  if !haskey(p,"time_s")
   	time = time_u[1] * (time_u[2]=="ms" ? 1/1000 : 1)
		p["time_s"] = time
	end
	if !haskey(p,"sig")
		sig = maximum(data)-median(data)
		p["sig"] = sig
	end
	if (!haskey(p,"wl")) && haskey(p,"wavelength")
		p["wl"] = p["wavelength"]
	end
  (p, data)
end

function import_dir(dir)
	files = readdir(dir,join = true,sort = true)
  dat_files = filter(x -> x[end-3:end]==".dat",files)
  full_list = map(read_file_JSON, dat_files)
  sorted = sort(full_list,lt = ((x,y) -> x[1]["wl"] < y[1]["wl"]))
	acc = DF.DataFrame([])
	for el in sorted
		p, data = el
		append!(acc, [p])
	end
	acc
end


function plot_fig(x,acc,raw)

	th = Theme(style(line_width=1mm))
  #Gadfly.push_theme(latex_fonts)
	Gadfly.push_theme(th)
  p1 = plot(x = x, y = getindex.(acc, 6), Geom.line, ); # сигнал гармоники в зависимости от длины волны лазера
  p2 = plot(x = x, y = getindex.(acc, 6), Geom.line, Scale.y_log10); # p1 в логарифмическом масштабе + мощность
  p3 = plot(y = abs.(getindex.(acc, 5)), Geom.line);
  sig = maximum(raw)-median(raw)
  p4 = plot(y = raw, Guide.title(string(sig)) , Geom.line); # сырой спектр с Sol-а
  fig = hstack(vstack(p1, p2), vstack(p3, p4));
  fig |> PNG("C:\\work\\soft\\SHades\\dyn.png",400,250)
  Gadfly.pop_theme()
	#Gadfly.pop_theme()
end


function time2sec(time)
  t0, unit = time
  t0 * (
    if unit == "ns"
      10^-9
    elseif unit == "mks"
      10^-6
    elseif unit == "ms"
      10^-3
    elseif unit == "s"
      1
    elseif unit == "min"
      60
    else unit == "h"
      3600
    end)
end

function preset_old(fname = "C:\\work\\soft\\SHades\\preset.json")
  io = open("$conf_dir\\" * fname)
  ell = ELL.open()
  try
    p = JSON.Parser.parse(io)
    function set_home(d)
      ELL.set_offset(ell, d["address"], d["home"] * pi/180)
	  ELL.home(ell, d["address"])
    end
    set_home(p["ell"]["power"])
    set_home(p["ell"]["polarizer"])
    set_home(p["ell"]["analyzer"])
    p
  finally
    close(io)
    ELL.close(ell)
  end

  Orpheus.init(test=false)

end

function preset(fname = "C:\\work\\soft\\SHades\\preset.json")
  io = open(fname)
  try
    p = JSON.Parser.parse(io)
    function set_home(d)
      ELL.set_offset(ell, d["address"], d["home"] * pi/180)
	  ELL.home(ell, d["address"])
    end
    set_home(p["ell"]["power"])
    set_home(p["ell"]["polarizer"])
    set_home(p["ell"]["analyzer"])
    p
  finally
    close(io)
  end
end

function stabilize(s_ell, add, s_lock, ch, time)
	val = 1
	while isready(ch)
      val = take!(ch)
	  Log.printlog("Dropped pow_ch element = ", val)
    end
  while true
    if isready(ch)
      val = take!(ch)
      if val < 0
	      Log.printlog("exit stab")
        return 0
      end
    end
    try
      ang = ELL.gp(s_ell,add)
      Log.printlog("angle = ", ang)
      real_power = Lockin.get(s_lock) # check function
			if real_power < 0
				real_power = abs(real_power)
				@warn "Measured power is negative! You have to go back in time and correct it!"
			end
      Log.printlog("real_power = ", real_power,", set_power = ", val)
      frac0 = sin(ang*2)^2
    #ELL.current_power[1] = real_power
    frac = max(0,min(val/real_power*frac0,1)) # required power fraction
    frac_m = (1/3*frac0+2/3*frac) #smoothing
    ang = asin(frac_m^0.5)/2 # 0 - cross π/4 - parallel
    Log.printlog("new angle = ", ang)
    ELL.ma(s_ell,add,ang) # set angle 
    catch
      Log.printlog("Stabilize caught exception")
      break
    end
	sleep(time)
  end
end # run as task (@async) and stop by hand

function unmuon(d;factor=2)
	frames = length(d)
	px = length(d[1])
	res = Vector{Float64}(undef,px)
	for i in 1:px
		l = map(fr -> fr[i],d)
		s = sort(l)
		function aux(s)
			acc = s[1]
			sigm = sqrt(abs(s[1]))
			for j in 1:frames
				if s[j] > acc + sigm*factor+30
					return acc
				else
					acc = mean(s[1:j])
					sigm = j==1 ? sigm : std(s[1:j])
				end
			end
			acc
		end
		res[i] = aux(s)
	end
	res
end


function get_spec(cam, t; frames=1, back=nothing)
	# измеряем спектр
	Log.printlog("Cam start_scan")
	data = Vector{Vector{Float64}}(undef,frames)
	for i in 1:frames
		PSI.start_scan(cam)
		sleep(t+0.1) # ждем, пока измерится спектр (колбэк пока не работает)
		Log.printlog("Cam get_data")
		data[i] = PSI.get_data(cam)
		if back != nothing
				data[i] = data[i] - back
		end
	end
	unmuon(data)
end

macro setup(cam, spec, lok, ell, body)
  body = esc(body)
	cam = esc(cam)
	spec = esc(spec)
	lok = esc(lok)
	ell = esc(ell)
	:(
	begin
		global close_all = ()-> begin
					PSI.close($cam)
					Sol.close($spec)
					Lockin.close($lok)
					ELL.close($ell)
				end
    Orpheus.init(test=true) # set false for real experiment
    PSI.init()
    $cam = PSI.wait2open()
    $spec = Sol.open()
    $lok = Lockin.open()
    Lockin.init($lok)
    $ell = ELL.open();
	try
    $body;
	catch
		@warn "Setup macro error catched"
  finally
    PSI.close($cam)
		Sol.close($spec)
    Lockin.close($lok)
    ELL.close($ell)
  end end)
end

macro stab(lok, ell, pow_ch, body)
	lok = esc(lok)
	ell = esc(ell)
	body = esc(body)
	#pow_ch = Channel(1)
	pow_ch = esc(pow_ch)
 :(
  task_stab = @async stabilize($ell,1,$lok,$pow_ch ,0.3);
  $body;

  try
    put!($pow_ch, -1.)
		put!($pow_ch, -1.)
    wait(task_stab)
    fetch(task_stab)
  catch
		@warn "Stab macro error catched"
  end
  )
end

function test() ## cam spec lok ell 
  pow_ch = Channel(1)
	@setup(cam, spec, lok, ell, # имена устройств
  @stab(lok, ell, # имена устройств
    pow_ch, # мощность для стабилизации
  begin
    # тело функции измерения
    PSI.set_params(cam, time = time)
    Sol.set_slit(spec,slit)
  end
    
   ))
end

function focus2(wl, ac_time, slit, interaction = "SIG",n = 2;
  power = nothing, ang_p=0,ang_a=0, sub_back = true, lum = nothing, frames = 1) #time = (10,"s")
  pow_ch = Channel(1)
	@setup(cam, spec, lok, ell, # имена устройств
  @stab(lok, ell, pow_ch, # имена устройств и мощность для стабилизации
	begin
    put!(pow_ch,power)
    # тело функции измерения
    PSI.set_params(cam, time = ac_time)
    Sol.set_slit(spec,slit)
    ELL.ma(ell,0,ang_p*π/180) # set polarizer
    sleep(0.1)
    ELL.ma(ell,2,ang_a*π/180) # set analyzer
    t = time2sec(ac_time)
		# закрываем лазер
		if power != nothing
			put!(pow_ch, 0.0001)
		end
    
    old_sol_wl = 0
    acc = []

		# меняем длину волны
    Log.printlog("Orpheus wl = ", wl)
    Orpheus.setWL(wl, interaction)
		# восстанавливаем мощность лазера
		if power != nothing
			put!(pow_ch, power)
		end
    Log.printlog("Press any key to stop.")
    # ишем фоновый сигнал
		if sub_back
        Sol.set_shutter(spec,0)
        Log.printlog("Cam start_scan: back")
        PSI.start_scan(cam)
        sleep(t+0.2) # ждем, пока измерятся спектр (колбэк пока не работает)
        Log.printlog("Cam get_data: back")
        back::Vector{Int32} = PSI.get_data(cam)
        Sol.set_shutter(spec,1)
		else
				back = nothing
    end
    task = Th.@spawn read(stdin, Char) # Слушаем клавиатуру в отдельном потоке 
    

		# переставляем спектрометр, если надо
		if lum == nothing
			sol_wl = round(wl/n /20)*20 #длина волны излучения с шагом 20 нм
		else
			sol_wl = lum
		end
		Log.printlog("SOL wl = ", sol_wl)
		Sol.set_wl(spec,sol_wl)

    # цикл
    while true 

        if istaskdone(task)
            fetch(task)
            Log.printlog("Break")
            break
        end

				if global_stop
    				break
				end
        
        # измеряем спектр
        data = get_spec(cam, t, frames=frames, back=back)

        # измеряем мощность
        pow_mW = Lockin.get(lok) # JSON
        Log.printlog("Power = ", pow_mW)

        #сохраняем данные
        sig = maximum(data)-median(data)
        new_par = (wl/n, 0, 0, time, pow_mW, sig)
        append!(acc, [new_par])
        if length(acc)>200
            acc = acc[end-200:end]
        end
        #строим график
        plot_fig(Vector{Float64}(1:length(acc)), acc,data)

    end
	end
   )dir
   )
end

function series2(wl_range, ac_time, slit, dir, interaction = "SIG", n = 2;
    power=nothing,ang_p=0,ang_a=0, sub_back = true, lum = nothing, frames=1) #time = (10,"s") angles in degrees
	pow_ch = Channel(1)
  @setup(cam, spec, lok, ell, # имена устройств
  @stab(lok, ell, pow_ch, # мощность для стабилизации
  begin
    put!(pow_ch,power)
    # тело функции измерения
    PSI.set_params(cam, time = ac_time)
    Sol.set_slit(spec,slit)
    ELL.ma(ell,0,ang_p*π/180) # set polarizer
    sleep(0.1)
    ELL.ma(ell,2,ang_a*π/180) # set analyzer
    t = time2sec(ac_time)
		# закрываем лазер
		if power != nothing
			put!(pow_ch, 0.0001)
		end

    old_sol_wl = 0
    acc = []

		# меняем длину волны
    Log.printlog("Orpheus wl = ", first(wl_range))
    Orpheus.setWL(first(wl_range), interaction)
		# восстанавливаем мощность лазера
		if power != nothing
			put!(pow_ch, power)
		end
    Log.printlog("Press any key to stop.")
    # ишем фоновый сигнал
		if sub_back
        Sol.set_shutter(spec,0)
        Log.printlog("Cam start_scan: back")
        PSI.start_scan(cam)
        sleep(t+0.2) # ждем, пока измерятся спектр (колбэк пока не работает)
        Log.printlog("Cam get_data: back")
        back::Vector{Int32} = PSI.get_data(cam)
        Sol.set_shutter(spec,1)
		else
				back = nothing
    end
    task = Th.@spawn read(stdin, Char) # Слушаем клавиатуру в отдельном потоке
    
    for wl in wl_range
        if istaskdone(task)
            fetch(task)
            Log.printlog("Break")
            break
        end
        # меняем длину волны
        Log.printlog("Orpheus wl = ", wl)
        Orpheus.setWL(wl, interaction)
				# восстанавливаем мощность лазера
				if power != nothing
					put!(pow_ch, power)
				end
        # переставляем спектрометр, если надо
				if lum == nothing
        	sol_wl = round(wl/n /20)*20 #длина волны излучения с шагом 20 нм
				else
    			sol_wl = lum
				end
        if sol_wl != old_sol_wl
            Log.printlog("SOL wl = ", sol_wl)
            Sol.set_wl(spec,sol_wl)
            old_sol_wl = sol_wl
        end

        sol_pos = Sol.get_wl_steps(spec)
        sleep(1.5)
        # измеряем спектр
        data = get_spec(cam, t, frames=frames, back=back)

        # измеряем мощность
        pow_mW = Lockin.get(lok) # JSON
        Log.printlog("Power = ", pow_mW)

        #сохраняем данные
        sig = maximum(data)-median(data)
        new_par = (wl/n, sol_wl, sol_pos, time, pow_mW, sig)
        append!(acc, [new_par])

        #строим график
        plot_fig(getindex.(acc, 1), acc,data)

        io = open("$dir\\$wl.dat", "w")
        Log.printlog("Writing data to file")
        # длину волны лазера и мощность пишем в шапку файла
        params = (wavelength = wl,
                  sol_wl = sol_wl,
                  sol_step = sol_pos,
                  time = ac_time,
                  power_mW = pow_mW,
                  analyzer = ang_a,
                  polarizer = ang_p
                  )
        write(io, "# $(JSON.json(params))\n")
        # спектр пишем в файл данных
        for i in data
            write(io, "$i\n")
        end
        close(io)
    end
  end
   ))
end



function acq_loop(p_init;delay=1.5, dir=nothing, pl_fun = (pa...) -> gridstack(plot_fig2(pa...)) |> PNG("C:\\work\\soft\\SHades\\dyn.png",400,250)) # p_init = (:wl => 500:1:600,:polarizer => 0:5:45, :analyzer => (:polarizer,x->x))
  pow_ch = Channel(1)

	###### Чтение директории выключено! №№№№
	if dir != nothing
    acc = import_dir(dir)
  else
    acc = DF.DataFrame([])
  end
  @setup(cam, spec, lok, ell, # имена устройств
  @stab(lok, ell, pow_ch, # мощность для стабилизации
  begin
    p0 = fill_empty_params(Dict(),cam, spec, lok, ell, pow_ch)
    set_new_params = diff(set_params, p0, cam, spec, lok, ell, pow_ch)
    back = nothing
    task = Th.@spawn read(stdin, Char) # Слушаем клавиатуру в отдельном потоке
		if haskey(Dict(p_init),:power) # тушим лазер перед перестройкой длины волны если такой параметр есть
			put!(pow_ch, 0.0001)
		end
    #while
      # перебираем параметры
      unwrap(p_init, (p,fname) -> begin
        # break if keypressed
        if istaskdone(task) || global_stop
            fetch(task)
            Log.printlog("Break")
            return "Bye bye!"
        end

        # устанавливаем параметры
        try
          val = p[:sol_wl]
          sol_wl = round(val /20)*20
          p[:sol_wl] = sol_wl
        catch
          @warn "no sol_wl rule, skipped"
        end
        set_new_params(p)
        # Измеряем фон для вычитания, только первый цикл
        if back == nothing
          Sol.set_shutter(spec,0)
          t_s = time2sec(p[:acq_time])
					sleep(2)
          back = get_spec(cam, t_s, frames=p[:frames], back=nothing)
          Sol.set_shutter(spec,1)
        end
        sleep(delay)

        # измеряем спектр
        t_s = time2sec(p[:acq_time])
        data = get_spec(cam, t_s, frames=p[:frames], back=back)
        real_power = Lockin.get(lok)
        p[:real_power] = real_power
        p[:time_s] = t_s

        # строим картинку
        sig = maximum(data)-median(data)
        function matchall(re,s)
          function aux(re,s,acc)
            res = match(re,s)
            if res!=nothing
              aux(re, res[2], append!(acc,[res[1]]))
            else
              acc
            end
          end
          aux(re,s,[])                  
        end
        all_pars = Symbol.(matchall(r"([a-zA-Z]+)[^a-zA-Z]+(.+)", fname))
        p[:sig] = sig
        append!(acc, p)
        Th.@spawn pl_fun(acc, data)

        # сохраняем в файл
        if dir != nothing
          io = open("$dir\\$fname.dat", "w")
          Log.printlog("Writing data to file")
          write(io, "# $(JSON.json(p))\n")
          # спектр пишем в файл данных
          for i in data
            write(io, "$i\n")
          end
          close(io)
        end
				()
      end
      )#unwrap
    #end
  end))
  global global_stop = false
end

function diff(f,i, names...)
  old = Ref(i)
  function aux(p)
    res = f(old.x, p, names...)
		Log.printlog("===== ", old.x, "\n====== ", p)
		#Log.printlog(names...)
		old.x = copy(p)
    res
  end
  aux
end

# wl inter sol_wl acq_time
function set_params(o, p, cam, spec, lok, ell, pow_ch) #old and new parameters
  function ifnew(k, s, f)
    if k == s
			try
				if !(haskey(o,s)) || p[s] != o[s]
					Log.printlog("=====set_params, ",s," -> ", p[s],"======")
					f()
				end
			catch
				@warn "$s setting error.\np = $p\no=$o\ns=$s"
			end
		end
	end
	Log.printlog("\n======set_params======")
	Log.printlog(keys(p))
	for k in keys(p)
		# Длина волны излучения
		ifnew(k, :wl,()-> Orpheus.setWL(p[:wl], p[:inter]))
		# Длина волны спектрометра
		ifnew(k, :sol_wl, () -> begin
			Sol.set_wl(spec, p[:sol_wl])
			p[:sol_step] = Sol.get_wl_steps(spec)
			end
		 )
		# Время измерения
		ifnew(k, :acq_time, ()-> PSI.set_params(cam, time = p[:acq_time]))
		# Щель спектрометра
		ifnew(k, :slit, ()-> Sol.set_slit(spec, p[:slit]))
		# Мощность излучения
		ifnew(k, :power, ()-> put!(pow_ch, p[:power]))
		# Поляризатор/анализаторs
		ifnew(k, :analyzer, ()-> ELL.ma(ell,2,p[:analyzer]*π/180 / 2)) # set analyzer Doubled angle!!!!!
		ifnew(k, :polarizer, ()-> ELL.ma(ell,0,p[:polarizer]*π/180 / 2)) # set polarizer Doubled angle!!!!!
		ifnew(k, :temp, ()-> PSI.set_temp(cam,temp=p[:temp]))
	end
end


###### Дописать!!!! ########

function fill_empty_params(p, cam, spec, lok, ell, pow_ch) #old and new parameters
  function ifempy(k, s, f)
    if k == s
			try
				if !(haskey(p,s))
					Log.printlog("=====fill_empty_params, ", s, " )======")
					f()
				end
			catch
				@warn "$s setting error.\np = $p\no=$o\ns=$s"
			end
		end
	end

	for k in keys(p)
		# Длина волны излучения
		ifempty(k, :wl, ()-> p[:wl] = Orpheus.getWL())
		# Длина волны спектрометра
		ifempty(k, :sol_wl, () -> begin
			p[:sol_wl] = Sol.get_wl(spec)
			p[:sol_step] = Sol.get_wl_steps(spec)
			end
		 )
		# Время измерения
		#ifempty(k, :acq_time, ()-> PSI.set_params(cam, time = p[:acq_time]))
		# Щель спектрометра
		ifempty(k, :slit, ()-> p[:slit] = Sol.get_slit(spec))
		# Поляризатор/анализаторs
		ifempty(k, :analyzer,  ()-> p[:analyzer]  = 180/π * ELL.gp(ell,2)) # set analyzer
		ifempty(k, :polarizer, ()-> p[:polarizer] = 180/π * ELL.gp(ell,0)) # set polarizer
	end
  p
end



function unwrap(p_list, body, p = Dict(), fname="")
  if isempty(p_list)
	return body(p,fname[1:end-1])
  end
  s, val = p_list[1]
  Log.printlog("++++++unwrap++++++")
  Log.printlog(p_list[1])
  if s == :loop
    i=1
    while true
      p[s] = i
      res = unwrap(p_list[2:end], body, p, fname*"loop")
      i = i+1
	  if res == :stop 
		return :stop
	  end		
    end
	res
	
  elseif typeof(val) == StepRange{Int64,Int64} ||
     typeof(val) == StepRangeLen{Float64, Base.TwicePrecision{Float64}, Base.TwicePrecision{Float64}, Int64}
    vec = collect(val)
    for el in vec
      p[s] = el
      res = unwrap(p_list[2:end], body, p, fname*"$(s)_$(el)_")
	  if res == :stop 
		return :stop
	  end
    end
	:continue
	
  elseif typeof(val) <: Real || typeof(val) == String
    p[s] = val
    unwrap(p_list[2:end], body, p, fname)
	
  
  elseif typeof(val) <: Tuple{Symbol,Any}
    ref,fun = val
    p[s] = fun(p[ref])
    unwrap(p_list[2:end], body, p, fname)
  
  elseif typeof(val) == Tuple{Int64,String}
    t_val,t_u = val
    p[s] = val
    unwrap(p_list[2:end], body, p, fname)
	
  else 
	#@warn "Unreacheble place, _unwrap_ on '$s' goes wrong! Ignore and take next"
	unwrap(p_list[2:end], body, p, fname)
	
  end
end
  


function acq_loop2(p_init; devs, delay=1.5, dir=nothing, pl_fun = (pa...) -> gridstack(plot_fig2(pa...)) |> PNG("C:\\work\\soft\\SHades\\dyn.png",400,250)) # p_init = (:wl => 500:1:600,:polarizer => 0:5:45, :analyzer => (:polarizer,x->x))
	Log.printlog("=======acq_loop2======")
  (cam, spec, lok, ell, pow_ch) = devs
  if dir != nothing
    acc = import_dir(dir)
  else
    acc = DF.DataFrame([])
  end
  while isready(pow_ch)
	take!(pow_ch)
  end
  #@setup(cam, spec, lok, ell, # имена устройств
  #@stab(lok, ell, pow_ch, # мощность для стабилизации
  begin
    p0 = fill_empty_params(Dict(),cam, spec, lok, ell, pow_ch)
    set_new_params = diff(set_params, p0, cam, spec, lok, ell, pow_ch)
    back = nothing
		if haskey(Dict(p_init),:power) # тушим лазер перед перестройкой длины волны если такой параметр есть
			put!(pow_ch, 0.0001)
		end
    #while
      # перебираем параметры
      unwrap(p_init, (p,fname) -> begin
        # break if keypressed
        if global_stop
           return :stop
        end

        # устанавливаем параметры
        try
          val = p[:sol_wl]
          sol_wl = round(val /20)*20
          p[:sol_wl] = sol_wl
        catch
          @warn "no sol_wl rule, skipped"
        end
        set_new_params(p)
        # Измеряем фон для вычитания, только первый цикл
        if back == nothing
          Sol.set_shutter(spec,0)
          t_s = time2sec(p[:acq_time])
					sleep(2)
          back = get_spec(cam, t_s, frames=p[:frames], back=nothing)
          Lockin.init(lok)
          Sol.set_shutter(spec,1)
		  try
			if haskey(p,:power)
				for n in 1:5
					pow_iter = (p[:power]/0.0001)^(n/5)*0.0001
					put!(pow_ch, pow_iter)
				end
			end
		  catch
		  @warn "power raise error"
		  end
          sleep(2)
        end
        sleep(delay)
		#Log.printlog("-------------Spectrum measurement---------------")
        # измеряем спектр
		#Log.printlog(p)
		#Log.printlog(p[:acq_time])
        t_s = time2sec(p[:acq_time])
		p[:time_s] = t_s
        data = get_spec(cam, t_s, frames=p[:frames], back=back)
		#Log.printlog("-------------get real_power---------------")
        real_power = Lockin.get(lok)
        if real_power != nothing 
			p[:real_power] = real_power
		else
			p[:real_power] = p[:power]
		end
        

        # строим картинку
        sig = maximum(data)-median(data)
        function matchall(re,s)
          function aux(re,s,acc)
            res = match(re,s)
            if res!=nothing
              aux(re, res[2], append!(acc,[res[1]]))
            else
              acc
            end
          end
          aux(re,s,[])                  
        end
        all_pars = Symbol.(matchall(r"([a-zA-Z]+)[^a-zA-Z]+(.+)", fname))
        p[:sig] = sig
        append!(acc, p)
        #Th.@spawn 
		pl_fun(acc, data)

        # сохраняем в файл
        if dir != nothing
          io = open("$dir\\$fname.dat", "w")
          Log.printlog("Writing data to file")
          write(io, "# $(JSON.json(p))\n")
          # спектр пишем в файл данных
          for i in data
            write(io, "$i\n")
          end
          close(io)
        end
		return :continue
      end
      )#unwrap
    #end
  end
  #))
  global global_stop = false
end