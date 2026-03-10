module Calibr
  include("Log.jl")
  import DelimitedFiles as DF
  function aux(a, f::Float64)
    if typeof(a[1]) <: Int
        Int(round(f))
    else
        f
    end
  end

  struct T{El}
    x::Array{El}
    st::Array{Int64}
    x2st::Function
    st2x::Function
  end

  function T(x, y, zshift = 0)
    function lin(a, v)
        eq = findfirst(x -> x==v, a)
        if eq != nothing
            return (eq,eq,1)
        end
        gr = findfirst(x -> x>= v, a)
        if gr == 1 
            (1, 1, 1)
        else
            (gr-1, gr, (a[gr]-v) / (a[gr]-a[gr-1]))
        end
    end
    function x2st(v)
        i1,i2,p = lin(x, v)
        Int(round(  y[i1]*p + y[i2]*(1-p) + zshift ))
    end
    function st2x(v)
        i1,i2,p = lin(y, v-zshift)
        aux(x, Float64(x[i1]*p + x[i2]*(1-p)))
    end
    Calibr.T(x, y, x2st, st2x)
end

function from_file(file)
	Log.printlog("Sol calibr reading from file ", file)
    mx = DF.readdlm(file)
    Calibr.T(mx[2:end,1], Int64.(round.(mx[2:end,2])), mx[1,2])
end
end


module Sol
include("Log.jl")
mot_num = [1;5;9;6;8] # wl tur sl port shutter
import ..Calibr
import LibSerialPort as LSP
include("readl.jl")
lk = ReentrantLock() # lock read-write sequence

struct Spec
    s
    motors::Vector{Int64}
    mot_cals::Vector{Calibr.T}
    wl_cals::Vector{Calibr.T}
end
function Spec(s)
    Spec(s, [], [], [] )
end

function open(port = "COM5"; conf_dir = ".")
    s = LSP.open(port, 9600)
    motors = zeros(length(mot_num))
    motors = map( x -> get_motor(Spec(s), x), mot_num)
    tur_c = Calibr.T([1;2;3;4],[10968; 30964; 50958; 70960])
    sl_c = Calibr.T([0;5000], [271;10271])
    port_c = Calibr.T([0;1], [527;5900]) # 1 - CCD
    shutter_c = Calibr.T([0;1], [0;128]) # 0 - closed
    cal_files = [joinpath(conf_dir, f) for f in ("gr1.cal", "gr2.cal", "gr3.cal", "mir.cal")]
    Spec(s, motors,
         [Calibr.T([0],[0]); tur_c; sl_c; port_c; shutter_c],
         map(Calibr.from_file, cal_files)
        )
end
function close(s)
    LSP.close(s.s)
end

function num2bel(n,pad=1)
    tmp::Vector{UInt8} = digits(n,base=16,pad = pad)
    #push!(tmp, 0)
    tmp = tmp .+ 48
    acc = ""
    for c in tmp
        acc = Char(c)*acc
    end
    acc
end
function bel2num(b)
    tmp = Vector{UInt8}(b) .- 48
    factor = 1
    acc = 0
    for i in tmp[end:-1:1]
        acc += i*factor
        factor *= 16
    end
    acc
end
function wait2read(s,timeout = 20)
    t1 = time()
    task_read = Threads.@spawn readl(s,'\n')
    while (time()-t1 < timeout)
         if istaskdone(task_read)
             return fetch(task_read)
         else
      sleep(0.01)
    end
  end
  @warn "SOL read timeout"
  ""
end

function get_motor(s, n)
  lock(lk)
  try
    #LSP.sp_flush(s.s,LSP.SP_BUF_BOTH)
    num_str = num2bel(n,2)*num2bel(n+6,2)
	try
		Log.printlog("Sol writing: 'SS",num_str,"'\n")
	catch e
		println(e)
	end
    write(s.s,"SS$num_str\n")
    vec = wait2read(s.s)
    Log.printlog("Sol readed: ", vec)
    steps = bel2num(vec)
    ind = findfirst(x -> x==n, mot_num)
    # if ind != nothing s.motors[ind] = steps end
    return steps
  catch
    @warn "Sol get_motor error"
  finally
    unlock(lk)
  end
end
function inc_motor(s, n, steps)
  lock(lk)
  try
    #LSP.sp_flush(s.s,LSP.SP_BUF_BOTH)
    n_str = num2bel(n,1)
    str = num2bel(steps)
    Log.printlog("Sol writing: 'I", n_str, str, "'\n")
    write(s.s,"I$n_str$str\n")
    res = wait2read(s.s)
    Log.printlog("Sol readed: ", res)
    ind = findfirst(x -> x==n, mot_num)
    if ind != nothing s.motors[ind] += steps end
    return res
  finally
    unlock(lk)
  end
end
function dec_motor(s, n, steps)
  lock(lk)
  try
    #LSP.sp_flush(s.s,LSP.SP_BUF_BOTH)
    n_str = num2bel(n,1)
    str = num2bel(steps)
    Log.printlog("Sol writing: 'D", n_str, str, "'\n")
    write(s.s,"D$n_str$str\n")
    res = wait2read(s.s)
    Log.printlog("Sol readed: ", res)
    ind = findfirst(x -> x==n, mot_num)
    if ind != nothing s.motors[ind] -= steps end
    return res
  finally
    unlock(lk)
  end
end

function reset_motor(s, n)
  lock(lk)
  try
    #LSP.sp_flush(s.s,LSP.SP_BUF_BOTH)
    write(s.s,"R$n\n")
    return wait2read(s.s)
  finally
    unlock(lk)
  end
end

function set_pos(s, motor, pos)
    num = Sol.mot_num[motor]
    step0 = s.motors[motor]
    cal = s.mot_cals[motor]
    new_steps = cal.x2st(pos)
    diff = new_steps - step0
    if motor == 5
        diff = sign(diff)end
    if diff > 0
        inc_motor(s, num, diff)
    elseif diff < 0
        dec_motor(s, num, -diff)
    end
end

function get_pos(s, motor)
    num = Sol.mot_num[motor]
    steps = get_motor(s, num)
    cal = s.mot_cals[motor]
    pos = cal.st2x(steps)
    pos
end

function get_wl_steps(s)
    get_motor(s, 1)
end

function set_wl_steps(s, steps)
    steps0 = s.motors[1]

    if steps > steps0
        inc_motor(s, 1, steps - steps0)
    else
        dec_motor(s, 1, steps0 - steps + 3200)
        inc_motor(s, 1, 3200)
    end
end

function set_wl(s, wl)
    tur_cal = s.mot_cals[2]
    tur_pos = tur_cal.st2x(get_motor(s, Sol.mot_num[2])) # номер текущей решетки
    wl_cal = s.wl_cals[tur_pos]
    set_wl_steps(s, wl_cal.x2st(wl))
end
function get_wl(s)
    tur_cal = s.mot_cals[2]
    tur_pos = tur_cal.st2x(get_motor(s, Sol.mot_num[2])) # номер текущей решетки
    wl_cal = s.wl_cals[tur_pos]
    wl_cal.st2x(get_wl_steps(s))
end
function set_shutter(s, new_state)
    set_pos(s, 5, new_state)
end

function set_slit(s, w)
    set_pos(s, 3, w)
end
function get_slit(s)
    get_pos(s, 3)
end
end
