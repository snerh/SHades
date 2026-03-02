using DelimitedFiles
using Plots
using Statistics
using JSON

function read_file(fname)
  io = open(fname,"r")
  read_first_num() = parse(Float64,match(r"[0-9.]+",readline(io)).match)
  function read_time()
    m = match(r"([0-9.]+), \"(.*)\"",readline(io))
    c = m.captures
    t = parse(Float64,c[1])
    u = c[2]
    if u == "ms"
      t = t/1000
    end
    t
  end
   
  wl = read_first_num()
  sol_wl = read_first_num()
  sol_steps = read_first_num()
  time = read_time()
  power = read_first_num()
  data = readdlm(io)
  d = Dict([
            ("wavelength", wl),
            ("sol_wl",sol_wl),
            ("sol_steps",sol_steps),
            ("time_s",time),
            ("power_mW",power)
           ])
  (d, data)
end

function read_file_JSON(fname)
  io = open(fname,"r")
  read(io,Char)
  s = readline(io)
  json = JSON.Parser.parse(s)
  time_u = json["time"]
  time = time_u[1] * (time_u[2]=="ms" ? 1/1000 : 1)
  push!(json,"time_s"=>time)
  data = readdlm(io)
  (json, data)
end

function readdir_SHG(dir; json = false)
  files = readdir(dir,join = true,sort = true)
  dat_files = filter(x -> x[end-3:end]==".dat",files)
  full_list = map(json ? read_file_JSON : read_file, dat_files)
  sort(full_list,lt = ((x,y) -> x[1]["wavelength"] < y[1]["wavelength"]))
end

function plot_power!(l,n = 2)
  pow = map(x -> x[1]["power_mW"],l)
  wl = map(x -> x[1]["wavelength"],l)
  plot!(wl./n,pow)
end

function get_SHG(l,n = 2; back = nothing)
  wl = map(x -> x[1]["wavelength"],l)
  pow = map(x -> x[1]["power_mW"],l)
  t = map(x -> x[1]["time_s"],l)

  function aux(el)
    if back != nothing
      s = el[2] - back[2]
    else
      s = el[2]
    end
    sig = maximum(s) - median(s)
  end
  s = map(aux, l)
  (wl./n, s./t./(pow.^n))
  #plot!(wl./n,pow)
  #plot!(wl./n,s./pow.^n,yaxis = :log)
end

function plot_SHG!(l,n = 2; back = nothing)
  plot!(get_SHG(l,n,back=back)...)
end

function read_Sol(fname)
   io = open(fname,"r")
   dat = readdlm(io,skipstart=1)
end
function readdir_Sol(dir)
  files = readdir(dir,join = true,sort = true)
  dat_files = filter(x -> x[end-3:end]==".dat",files)
  for fname in dat_files
    m = read_Sol(fname)
    i = maximum(m[:,3]) -  - median(m[:,3])
    println("$(basename(fname)) $i")
  end
end

function pl_part(p,n,el)
  wl = el[1]["wavelength"]
  sol_wl = el[1]["sol_wl"]
  data = el[2]
  y = map(a -> (a - 1024)*0.03 + sol_wl,1:2048)
  heatmap!(p,[wl],y,log.(abs.(data)))
  #heatmap!(p,[wl],y,data)
end

function heatmap_SHG(p,l)
  #p = heatmap()
  for n in 1:length(l)
    pl_part(p,n,l[n])
  end
  p
end
function heatmap_SHG(l)
  p = heatmap(xlims=(800,900))
  heatmap_SHG(p,l)
end

function map_SHG(f,l...)
  res = Vector{Tuple{Dict{String, Any}, Matrix{Float64}}}(undef,length(l[1]))
  for i in 1:length(l[1])
    get_d(el) = el[i][2];
    dat_list = map(get_d, l)
    new_d = map(f, dat_list...)
    res[i] = (l[1][i][1], new_d)
  end
  res
end
    

