module DeviceManager

export DeviceManager, RawDevice, MockDevice
export DeviceCommand, SetParameter, ReadSignal, ShutdownDevice
export device_loop, SystemEvent, DeviceError

abstract type DeviceCommand end

struct DeviceManager
    devices::Dict{Symbol,Channel{DeviceCommand}}
end

struct SetParameter <: DeviceCommand
    name::Symbol
    value
    reply::Channel
end

struct ReadSignal <: DeviceCommand
    name::Symbol
    reply::Channel
end

struct ShutdownDevice <: DeviceCommand end

abstract type SystemEvent end

struct DeviceError <: SystemEvent
    message::String
end

function device_loop(raw_dev)
    cmd_ch = raw_dev.device_cmd
    event_ch = raw_dev.device_events

    dev = raw_dev.init_device()
    t = raw_dev.t
    healthy = true

    try
        for cmd in cmd_ch

            if cmd isa SetParameter
                ok = call_with_timeout(() -> raw_dev.set_param(dev, cmd.name, cmd.value), t)
                ok === :timeout && (healthy = false)

                if healthy
                    put!(cmd.reply, :ok)
                else
                    put!(event_ch, DeviceError("Timeout setting $(cmd.name)"))
                end

            elseif cmd isa ReadSignal
                val = call_with_timeout(() -> raw_dev.read_signal(dev, cmd.name), t)
                val === :timeout && (healthy = false)

                if healthy
                    put!(cmd.reply, val)
                else
                    put!(event_ch, DeviceError("Read timeout"))
                end

            elseif cmd isa ShutdownDevice
                break
            end
        end
    finally
        raw_dev.close_device(dev)
    end
end

struct RawDevice
    init_device::Function
    set_param::Function
    read_signal::Function
    close_device::Function
    t::Float64 # seconds
    device_cmd::Channel{DeviceCommand}
    device_events::Channel{SystemEvent}
end

# ---- Mock hardware ----
MockDevice() = RawDevice(
    () -> Dict(),
    (dev, name, value) -> :ok,
    (dev, name) -> rand(),
    dev -> nothing,
    1.0,
    Channel{DeviceCommand}(32),
    Channel{SystemEvent}(32)
)

function call_with_timeout(f, timeout)
    t = @async f()
    try
        wait(Timeout(timeout), t)
        return fetch(t)
    catch
        return :timeout
    end
end

end
