module Power

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
    resp = HTTP.get("http://$(ip)/power"; readtimeout=timeout_s)
    payload = JSON.parse(String(resp.body))
    return _extract_power(payload)
end

end
