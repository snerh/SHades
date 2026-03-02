module PSI
include("Log.jl")

PSI_CCD_UNIT_NSEK   = 0
PSI_CCD_UNIT_MKS    = 1
PSI_CCD_UNIT_MSEK   = 2
PSI_CCD_UNIT_SEK    = 3
PSI_CCD_UNIT_MIN    = 4
PSI_CCD_UNIT_HOURS  = 5

psi = "C:\\work\\soft\\SHades\\psi_ccd5.dll"

function init()
	Log.printlog("psi file = ", psi)
    err = @ccall psi.psiccd3_Init()::Cuchar
    err == 0
end

function wait2open(ip = "192.168.240.181")
    cam_id = Ref{Cint}(0)
    err = @ccall psi.psiccd3_Wait2OpenDevice(ip::Cstring,cam_id::Ref{Cint})::Cint
    err == 0 ? cam_id.x : error("psiccd3_Wait2OpenDevice error")
end

function close(id)
    err = @ccall psi.psiccd3_CloseDevice(id::Cint)::Cint
    err == 0 ? id : error("psiccd3_CloseDevice error")
end

function f()
end

function set_callbacka(f)
    fptr = @cfunction(f,Cint,(Cint,Cint,Cint,Cint))
    err = @ccall psi.psiccd3_SetCallback(fptr::Ptr{Cvoid})::Cint
    err == 0 ? () : error("psiccd3_SetCallback error")
end

function start_scan(id, FPGA = 0, sensor = 0)
    err = @ccall psi.psiccd3_StartScan(id::Cint, FPGA::Cushort, sensor::Cushort)::Cint
    err == 0 ? () : error("psiccd3_StartScan error")
end

function get_data(id, FPGA = 0, sensor = 0, frames = 1, ROImask = 1)
    x, y = get_dims(id)
    buff = Vector{Cushort}(undef, frames * x * y)
    p = pointer(buff)
    #Log.printlog(p)
    #Log.printlog(buff[1:10])
    err = @ccall psi.psiccd3_GetData(id::Cint, FPGA::Cushort, sensor::Cushort, frames::Cushort, ROImask::Cushort,Ref(p)::Ref{Ptr{Cushort}})::Cint
    if err == 0
        #Log.printlog(buff[1:10])
        buff
    else
        error("pscccd3_GetData error")
    end
end

function get_params(id, FPGA = 0, sensor = 0)
    size = 32 + 18*8 + 24 + (48+32)
    buf = Vector{Cushort}(undef, Int(size/2))
    err = @ccall psi.psiccd3_GetSensorParams(id::Cint, FPGA::Cushort, sensor::Cushort, buf::Ref{Cushort})::Cint
    err == 0 ? buf : error("psiccd3_GetSensorParams error")
end

function get_temp(id, FPGA = 0,  th_element = 0)
    ref = Ref(Cint(-100))
    err = @ccall psi.psiccd3_GetThermoelementParams(id::Cint, FPGA::Cushort, th_element::Cushort, ref::Ref{Cint})::Cint
    err == 0 ? ref.x : error("psiccd3_GetThermoelementParams error")
end

function set_temp(id, FPGA = 0,  th_element = 0; temp = 20)
    err = @ccall psi.psiccd3_SetThermoelementParams(id::Cint, FPGA::Cushort, th_element::Cushort, Ref(Cint(temp))::Ref{Cint})::Cint
    err == 0 ? () : error("psiccd3_SetThermoelementParams error")
end

function get_dims(id, FPGA = 0, sensor = 0)
    buf = get_params(id, FPGA, sensor)
    roi_w = buf[20]-buf[18]+1
    roi_h = buf[21]-buf[19]+1
    bin_w = buf[24]
    bin_h = buf[23]
    (2048,1) # заглушка
    Int.(round.( (roi_w/bin_w, roi_h/bin_h) ))
end

function set_params(id, FPGA = 0, sensor = 0; time::Union{Nothing,Tuple{Int,String}} = nothing)
    buf = get_params(id, FPGA, sensor)
    if time != nothing
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
    # overwrite POI to spectrum 2048x1
    spectrum_roi::Vector{Cushort} = [0,0,2047,121,0,122,1,4096,0]
    p = view(buf,18:26)
    copy!(p, spectrum_roi)

    err = @ccall psi.psiccd3_SetSensorParams(id::Cint, FPGA::Cushort, sensor::Cushort, buf::Ref{Cushort})::Cint
    err == 0 ? buf : error("psiccd3_SetSensorParams error :$err")
    ()
end        

end #module
