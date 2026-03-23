module PSI
include("Log.jl")
import Libdl

const PSI_CCD_UNIT_NSEK   = 0
const PSI_CCD_UNIT_MKS    = 1
const PSI_CCD_UNIT_MSEK   = 2
const PSI_CCD_UNIT_SEK    = 3
const PSI_CCD_UNIT_MIN    = 4
const PSI_CCD_UNIT_HOURS  = 5

const PSI_CMD_ACK_ERROR = 5
const PSI_CMD_SCAN_START = 301

const DEFAULT_LIBPATH = "C:\\work\\soft\\SHades\\psi_ccd5.dll"

struct PSIContext
    libpath::String
    handle::Ptr{Cvoid}
end
PSIContext(; libpath::AbstractString=DEFAULT_LIBPATH) = PSIContext(String(libpath), Libdl.dlopen(libpath))

struct PSIDevice
    ctx::PSIContext
    id::Int32
end

const _cb_lock = ReentrantLock()
const _cb_channels = Dict{Int32,Channel{Tuple{Int32,Int32}}}()
const _cb_installed = Ref(false)
const _cb_ptr = Ref{Ptr{Cvoid}}(C_NULL)

_sym(ctx::PSIContext, name::Symbol) = Libdl.dlsym(ctx.handle, name)

function _device_callback(iDevNum::Cint, lEvent::Cint, lParam1::Cint, lParam2::Cint)::Cint
    ch = nothing
    lock(_cb_lock)
    ch = get(_cb_channels, Int32(iDevNum), nothing)
    unlock(_cb_lock)

    if ch !== nothing && isopen(ch)
        if !isready(ch)
            try
                put!(ch, (Int32(lEvent), Int32(lParam1)))
            catch
            end
        end
    end
    return 0
end

function _ensure_callback!(ctx::PSIContext)
    if _cb_installed[]
        return nothing
    end
    _cb_ptr[] = @cfunction(_device_callback, Cint, (Cint, Cint, Cint, Cint))
    err = ccall(_sym(ctx, :psiccd3_SetCallback), Cint, (Ptr{Cvoid},), _cb_ptr[])
    err == 0 || error("psiccd3_SetCallback error: $err")
    _cb_installed[] = true
    return nothing
end

function register_scan_channel!(dev::PSIDevice, ch::Channel{Tuple{Int32,Int32}})
    _ensure_callback!(dev.ctx)
    lock(_cb_lock)
    _cb_channels[Int32(dev.id)] = ch
    unlock(_cb_lock)
    return nothing
end

function unregister_scan_channel!(dev::PSIDevice)
    lock(_cb_lock)
    pop!(_cb_channels, Int32(dev.id), nothing)
    unlock(_cb_lock)
    return nothing
end

function wait_scan_complete(dev::PSIDevice; timeout_s::Float64=5.0, do_start::Bool=false, FPGA::Integer=0, sensor::Integer=0)
    ch = Channel{Tuple{Int32,Int32}}(1)
    register_scan_channel!(dev, ch)
    try
        if do_start
            start_scan(dev, FPGA, sensor)
        end
        t0 = time()
        while true
            if isready(ch)
                ev, param = take!(ch)
                if ev == PSI_CMD_ACK_ERROR
                    return (:error, Int(param))
                elseif ev == PSI_CMD_SCAN_START
                    return (:ok, Int(param))
                end
            elseif (time() - t0) > timeout_s
                return (:timeout, 0)
            else
                sleep(0.01)
            end
        end
    finally
        unregister_scan_channel!(dev)
    end
end

function init(ctx::PSIContext)
    Log.printlog("psi file = ", ctx.libpath)
    err = ccall(_sym(ctx, :psiccd3_Init), Cuchar, ())
    return err == 0
end

function wait2open(ctx::PSIContext, ip::AbstractString="192.168.240.181")
    cam_id = Ref{Cint}(0)
    err = ccall(_sym(ctx, :psiccd3_Wait2OpenDevice), Cint, (Cstring, Ref{Cint}), ip, cam_id)
    err == 0 ? PSIDevice(ctx, Int32(cam_id[])) : error("psiccd3_Wait2OpenDevice error")
end

function close(dev::PSIDevice)
    err = ccall(_sym(dev.ctx, :psiccd3_CloseDevice), Cint, (Cint,), dev.id)
    err == 0 ? dev : error("psiccd3_CloseDevice error")
end

function start_scan(dev::PSIDevice, FPGA::Integer=0, sensor::Integer=0)
    err = ccall(_sym(dev.ctx, :psiccd3_StartScan), Cint, (Cint, Cushort, Cushort), dev.id, FPGA, sensor)
    err == 0 ? nothing : error("psiccd3_StartScan error")
end

function stop_scan(dev::PSIDevice, FPGA::Integer=0, sensor::Integer=0)
    err = ccall(_sym(dev.ctx, :psiccd3_StopScan), Cint, (Cint, Cushort, Cushort), dev.id, FPGA, sensor)
    err == 0 ? nothing : error("psiccd3_StopScan error")
end

function abort_scan(dev::PSIDevice, FPGA::Integer=0, sensor::Integer=0)
    err = ccall(_sym(dev.ctx, :psiccd3_AbortScan), Cint, (Cint, Cushort, Cushort), dev.id, FPGA, sensor)
    err == 0 ? nothing : error("psiccd3_AbortScan error")
end

function get_data(dev::PSIDevice, FPGA::Integer=0, sensor::Integer=0, frames::Integer=1, ROImask::Integer=1)
    x, y = get_dims(dev, FPGA, sensor)
    buff = Vector{Cushort}(undef, frames * x * y)
    pref = Ref{Ptr{Cushort}}(pointer(buff))
    err = ccall(
        _sym(dev.ctx, :psiccd3_GetData),
        Cint,
        (Cint, Cushort, Cushort, Cushort, Cushort, Ref{Ptr{Cushort}}),
        dev.id,
        FPGA,
        sensor,
        frames,
        ROImask,
        pref,
    )
    if err == 0
        return buff
    end
    error("pscccd3_GetData error")
end

function get_params(dev::PSIDevice, FPGA::Integer=0, sensor::Integer=0)
    size = 32 + 18 * 8 + 24 + (48 + 32)
    buf = Vector{Cushort}(undef, Int(size / 2))
    err = ccall(
        _sym(dev.ctx, :psiccd3_GetSensorParams),
        Cint,
        (Cint, Cushort, Cushort, Ref{Cushort}),
        dev.id,
        FPGA,
        sensor,
        buf,
    )
    err == 0 ? buf : error("psiccd3_GetSensorParams error")
end

function get_temp(dev::PSIDevice, FPGA::Integer=0, th_element::Integer=0)
    ref = Ref(Cint(-100))
    err = ccall(
        _sym(dev.ctx, :psiccd3_GetThermoelementParams),
        Cint,
        (Cint, Cushort, Cushort, Ref{Cint}),
        dev.id,
        FPGA,
        th_element,
        ref,
    )
    err == 0 ? ref[] : error("psiccd3_GetThermoelementParams error")
end

function set_temp(dev::PSIDevice, FPGA::Integer=0, th_element::Integer=0; temp::Integer=20)
    err = ccall(
        _sym(dev.ctx, :psiccd3_SetThermoelementParams),
        Cint,
        (Cint, Cushort, Cushort, Ref{Cint}),
        dev.id,
        FPGA,
        th_element,
        Ref(Cint(temp)),
    )
    err == 0 ? nothing : error("psiccd3_SetThermoelementParams error")
end

function get_dims(dev::PSIDevice, FPGA::Integer=0, sensor::Integer=0)
    buf = get_params(dev, FPGA, sensor)
    roi_w = buf[20] - buf[18] + 1
    roi_h = buf[21] - buf[19] + 1
    bin_w = buf[24]
    bin_h = buf[23]
    Int.(round.((roi_w / bin_w, roi_h / bin_h)))
end

function set_params(dev::PSIDevice, FPGA::Integer=0, sensor::Integer=0; time::Union{Nothing,Tuple{Int,String}}=nothing, frames::Int=1)
    buf = get_params(dev, FPGA, sensor)
    if time !== nothing
        x, unit = time
        Log.printlog(time)
        buf[95] = x
        if unit == "ns"
            buf[94] = 0
        elseif unit == "mks"
            buf[94] = 1
        elseif unit == "ms"
            buf[94] = 2
        elseif unit == "s"
            buf[94] = 3
        elseif unit == "min"
            buf[94] = 4
        elseif unit == "h"
            buf[94] = 5
        else
            error("set_params error: unknown time unit")
        end
    end
    # overwrite ROI to spectrum 2048x1
    spectrum_roi::Vector{Cushort} = [0, 0, 2047, 121, 0, 122, 1, 4096, 0]
    p = view(buf, 18:26)
    copy!(p, spectrum_roi)

    # overwrite frame count
    frames_buf::Vector{Cushort} = [UInt16(frames),0]
    frame_start = (32 + 18*8)/2
    p2 = view(buf, frame_start:frame_start+1)
    copy!(p2, frames_buf)

    err = ccall(
        _sym(dev.ctx, :psiccd3_SetSensorParams),
        Cint,
        (Cint, Cushort, Cushort, Ref{Cushort}),
        dev.id,
        FPGA,
        sensor,
        buf,
    )
    err == 0 ? buf : error("psiccd3_SetSensorParams error :$err")
    return nothing
end

end #module
