module Power

include("Log.jl")
using HTTP
using JSON

const DEFAULT_IP = get(ENV, "SHADES_POWER_WEB_IP", "192.168.1.52")

function _extract_power(payload)
    payload isa Number && return Float64(payload)
    if payload isa AbstractDict
        for key in ("power", "value", "p", "result")
            if haskey(payload, key) && payload[key] isa Number
                return Float64(payload[key])
            end
        end
    end
    error("Unsupported Power_web response: $(repr(payload))")
end

function get(; ip::AbstractString=DEFAULT_IP, timeout_s::Real=2)
    url = "http://$(ip)/power"
    Log.printlog("Power_web GET ", url, " timeout_s=", timeout_s)
    resp = HTTP.get(url; readtimeout=timeout_s)
    body = String(resp.body)
    Log.printlog("Power_web response status=", resp.status, " body=", body)
    payload = JSON.parse(body)
    power = _extract_power(payload)
    Log.printlog("Power_web parsed power=", power)
    return power
end

end
