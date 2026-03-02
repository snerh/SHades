module Power
    using HTTP
    using JSON
ip = "192.168.1.52"
function get()
    resp = HTTP.get("http://"*ip*"/power")
    pow = String(resp.body)
    #print(resp)
    JSON.parse(pow)
end
end