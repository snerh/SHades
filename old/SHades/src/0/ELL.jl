module ELL
  import LibSerialPort as LSP
  import Base.Threads as Th

  factor = 0x40000 # pulses per turn?
  factor = 143360
  current_power = [1.]
  lk = ReentrantLock()
  
  #function wait2read(s,timeout = 2)
  #  t1 = time()
  #  while (time()-t1 < timeout)
  #    bytes = LSP.bytesavailable(s)
  #    if bytes <3
  #      sleep(0.05)
  #    else
  #      hd = LSP.read(s,3)
  #      addr = parse(Int, hd[1])
  #      comm = hd[2:3]
  #      if comm == "IN" # Information
  #        res = SP.read(s,30+2)
  #      elseif comm == "GS" # Status
  #        res = SP.read(s,2+2)
  #      elseif comm == "PO" #Position
  #        res = SP.read(s,8+2)
  #      else
  #        res = ""
  #      end
  #      SP.flush(s)
  #      println("ELL read: ",addr,comm,res)
  #      return (addr,comm,chomp(res))
  #    end
  #  end
  #  println("ELL read timeout")
  #  return(-1,"","") # exception?
  #end #wait2read

  function wait2read2(s,timeout=3)
    t1 = time()
    task_read = Th.@spawn (sleep(0.1);string(Int(round(rand()*10))))
    while (time()-t1 < timeout)
      if istaskdone(task_read)
        res = fetch(task_read)
        addr = parse(Int,res[1])
        comm = res[2:3]

        println("ELL read: ",addr,comm,res[4:end])
        return (addr,comm,res[4:end])

      else
        sleep(0.01)
      end
    end
    @warn "ELL timeout"
    println("ELL read timeout")
    return(-1,"","") # exception? 
  end

#  function write(s,add,comm)
#    println("ELL write: $add$comm")
#    SP.write(s,"$add$comm\n\r")
#  end

  function write(s,add,comm,val=nothing;pad=8)
    if val != nothing 
      s_val = uppercase(string(val,base=16,pad=pad)) # conver to hex string
    else
      s_val = ""
    end
    println("ELL write: $add$comm$s_val")
    #LSP.write(s,"$add$comm$s_val")
    #LSP.flush(s)
  end

  function resp(s,add,comm,val=nothing;pad=8)
    #LSP.sp_flush(s,LSP.SP_BUF_BOTH);
    lock(lk)
    try
      #write(s,add,comm,val)
      return wait2read2(s)
    finally
      unlock(lk)
    end
  end

  function open(com = "COM4")
    #s = LSP.open(com, 9600)
    #s
    1
  end
  function close(s)
    #LSP.close(s)
  end

  function search(s, rng=0:8)
    acc = []
    for n in rng
      a,c,r = resp(s,n,"in")
      if a > -1
        append!(acc,[(a,r)])
      end
    end
    acc
  end

  function move(s,add,comm,ang) # ang in radians
    pulses = Int64( round( ang/(2π)*factor ))
    a,c,r = resp(s,add,comm,pulses)
    if a == add
      return parse(Int64,r,base=16) # current position of status
    else
      error("ELL wrong address: $a\n")
    end
  end

  function set_offset(s,add,ang) # ang in radians
    pulses = Int64( round( ang/(2π)*factor ))
    a,c,r = resp(s,add,"so",pulses)
    if a == add
      return parse(Int64,r,base=16) # current position of status
    else
      error("ELL wrong address: $a\n")
    end
  end

  function ma(s,add,ang) # move absolute
    move(s,add,"ma",ang)
  end
  function mr(s,add,ang) # move relative
    move(s,add,"mr",ang)
  end
  function gp(s,add)
    a,c,r = resp(s,add,"gp")
    if a == -1
      error("Get position error, wrong address: $a")
    end
    ang = parse(Int64,r,base=16)/factor * 2pi
  end


end #module

