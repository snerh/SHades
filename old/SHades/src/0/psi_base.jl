module PSI

PSI_CCD_UNIT_NSEK   = 0
PSI_CCD_UNIT_MKS    = 1
PSI_CCD_UNIT_MSEK   = 2
PSI_CCD_UNIT_SEK    = 3
PSI_CCD_UNIT_MIN    = 4
PSI_CCD_UNIT_HOURS  = 5


function init()
end

function wait2open(ip = "192.168.240.181")
end

function close(id)
end

function f()
end

function set_callbacka(f)
end

function start_scan(id, FPGA = 0, sensor = 0)
end

function get_data(id, FPGA = 0, sensor = 0, frames = 1, ROImask = 1)
    x, y = get_dims(id)
    buff = Vector{Cushort}(undef, frames * x * y)
    buff
end

function get_params(id, FPGA = 0, sensor = 0)
end

function get_temp(id, FPGA = 0,  th_element = 0)
    1
end

function set_temp(id, FPGA = 0,  th_element = 0; temp = 20)
end

function get_dims(id, FPGA = 0, sensor = 0)
    Int.(round.( (2048, 1) ))
end

function set_params(id, FPGA = 0, sensor = 0; time::Union{Nothing,Tuple{Int,String}} = nothing)
    ()
end        

end #module
