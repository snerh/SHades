module DeviceManager

export DeviceHub, RawDevice, MockDevice, MockCamDevice
export DeviceCommand, SetParameter, ReadSignal, ShutdownDevice
export ConnectDevice, InitDevice, DisconnectDevice, GetDeviceStatus
export connect_devices!, init_devices!, disconnect_devices!, devices_status, devices_ready
export device_loop, SystemEvent, DeviceError

abstract type DeviceCommand end

struct DeviceHub
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

struct ConnectDevice <: DeviceCommand
    reply::Channel
end

struct InitDevice <: DeviceCommand
    reply::Channel
end

struct DisconnectDevice <: DeviceCommand
    reply::Channel
end

struct GetDeviceStatus <: DeviceCommand
    reply::Channel
end

struct ShutdownDevice <: DeviceCommand end

abstract type SystemEvent end

struct DeviceError <: SystemEvent
    message::String
end

function _request!(ch::Channel{DeviceCommand}, make_cmd::Function)
    reply = Channel(1)
    put!(ch, make_cmd(reply))
    return take!(reply)
end

function _sorted_device_names(hub::DeviceHub)
    sort!(collect(keys(hub.devices)); by=String)
end

function connect_devices!(hub::DeviceHub)
    out = Dict{Symbol,Any}()
    for name in _sorted_device_names(hub)
        out[name] = _request!(hub.devices[name], reply -> ConnectDevice(reply))
    end
    return out
end

function init_devices!(hub::DeviceHub)
    out = Dict{Symbol,Any}()
    for name in _sorted_device_names(hub)
        out[name] = _request!(hub.devices[name], reply -> InitDevice(reply))
    end
    return out
end

function disconnect_devices!(hub::DeviceHub)
    out = Dict{Symbol,Any}()
    for name in _sorted_device_names(hub)
        out[name] = _request!(hub.devices[name], reply -> DisconnectDevice(reply))
    end
    return out
end

function devices_status(hub::DeviceHub)
    out = Dict{Symbol,NamedTuple{(:connected,:initialized,:healthy),Tuple{Bool,Bool,Bool}}}()
    for name in _sorted_device_names(hub)
        st = _request!(hub.devices[name], reply -> GetDeviceStatus(reply))
        out[name] = st
    end
    return out
end

function devices_ready(hub::DeviceHub)::Bool
    st = devices_status(hub)
    all(v -> v.connected && v.initialized && v.healthy, values(st))
end

function device_loop(raw_dev, name::Symbol=:device)
    cmd_ch = raw_dev.device_cmd
    event_ch = raw_dev.device_events

    dev = nothing
    connected = false
    initialized = false
    healthy = true
    t = raw_dev.t

    function _safe_disconnect!()
        if connected && dev !== nothing
            try
                raw_dev.close_device(dev)
            catch ex
                put!(event_ch, DeviceError("Disconnect failed on $(name): $(sprint(showerror, ex))"))
            end
        end
        dev = nothing
        connected = false
        initialized = false
        return nothing
    end

    function _recover!()
        _safe_disconnect!()
        new_dev = call_with_timeout(() -> raw_dev.connect_device(), t)
        if new_dev === :timeout
            healthy = false
            put!(event_ch, DeviceError("Recover connect timeout on $(name)"))
            return false
        elseif new_dev isa Exception
            healthy = false
            put!(event_ch, DeviceError("Recover connect error on $(name): $(sprint(showerror, new_dev))"))
            return false
        end

        dev = new_dev
        connected = true
        initialized = false

        init_res = call_with_timeout(() -> raw_dev.init_device(dev), t)
        if init_res === :timeout
            healthy = false
            put!(event_ch, DeviceError("Recover init timeout on $(name)"))
            return false
        elseif init_res isa Exception
            healthy = false
            put!(event_ch, DeviceError("Recover init error on $(name): $(sprint(showerror, init_res))"))
            return false
        end

        initialized = true
        healthy = true
        return true
    end

    try
        for cmd in cmd_ch
            if cmd isa ConnectDevice
                if connected
                    put!(cmd.reply, :ok)
                    continue
                end
                new_dev = call_with_timeout(() -> raw_dev.connect_device(), t)
                if new_dev === :timeout
                    healthy = false
                    put!(event_ch, DeviceError("Connect timeout on $(name)"))
                    put!(cmd.reply, :timeout)
                elseif new_dev isa Exception
                    healthy = false
                    put!(event_ch, DeviceError("Connect error on $(name): $(sprint(showerror, new_dev))"))
                    put!(cmd.reply, :error)
                else
                    dev = new_dev
                    connected = true
                    initialized = false
                    healthy = true
                    put!(cmd.reply, :ok)
                end

            elseif cmd isa InitDevice
                if !connected || dev === nothing
                    put!(cmd.reply, :not_connected)
                    continue
                end
                if initialized
                    put!(cmd.reply, :ok)
                    continue
                end
                init_res = call_with_timeout(() -> raw_dev.init_device(dev), t)
                if init_res === :timeout
                    healthy = false
                    put!(event_ch, DeviceError("Init timeout on $(name)"))
                    put!(cmd.reply, :timeout)
                elseif init_res isa Exception
                    healthy = false
                    put!(event_ch, DeviceError("Init error on $(name): $(sprint(showerror, init_res))"))
                    put!(cmd.reply, :error)
                else
                    initialized = true
                    put!(cmd.reply, :ok)
                end

            elseif cmd isa DisconnectDevice
                _safe_disconnect!()
                put!(cmd.reply, :ok)

            elseif cmd isa GetDeviceStatus
                put!(cmd.reply, (connected=connected, initialized=initialized, healthy=healthy))

            elseif cmd isa SetParameter
                if !(connected && initialized && healthy)
                    put!(cmd.reply, :not_ready)
                    continue
                end
                ok = call_with_timeout(() -> raw_dev.set_param(dev, cmd.name, cmd.value), t)
                if ok === :timeout
                    healthy = false
                    put!(event_ch, DeviceError("Timeout setting $(name).$(cmd.name)"))
                    if _recover!()
                        ok2 = call_with_timeout(() -> raw_dev.set_param(dev, cmd.name, cmd.value), t)
                        if ok2 === :timeout
                            healthy = false
                            put!(event_ch, DeviceError("Retry timeout setting $(name).$(cmd.name)"))
                            put!(cmd.reply, :timeout)
                        elseif ok2 isa Exception
                            healthy = false
                            put!(event_ch, DeviceError("Retry error setting $(name).$(cmd.name): $(sprint(showerror, ok2))"))
                            put!(cmd.reply, :error)
                        else
                            put!(cmd.reply, :ok)
                        end
                    else
                        put!(cmd.reply, :timeout)
                    end
                elseif ok isa Exception
                    healthy = false
                    put!(event_ch, DeviceError("Error setting $(name).$(cmd.name): $(sprint(showerror, ok))"))
                    if _recover!()
                        ok2 = call_with_timeout(() -> raw_dev.set_param(dev, cmd.name, cmd.value), t)
                        if ok2 === :timeout
                            healthy = false
                            put!(event_ch, DeviceError("Retry timeout setting $(name).$(cmd.name)"))
                            put!(cmd.reply, :timeout)
                        elseif ok2 isa Exception
                            healthy = false
                            put!(event_ch, DeviceError("Retry error setting $(name).$(cmd.name): $(sprint(showerror, ok2))"))
                            put!(cmd.reply, :error)
                        else
                            put!(cmd.reply, :ok)
                        end
                    else
                        put!(cmd.reply, :error)
                    end
                else
                    put!(cmd.reply, :ok)
                end

            elseif cmd isa ReadSignal
                if !(connected && initialized && healthy)
                    put!(cmd.reply, :not_ready)
                    continue
                end
                val = call_with_timeout(() -> raw_dev.read_signal(dev, cmd.name), t)
                if val === :timeout
                    healthy = false
                    put!(event_ch, DeviceError("Read timeout $(name).$(cmd.name)"))
                    if _recover!()
                        val2 = call_with_timeout(() -> raw_dev.read_signal(dev, cmd.name), t)
                        if val2 === :timeout
                            healthy = false
                            put!(event_ch, DeviceError("Retry read timeout $(name).$(cmd.name)"))
                            put!(cmd.reply, :timeout)
                        elseif val2 isa Exception
                            healthy = false
                            put!(event_ch, DeviceError("Retry read error $(name).$(cmd.name): $(sprint(showerror, val2))"))
                            put!(cmd.reply, :error)
                        else
                            put!(cmd.reply, val2)
                        end
                    else
                        put!(cmd.reply, :timeout)
                    end
                elseif val isa Exception
                    healthy = false
                    put!(event_ch, DeviceError("Read error $(name).$(cmd.name): $(sprint(showerror, val))"))
                    if _recover!()
                        val2 = call_with_timeout(() -> raw_dev.read_signal(dev, cmd.name), t)
                        if val2 === :timeout
                            healthy = false
                            put!(event_ch, DeviceError("Retry read timeout $(name).$(cmd.name)"))
                            put!(cmd.reply, :timeout)
                        elseif val2 isa Exception
                            healthy = false
                            put!(event_ch, DeviceError("Retry read error $(name).$(cmd.name): $(sprint(showerror, val2))"))
                            put!(cmd.reply, :error)
                        else
                            put!(cmd.reply, val2)
                        end
                    else
                        put!(cmd.reply, :error)
                    end
                else
                    put!(cmd.reply, val)
                end

            elseif cmd isa ShutdownDevice
                if connected && dev !== nothing
                    try
                        raw_dev.abort_device(dev)
                    catch ex
                        put!(event_ch, DeviceError("Abort failed on $(name): $(sprint(showerror, ex))"))
                    end
                end
                break
            end
        end
    finally
        if connected && dev !== nothing
            try
                raw_dev.close_device(dev)
            catch ex
                put!(event_ch, DeviceError("Close failed on $(name): $(sprint(showerror, ex))"))
            end
        end
        close(event_ch)
    end
end

struct RawDevice
    connect_device::Function
    init_device::Function
    set_param::Function
    read_signal::Function
    abort_device::Function
    close_device::Function
    t::Float64 # seconds
    device_cmd::Channel{DeviceCommand}
    device_events::Channel{SystemEvent}
end

function _mock_common_device()
    RawDevice(
        () -> Dict{Symbol,Any}(
            :params => Dict{Symbol,Any}(
                :target_power => 1.0,
                :power => 1.0,
                :ang_power => 0.35,
                :wl => 550.0,
                :frames => 1,
                :acq_time => 0.1,
            ),
        ),
        dev -> :ok,
        (dev, param, value) -> begin
            dev[:params][param] = value
            :ok
        end,
        (dev, signal) -> begin
            params = dev[:params]
            if signal == :power
                target = Float64(get(params, :target_power, 1.0))
                return max(target + 0.02 * randn(), 0.0)
            elseif signal == :target_power
                return Float64(get(params, :target_power, 1.0))
            elseif signal == :ang_power
                return Float64(get(params, :ang_power, 0.35))
            elseif signal == :wl
                return Float64(get(params, :wl, 550.0))
            end
            return rand()
        end,
        dev -> nothing,
        dev -> nothing,
        1.0,
        Channel{DeviceCommand}(32),
        Channel{SystemEvent}(32),
    )
end

# ---- Mock hardware ----
MockDevice() = _mock_common_device()

function MockCamDevice()
    RawDevice(
        () -> Dict{Symbol,Any}(
            :params => Dict{Symbol,Any}(
                :wl => 550.0,
                :frames => 1,
                :acq_time => 0.1,
            ),
        ),
        dev -> :ok,
        (dev, param, value) -> begin
            dev[:params][param] = value
            :ok
        end,
        (dev, signal) -> begin
            params = dev[:params]
            if signal != :spectrum
                return get(params, signal, 0.0)
            end

            n = 1024
            frames = max(Int(round(Float64(get(params, :frames, 1)))), 1)
            wl = Float64(get(params, :wl, 550.0))
            x = collect(1.0:1.0:n)
            center = 400.0 + 120.0 * sin(wl / 65.0)
            amp = 900.0 + 180.0 * cos(wl / 45.0)
            width = 24.0

            acc = zeros(Float64, n)
            for _ in 1:frames
                acc .+= 120.0 .+ amp .* exp.(-((x .- center) .^ 2) ./ (2.0 * width^2)) .+ 30.0 .* randn(n)
            end
            return acc ./ frames
        end,
        dev -> nothing,
        dev -> nothing,
        1.0,
        Channel{DeviceCommand}(32),
        Channel{SystemEvent}(32),
    )
end

function call_with_timeout(f, timeout)
    t = @async try
        f()
    catch ex
        ex
    end
    status = timedwait(() -> istaskdone(t), timeout)
    if status == :ok
        return fetch(t)
    end
    return :timeout
end

end
