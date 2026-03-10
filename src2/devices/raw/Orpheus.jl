module Orpheus
  include("Log.jl")
  import HTTP
  import JSON

  struct OrpheusClient
    ip::String
    port::String
    id::String
  end

  const DEFAULT_TEST = OrpheusClient("127.0.0.1", "8000", "Orpheus-F-Demo-0654")
  const DEFAULT_REAL = OrpheusClient("172.16.11.11", "8012", "P21607")

  function client(; test::Bool=true, ip::AbstractString="", port::AbstractString="", id::AbstractString="")
    base = test ? DEFAULT_TEST : DEFAULT_REAL
    return OrpheusClient(
      isempty(ip) ? base.ip : String(ip),
      isempty(port) ? base.port : String(port),
      isempty(id) ? base.id : String(id),
    )
  end

  function _url(c::OrpheusClient, path::AbstractString)
    return "http://$(c.ip):$(c.port)/$(c.id)/v0/PublicAPI$path"
  end

  function put(c::OrpheusClient, url::AbstractString, body)
    resp = HTTP.put(_url(c, url), ["Content-Type" => "application/json"], body)
    return String(resp.body)
  end

  function get(c::OrpheusClient, url::AbstractString)
    Log.printlog(_url(c, url))
    resp = HTTP.get(_url(c, url))
    return String(resp.body)
  end

  function setWL(c::OrpheusClient, wl, interaction::AbstractString="SIG")
    body = JSON.json(Dict(["Wavelength" => wl, "Interaction" => interaction]))
    str = put(c, "/Optical/WavelengthControl/SetWavelength", body)
    dict = JSON.parse(str)
    if dict["IsSuccess"] != true
      error("SetWavelength error")
    end
    return nothing
  end

  function getWL(c::OrpheusClient)
    resp = get(c, "/Optical/WavelengthControl/Output/Wavelength")
    return parse(Float64, resp)
  end
end
