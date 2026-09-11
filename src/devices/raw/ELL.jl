module ELL
  include("Log.jl")
  import LibSerialPort as LSP

  const PULSES_PER_TURN = 143360

  mutable struct ELLHandle
    s
    lk::ReentrantLock
  end
  
  function toInt64(str)
    return Int64(reinterpret(Int32,parse(UInt32, str, base=16)))
  end

  _expected_response(comm) = comm in ("gp", "ma", "mr", "ho") ? "PO" : comm in ("so", "gs") ? "GS" : nothing

  function _set_read_timeout_seconds(s, seconds::Real)
    # LibSerialPort stores the timeout in UInt32 milliseconds, so passing
    # fractional seconds can raise InexactError during conversion.
    LSP.set_read_timeout(s, max(1, ceil(Int, seconds)))
  end

  function wait2read2(s, timeout=15; expected_addr=nothing, expected_comm=nothing)
    deadline = time() + timeout

    while time() < deadline
      try
        _set_read_timeout_seconds(s, deadline - time())
        res = strip(LSP.readline(s))
        length(res) >= 3 || continue
        addr = parse(Int, string(res[1]))
        comm = res[2:3]
        payload = length(res) >= 4 ? res[4:end] : ""

        if (expected_addr === nothing || addr == expected_addr) &&
           (expected_comm === nothing || comm == expected_comm)
          Log.printlog("ELL read: ", addr, comm, payload)
          return (addr, comm, payload)
        end

        Log.printlog("ELL stale read: ", addr, comm, payload, " expected=", expected_addr, expected_comm)
      catch e
        if isa(e, LSP.Timeout)
          break
        end
        Log.printlog("ELL read error: ", sprint(showerror, e))
        break
      end
    end

    @warn "ELL timeout"
    Log.printlog("ELL read timeout expected=", expected_addr, expected_comm)
    #LSP.sp_flush(s, LSP.SP_BUF_BOTH)
    return (-1, "", "-1")
  end

  function write(h::ELLHandle, add, comm, val=nothing; pad=8)
    if val != nothing
      s_val = uppercase(string(val, base=16, pad=pad))
    else
      s_val = ""
    end
    Log.printlog("ELL write:", add, comm, s_val)
    #LSP.sp_flush(h.s, LSP.SP_BUF_BOTH)
    LSP.write(h.s, "$add$comm$s_val")
    LSP.flush(h.s)
  end

  function resp(h::ELLHandle, add, comm, val=nothing; pad=8, timeout=15)
    lock(h.lk)
    try
      write(h, add, comm, val; pad=pad)
      return wait2read2(h.s, timeout; expected_addr=add, expected_comm=_expected_response(comm))
    catch ex
      @warn "Ell resp error" exception=(ex, catch_backtrace())
      Log.printlog("ELL resp error: ", sprint(showerror, ex))
      return (-1, "", "0")
    finally
      unlock(h.lk)
    end
  end

  function open(com="COM4")
    s = LSP.open(com, 9600)
    try
      LSP.sp_flush(s, LSP.SP_BUF_BOTH)
      _set_read_timeout_seconds(s, 3)
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
      return toInt64(r)
    else
      error("ELL wrong address: $a\n")
    end
  end

  function set_offset(h::ELLHandle, add, ang) # ang in radians
 	  Log.printlog("ELL set_offset position: ",ang)
    pulses = Int64(round(ang / (2 * pi) * PULSES_PER_TURN))
    a, c, r = resp(h, add, "so", pulses)
    if a == add
	  res = toInt64(r)
	  Log.printlog("ELL set_offset result: ",res)
	  return res
    else
      error("ELL wrong address: $a\n")
    end
  end

  ma(h::ELLHandle, add, ang) = move(h, add, "ma", ang)
  mr(h::ELLHandle, add, ang) = move(h, add, "mr", ang)
  home(h::ELLHandle, add) = resp(h, add, "ho", 0, pad=1)
  gs(h::ELLHandle, add) = resp(h, add, "gs") # get_position

  function gp(h::ELLHandle, add) #get_status
    a, c, r = resp(h, add, "gp")
    if a == -1
      error("Get position error, wrong address: $a")
    end
    ang = toInt64(r) / PULSES_PER_TURN * (2 * pi)
    return ang
  end

  function wait_ready(h::ELLHandle, add)
    while true
      (a,c,r) = ELL.gs(h, add)

      a == add && toInt64(r) == 0 && break

      sleep(0.02)
    end
  end
end #module
