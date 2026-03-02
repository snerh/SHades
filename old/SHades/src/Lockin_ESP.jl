module Lockin
  include("Log.jl")
  import LibSerialPort as LSP
  include("readl.jl")
  lk = ReentrantLock() # lock read-write sequence

function open(port = "COM6")
  s = LSP.open(port, 115200)
  LSP.sp_flush(s,LSP.SP_BUF_BOTH)
  s
end

function init(s)
  #write(s, "setZero\n")
  #wait2read(s)
  #LSP.sp_flush(s,LSP.SP_BUF_BOTH)
end


function wait2read(s,timeout = 2)
  LSP.set_read_timeout(s,timeout)
    try
	  res = LSP.readline(s)
        #Log.printlog("res = ",res)
      return res
    catch e
	  if isa(e, LSP.Timeout)
		@warn "Lockin timeout"
		Log.printlog("Lockin read timeout")
		LSP.sp_flush(s, LSP.SP_BUF_BOTH)
		rethrow()
      end
    end 
end

function get(s, ch = 3) # 1, 2, 3, 4 - X, Y, R, PHI
  lock(lk)    
  try
    ##LSP.sp_flush(s,LSP.SP_BUF_BOTH)
    write(s,"get\n")
    resp = wait2read(s)
    num_str = match(r"[-0-9.]+\t[-0-9.]+\t([-0-9.]+)",resp)[1]
    resp = parse(Float64,num_str)
    return resp
  catch
    @warn "Lockin get error"
	return nothing
  finally  
    unlock(lk)
  end
end

function close(s)
    LSP.close(s)
end

end #module
