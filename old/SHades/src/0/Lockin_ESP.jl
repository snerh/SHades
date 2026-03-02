module Lockin
  import LibSerialPort as LSP
  include("readl.jl")
  lk = ReentrantLock() # lock read-write sequence

function open(port = "COM7")
  #s = LSP.open(port, 9600)
  #LSP.sp_flush(s,LSP.SP_BUF_BOTH)
  
  1
end

function init(s)
  #write(s, "OUTX 0\n")
  #wait2read(s)
  #LSP.sp_flush(s,LSP.SP_BUF_BOTH)
end


function wait2read(s,timeout = 2)
  t1 = time()
  task_read = Threads.@spawn (sleep(0.1); rand()*100)
  while (time()-t1 < timeout)
    if istaskdone(task_read)
        res = fetch(task_read)
        #println("res = $res")
      return res
    else
      sleep(0.01)
    end
  end
  @warn "Lockin timeout"
  0
end

function get(s, ch = 3) # 1, 2, 3, 4 - X, Y, R, PHI
  lock(lk)    
  try
    ##LSP.sp_flush(s,LSP.SP_BUF_BOTH)
    #write(s,"OUTP? $ch\n")
    resp = wait2read(s)
    return resp
  catch
    @warn "Lockin error. resp"
  finally  
    unlock(lk)
  end
end

function close(s)
   # LSP.close(s)
end

end #module
