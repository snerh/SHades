module Orpheus
  include("Log.jl")
  import HTTP
  import JSON
  ip = "127.0.0.1"
  port = "8000"
  id = "Orpheus-F-Demo-0654"

  function init(;test = true)
    if !(test)
      global ip = "172.16.11.11"
      global port = "8012"
      global id = "P21607"
    end
  end

  function put(url,body)
    resp = HTTP.put("http://$ip:$port/$id/v0/PublicAPI$url",["Content-Type" => "application/json"],body)
    s = String(resp.body)
    s
  end
  function get(url)
    Log.printlog("http://", ip,":",port,"/",id,"/v0/PublicAPI",url)
    resp = HTTP.get("http://$ip:$port/$id/v0/PublicAPI$url")
    s = String(resp.body)
    s
  end
  function setWL(wl,interaction = "SIG")
    body = JSON.json(Dict(["Wavelength" => wl, "Interaction" => interaction]))
    str = put("/Optical/WavelengthControl/SetWavelength", body)
    dict = JSON.parse(str)
    if dict["IsSuccess"] != true 
        error("SetWavelength error")
    end
    ()
  end
  function getWL()
    resp = get("/Optical/WavelengthControl/Output/Wavelength")
    wl = parse(Float64, resp)
    wl
  end
end

