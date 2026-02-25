module Power

using ..Device

export PowerCommand, laser_loop, PowerUpdate

abstract type PowerCommand end
struct StartStab <: LaserCommand end
struct SetTargetPower <: LaserCommand 
    val:Float64
end
struct StopStabr <: LaserCommand end

struct LaserPowerUpdate <: SystemEvent
    power::Float64
end

function power_loop(cmd_ch, event_ch, manager)

    running = false
    target = 1

    while true

        if isready(cmd_ch)
            cmd = take!(cmd_ch)
            running = cmd isa StartStab
            if cmd ias SetTargetPower
                target = cmd.val
            end
        end

        if running
            reply = Channel(1)
            # get current power
            put!(manager.devices[:pd], ReadSignal(:power, reply))
            real_power = take!(reply)
            if real_power < 0
				real_power = abs(real_power)
				@warn "Measured power is negative! You have to go back in time and correct it!"
			end
            # put current power to AppState
            put!(event_ch, LaserPowerUpdate(real_power))

            # get current λ/2 angle
            put!(manager.devices[:ell], ReadSignal(:ang_power, reply))
            ang = take!(reply)

            frac0 = sin(ang*2)^2
            # required power fraction
            frac = max(0,min(target/real_power*frac0,1)) 
            new_ang = asin(frac_m^0.5)/2 # 0 - cross π/4 - parallel
            Log.printlog("new angle = ", ang)

            put!(manager.devices[:ell], SetParameter(:ang_power, new_ang,reply))
            resp = take!(reply)

            
        else
            sleep(0.5)
        end
    end
end

end