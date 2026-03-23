module RawDevices

using ..DeviceManager
using Statistics
import JSON

const RAW_DIR = @__DIR__
const DEFAULT_ELL_PRESET = joinpath(RAW_DIR, "ELL_preset.json")
const DEFAULT_SOL_CONF_DIR = RAW_DIR

include(joinpath(RAW_DIR, "Lockin_ESP.jl"))
include(joinpath(RAW_DIR, "ELL.jl"))
include(joinpath(RAW_DIR, "Orpheus.jl"))
include(joinpath(RAW_DIR, "psi_base.jl"))
include(joinpath(RAW_DIR, "Sol.jl"))

export build_real_devices
export LockinDevice, EllDevice, LaserDevice, SpectrometerDevice, CameraDevice

struct ELLPreset
    power_addr::Int
    polarizer_addr::Int
    analyzer_addr::Int
    power_home_deg::Float64
    polarizer_home_deg::Float64
    analyzer_home_deg::Float64
    half_wave::Bool
end

mutable struct CameraState
    acq_time_s::Float64
    frames::Int
    temp_c::Union{Nothing,Float64}
    scan_timeout_s::Float64
end


mutable struct LockinState
    target_power::Float64
end

mutable struct LaserState
    wl::Float64
    interaction::String
end

mutable struct SpecState
    wl::Union{Nothing,Float64}
    slit::Union{Nothing,Float64}
    shutter::Union{Nothing,Bool}
end

_default_ell_preset() = ELLPreset(1, 0, 2, 33.6, 129.8, 10.0, true)

function _bool_from_any(x, default::Bool)
    x === nothing && return default
    x isa Bool && return x
    x isa Number && return x != 0
    if x isa AbstractString
        v = lowercase(strip(x))
        return v in ("true", "1", "yes", "y")
    end
    return default
end

function load_ell_preset(path::AbstractString=DEFAULT_ELL_PRESET)
    if !isfile(path)
        return _default_ell_preset()
    end

    data = JSON.parsefile(path)
    ell = get(data, "ell", data)

    function _axis(key, def_addr, def_home)
        d = get(ell, key, Dict{String,Any}())
        addr = Int(get(d, "address", def_addr))
        home = Float64(get(d, "home", def_home))
        return addr, home
    end

    paddr, phome = _axis("power", 1, 33.6)
    poladdr, polhome = _axis("polarizer", 0, 129.8)
    aaddr, ahome = _axis("analyzer", 2, 10.0)
    half_wave = _bool_from_any(get(ell, "half_wave", true), true)

    return ELLPreset(paddr, poladdr, aaddr, phome, polhome, ahome, half_wave)
end

function _deg_to_ell_rad(deg::Float64, half_wave::Bool)
    ang = deg2rad(deg)
    return half_wave ? ang / 2.0 : ang
end

function _ell_rad_to_deg(rad::Float64, half_wave::Bool)
    ang = rad2deg(rad)
    return half_wave ? ang * 2.0 : ang
end

function _sec_to_psi_time(t_s::Float64)
    if t_s < 1.0
        ms = Int(max(1, round(t_s * 1000)))
        return (ms, "ms")
    end
    return (Int(round(t_s)), "s")
end

function _unmuon(d; factor=2)
    frames = length(d)
    px = length(d[1])
    res = Vector{Float64}(undef, px)
    for i in 1:px
        l = map(fr -> fr[i], d)
        s = sort(l)
        function aux(s)
            acc = s[1]
            sigm = sqrt(abs(s[1]))
            for j in 1:frames
                if s[j] > acc + sigm * factor + 30
                    return acc
                else
                    acc = mean(s[1:j])
                    sigm = j == 1 ? sigm : std(s[1:j])
                end
            end
            return acc
        end
        res[i] = aux(s)
    end
    return res
end

function _make_device(
    connect_device::Function,
    init_device::Function,
    set_param::Function,
    read_signal::Function,
    abort_device::Function,
    close_device::Function;
    timeout_s::Float64=5.0,
    cmd_size::Int=32,
    event_size::Int=32,
)
    RawDevice(
        connect_device,
        init_device,
        set_param,
        read_signal,
        abort_device,
        close_device,
        timeout_s,
        Channel{DeviceCommand}(cmd_size),
        Channel{SystemEvent}(event_size),
    )
end

function LockinDevice(; port::AbstractString="COM6", timeout_s::Float64=2.0)
    state = LockinState(0.0001)
    connect_device = () -> Lockin.open(port)
    init_device = dev -> (Lockin.init(dev); :ok)
    set_param = (dev, name, value) -> begin
        if name == :target_power
            state.target_power = value
        end
    end
    read_signal = (dev, name) -> begin
        if name == :target_power
            return state.target_power
        elseif name == :power
            val = Lockin.get(dev)
            return val === nothing ? NaN : Float64(val)
        end
        return nothing
    end
    abort_device = dev -> nothing
    close_device = dev -> (Lockin.close(dev); nothing)

    return _make_device(connect_device, init_device, set_param, read_signal, abort_device, close_device; timeout_s=timeout_s)
end

function LaserDevice(
    ;
    test::Bool=true,
    ip::AbstractString="",
    port::AbstractString="",
    id::AbstractString="",
    default_wl::Float64=550.0,
    default_interaction::AbstractString="SIG",
    timeout_s::Float64=2.0,
)
    state = LaserState(default_wl, String(default_interaction))

    connect_device = () -> Orpheus.client(; test=test, ip=ip, port=port, id=id)
    init_device = dev -> :ok
    set_param = (dev, name, value) -> begin
        if name == :wl
            state.wl = Float64(value)
            Orpheus.setWL(dev, state.wl, state.interaction)
        elseif name == :interaction
            state.interaction = String(value)
        end
        return :ok
    end
    read_signal = (dev, name) -> begin
        if name == :wl
            return Orpheus.getWL(dev)
        elseif name == :interaction
            return state.interaction
        end
        return nothing
    end
    abort_device = dev -> nothing
    close_device = dev -> nothing

    return _make_device(connect_device, init_device, set_param, read_signal, abort_device, close_device; timeout_s=timeout_s)
end

function SpectrometerDevice(; port::AbstractString="COM5", conf_dir::AbstractString=DEFAULT_SOL_CONF_DIR, timeout_s::Float64=2.0)
    state = SpecState(nothing, nothing, nothing)

    connect_device = () -> Sol.open(port; conf_dir=conf_dir)
    init_device = dev -> :ok
    set_param = (dev, name, value) -> begin
        if name == :wl
            v = Float64(value)
            state.wl = v
            Sol.set_wl(dev, v)
        elseif name == :slit
            v = Float64(value)
            state.slit = v
            Sol.set_slit(dev, v)
        elseif name == :shutter
            is_open = Bool(value)
            state.shutter = is_open
            Sol.set_shutter(dev, is_open ? 1 : 0)
        end
        return :ok
    end
    read_signal = (dev, name) -> begin
        if name == :wl
            return Sol.get_wl(dev)
        elseif name == :slit
            return Sol.get_slit(dev)
        elseif name == :shutter
            return state.shutter
        end
        return nothing
    end
    abort_device = dev -> nothing
    close_device = dev -> (Sol.close(dev); nothing)

    return _make_device(connect_device, init_device, set_param, read_signal, abort_device, close_device; timeout_s=timeout_s)
end

function EllDevice(; port::AbstractString="COM4", preset_path::AbstractString=DEFAULT_ELL_PRESET, timeout_s::Float64=2.0)
    preset = load_ell_preset(preset_path)

    function _apply_home(dev, addr::Int, home_deg::Float64)
        ELL.set_offset(dev, addr, deg2rad(home_deg))
        ELL.home(dev, addr)
        return nothing
    end

    connect_device = () -> ELL.open(port)
    init_device = dev -> begin
        _apply_home(dev, preset.power_addr, preset.power_home_deg)
        _apply_home(dev, preset.polarizer_addr, preset.polarizer_home_deg)
        _apply_home(dev, preset.analyzer_addr, preset.analyzer_home_deg)
        return :ok
    end
    set_param = (dev, name, value) -> begin
        if name == :polarizer
            ang = _deg_to_ell_rad(Float64(value), preset.half_wave)
            ELL.ma(dev, preset.polarizer_addr, ang)
        elseif name == :analyzer
            ang = _deg_to_ell_rad(Float64(value), preset.half_wave)
            ELL.ma(dev, preset.analyzer_addr, ang)
        elseif name == :ang_power
            ELL.ma(dev, preset.power_addr, Float64(value))
        end
        return :ok
    end
    read_signal = (dev, name) -> begin
        if name == :ang_power
            return ELL.gp(dev, preset.power_addr)
        elseif name == :polarizer
            ang = ELL.gp(dev, preset.polarizer_addr)
            return _ell_rad_to_deg(ang, preset.half_wave)
        elseif name == :analyzer
            ang = ELL.gp(dev, preset.analyzer_addr)
            return _ell_rad_to_deg(ang, preset.half_wave)
        end
        return nothing
    end
    abort_device = dev -> nothing
    close_device = dev -> (ELL.close(dev); nothing)

    return _make_device(connect_device, init_device, set_param, read_signal, abort_device, close_device; timeout_s=timeout_s)
end

function CameraDevice(
    ;
    ip::AbstractString="192.168.240.181",
    timeout_s::Float64=30.0,
    psi_libpath::AbstractString=PSI.DEFAULT_LIBPATH,
    scan_timeout_s::Float64=timeout_s,
    acq_time_s::Float64=0.1,
    frames::Int=1,
    temp_c::Union{Nothing,Float64}=nothing,
)
    state = CameraState(acq_time_s, max(frames, 1), temp_c, scan_timeout_s)
    ctx = PSI.PSIContext(; libpath=psi_libpath)

    connect_device = () -> begin
        ok = PSI.init(ctx)
        ok || error("PSI init failed")
        return PSI.wait2open(ctx, ip)
    end
    init_device = dev -> begin
        PSI.set_params(dev, time=_sec_to_psi_time(state.acq_time_s))
        if state.temp_c !== nothing
            PSI.set_temp(dev; temp=Int(round(state.temp_c)))
        end
        return :ok
    end
    set_param = (dev, name, value) -> begin
        if name == :acq_time
            state.acq_time_s = Float64(value)
            PSI.set_params(dev, time=_sec_to_psi_time(state.acq_time_s))
        elseif name == :frames
            state.frames = max(Int(round(Float64(value))), 1)
        elseif name == :temp
            state.temp_c = Float64(value)
            PSI.set_temp(dev; temp=Int(round(state.temp_c)))
        end
        return :ok
    end
    read_signal = (dev, name) -> begin
        if name == :spectrum
            frames = max(state.frames, 1)
            status, param = PSI.wait_scan_complete(dev; timeout_s=state.scan_timeout_s, do_start=true)
            if status == :timeout
                try
                    PSI.abort_scan(dev)
                catch
                end
                error("PSI scan timeout")
            elseif status == :error
                error("PSI scan error: code $(param)")
            end

            raw = Float64.(PSI.get_data(dev, frames=frames))
            px = length(raw) ÷ frames
            if px * frames != length(raw)
                error("PSI data size mismatch: frames=$(frames), len=$(length(raw))")
            end
            frames_data = [raw[(i - 1) * px + 1:i * px] for i in 1:frames]
            return _unmuon(frames_data)
        elseif name == :temp
            return PSI.get_temp(dev)
        end
        return nothing
    end
    abort_device = dev -> begin
        try
            PSI.abort_scan(dev)
        catch
        end
        return nothing
    end
    close_device = dev -> (PSI.close(dev); nothing)

    return _make_device(connect_device, init_device, set_param, read_signal, abort_device, close_device; timeout_s=timeout_s)
end

function build_real_devices(
    ;
    ell_port::AbstractString="COM4",
    ell_preset_path::AbstractString=DEFAULT_ELL_PRESET,
    lockin_port::AbstractString="COM6",
    sol_port::AbstractString="COM5",
    sol_conf_dir::AbstractString=DEFAULT_SOL_CONF_DIR,
    psi_ip::AbstractString="192.168.240.181",
    psi_libpath::AbstractString=PSI.DEFAULT_LIBPATH,
    orpheus_test::Bool=false,
    orpheus_ip::AbstractString="",
    orpheus_port::AbstractString="",
    orpheus_id::AbstractString="",
)
    laser = LaserDevice(; test=orpheus_test, ip=orpheus_ip, port=orpheus_port, id=orpheus_id)
    spec = SpectrometerDevice(; port=sol_port, conf_dir=sol_conf_dir)
    ell = EllDevice(; port=ell_port, preset_path=ell_preset_path)
    cam = CameraDevice(; ip=psi_ip, psi_libpath=psi_libpath)
    pd = LockinDevice(; port=lockin_port)

    devices = RawDevice[laser, spec, ell, cam, pd]
    hub = DeviceHub(Dict(
        :laser => laser.device_cmd,
        :spec => spec.device_cmd,
        :ell => ell.device_cmd,
        :cam => cam.device_cmd,
        :pd => pd.device_cmd,
    ))

    return (devices=devices, hub=hub)
end

end
