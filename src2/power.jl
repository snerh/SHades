module Power

using ..DeviceManager

export PowerCommand, StartStab, SetTargetPower, StopStab, ShutdownPower
export power_loop, LaserPowerUpdate

abstract type PowerCommand end
struct StartStab <: PowerCommand end
struct SetTargetPower <: PowerCommand 
    val::Float64
end
struct StopStab <: PowerCommand end
struct ShutdownPower <: PowerCommand end
const StopStabr = StopStab

struct LaserPowerUpdate <: SystemEvent
    power::Float64
end

function _power_step!(event_ch, manager, target)
    reply = Channel(1)

    put!(manager.devices[:pd], ReadSignal(:power, reply))
    real_power = take!(reply)
    if real_power < 0
        real_power = abs(real_power)
        @warn "Measured power is negative! You have to go back in time and correct it!"
    end
    put!(event_ch, LaserPowerUpdate(real_power))

    put!(manager.devices[:ell], ReadSignal(:ang_power, reply))
    ang = take!(reply)

    frac0 = sin(ang * 2)^2
    safe_power = max(real_power, eps(Float64))
    frac = clamp(target / safe_power * frac0, 0.0, 1.0)
    new_ang = asin(sqrt(frac)) / 2

    put!(manager.devices[:ell], SetParameter(:ang_power, new_ang, reply))
    take!(reply)
    return nothing
end

function _power_worker(event_ch, manager, running, target, shutdown; period_s=0.1)
    while !shutdown[]
        if running[]
            try
                _power_step!(event_ch, manager, target[])
            catch ex
                put!(event_ch, DeviceError("Power loop failed: $(sprint(showerror, ex))"))
            end
        end
        sleep(period_s)
    end
    return nothing
end

function power_loop(cmd_ch, event_ch, manager)
    running = Ref(false)
    target = Ref(1.0)
    shutdown = Ref(false)
    worker = @async _power_worker(event_ch, manager, running, target, shutdown)

    try
        while true
            cmd = try
                take!(cmd_ch)
            catch ex
                ex isa InvalidStateException ? break : rethrow(ex)
            end
            if cmd isa StartStab
                running[] = true
            elseif cmd isa StopStab
                running[] = false
            elseif cmd isa SetTargetPower
                target[] = cmd.val
            elseif cmd isa ShutdownPower
                running[] = false
                break
            end
        end
    finally
        shutdown[] = true
        wait(worker)
        close(event_ch)
    end
end

end
