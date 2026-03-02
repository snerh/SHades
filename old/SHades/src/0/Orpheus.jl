module Orpheus
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
  end
  function get(url)
  end
  function setWL(wl,interaction = "SIG")
    ()
  end
  function getWL()
    123
  end
end

