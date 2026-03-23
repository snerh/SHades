module Lockin
  include("Log.jl")
  import LibSerialPort as LSP
  include("readl.jl")

  mutable struct LockinHandle
    s
    lk::ReentrantLock
  end

  function open(port = "COM6")
    s = LSP.open(port, 115200)
    LSP.sp_flush(s, LSP.SP_BUF_BOTH)
    return LockinHandle(s, ReentrantLock())
  end

  function init(h::LockinHandle)
    #write(h.s, "setZero\n")
    #wait2read(h.s)
    #LSP.sp_flush(h.s, LSP.SP_BUF_BOTH)
    return nothing
  end

  function wait2read(s, timeout = 2)
    LSP.set_read_timeout(s, timeout)
    try
      res = LSP.readline(s)
      return res
    catch e
      if isa(e, LSP.Timeout)
        @warn "Lockin timeout"
        Log.printlog("Lockin read timeout")
        LSP.sp_flush(s, LSP.SP_BUF_BOTH)
        rethrow()
      end
      rethrow()
    end 
  end

  function get(h::LockinHandle, ch = 3) # 1, 2, 3, 4 - X, Y, R, PHI
    lock(h.lk)
    try
      write(h.s, "get\n")
      resp = wait2read(h.s)
      num_str = match(r"[-0-9.]+\t[-0-9.]+\t([-0-9.]+)", resp)[1]
      return parse(Float64, num_str)
    catch
      @warn "Lockin get error"
      return nothing
    finally
      unlock(h.lk)
    end
  end

  function close(h::LockinHandle)
    LSP.close(h.s)
    return nothing
  end

end #module
