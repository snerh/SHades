module ELL
  include("Log.jl")
  import LibSerialPort as LSP

  const PULSES_PER_TURN = 143360

  mutable struct ELLHandle
    s
    lk::ReentrantLock
  end

  function wait2read2(s, timeout=1)
    LSP.set_read_timeout(s, timeout)
    try
      res = LSP.readline(s)
      addr = parse(Int, res[1])
      comm = res[2:3]

      Log.printlog("ELL read: ", addr, comm, res[4:end])
      return (addr, comm, res[4:end])
    catch e
      if isa(e, LSP.Timeout)
        @warn "ELL timeout"
        Log.printlog("ELL read timeout")
        LSP.sp_flush(s, LSP.SP_BUF_BOTH)
        return (-1, "", "0")
      end
      rethrow()
    end
  end

  function write(h::ELLHandle, add, comm, val=nothing; pad=8)
    if val != nothing
      s_val = uppercase(string(val, base=16, pad=pad))
    else
      s_val = ""
    end
    Log.printlog("ELL write:", add, comm, s_val)
    LSP.write(h.s, "$add$comm$s_val")
    LSP.flush(h.s)
  end

  function resp(h::ELLHandle, add, comm, val=nothing; pad=8)
    lock(h.lk)
    try
      write(h, add, comm, val; pad=pad)
      return wait2read2(h.s)
    catch
      @warn "Ell resp error"
      return (-1, "", "0")
    finally
      unlock(h.lk)
    end
  end

  function open(com="COM4")
    s = LSP.open(com, 9600)
    try
      LSP.sp_flush(s, LSP.SP_BUF_BOTH)
      LSP.set_read_timeout(s, 1)
      return ELLHandle(s, ReentrantLock())
    catch
      LSP.close(s)
      rethrow()
    end
  end

  function close(h::ELLHandle)
    LSP.close(h.s)
    return nothing
  end

  function search(h::ELLHandle, rng=0:8)
    acc = []
    for n in rng
      a, c, r = resp(h, n, "in")
      if a > -1
        push!(acc, (a, r))
      end
    end
    return acc
  end

  function move(h::ELLHandle, add, comm, ang) # ang in radians
    pulses = Int64(round(ang / (2 * pi) * PULSES_PER_TURN))
    a, c, r = resp(h, add, comm, pulses)
    if a == add
      return parse(Int64, r, base=16)
    else
      error("ELL wrong address: $a\n")
    end
  end

  function set_offset(h::ELLHandle, add, ang) # ang in radians
    pulses = Int64(round(ang / (2 * pi) * PULSES_PER_TURN))
    a, c, r = resp(h, add, "so", pulses)
    if a == add
      return parse(Int64, r, base=16)
    else
      error("ELL wrong address: $a\n")
    end
  end

  ma(h::ELLHandle, add, ang) = move(h, add, "ma", ang)
  mr(h::ELLHandle, add, ang) = move(h, add, "mr", ang)
  home(h::ELLHandle, add) = resp(h, add, "ho", 0, pad=1)

  function gp(h::ELLHandle, add)
    a, c, r = resp(h, add, "gp")
    if a == -1
      error("Get position error, wrong address: $a")
    end
    ang = parse(Int64, r, base=16) / PULSES_PER_TURN * (2 * pi)
    return ang
  end

end #module
