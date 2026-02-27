module Measurement

using ..Domain
using ..Parameters
using ..DeviceManager

export MeasurementCommand, StartMeasurement, StopMeasurement, ShutdownMeasurement
export measurement_loop, MeasurementStep, MeasurementDone, MeasurementStopped

abstract type MeasurementCommand end
struct StartMeasurement <: MeasurementCommand
    params::ScanAxisSet
end
struct StopMeasurement <: MeasurementCommand end
struct ShutdownMeasurement <: MeasurementCommand end

struct MeasurementStep <: SystemEvent
    spectrum::Spectrum
end

struct MeasurementDone <: SystemEvent end
struct MeasurementStopped <: SystemEvent end

function _measurement_step!(event_ch, manager, points)
    reply = Channel(1)
    function set_param(p, val)
        reply = Channel(1)
        if p == :power
            put!(event_ch, SetTargetPower(val))

        if p == :wl
            put!(manager.devices[:laser], SetParameter(:wl, val, reply))
        elseif p == :sol_wl
            put!(manager.devices[:spec], SetParameter(:wl, val, reply))
        elseif p == :slit
            put!(manager.devices[:spec], SetParameter(:slit, val, reply))
        elseif p == :temp # может, здесь и не нужно?
            put!(manager.devices[:cam], SetParameter(:temp, val, reply))
        elseif p == :acq_time
            put!(manager.devices[:cam], SetParameter(:acq_time, val, reply))
        elseif p == :frames
            put!(manager.devices[:cam], SetParameter(:frames, val, reply))
        elseif p == :polarizer
            put!(manager.devices[:ell], SetParameter(:polarizer, val, reply))
        elseif p == :analizer
            put!(manager.devices[:ell], SetParameter(:analizer, val, reply))
        else
            return () # exit if data didn't push to channel       
        end

        # test reply
        if take!(reply) != :ok 
            break
        end
    end

    new_params = points[1]
    points = points[2:end]
    for p in keys(new_params)
        set_param(p, new_params[p])
    end

    # get cam_data
    put!(manager.devices[:cam], ReadSignal(:spectrum, reply))

    return nothing
end

function _measurement_step!(event_ch, manager, points)


end

function _measurement_worker(event_ch, manager, running, points, shutdown; period_s=0.1)
    while !shutdown[]
        if starting[]
            try
                _measurement_start!(event_ch, manager, points)
                starting[] = false
            catch ex
                put!(event_ch, DeviceError("Measurement loop failed: $(sprint(showerror, ex))"))
            end
        end
        if running[]
            try
                _measurement_step!(event_ch, manager, points)
            catch ex
                put!(event_ch, DeviceError("Measurement loop failed: $(sprint(showerror, ex))"))
            end
        end
        sleep(period_s)
    end
    return nothing
end

function measurement_loop(cmd_ch, event_ch, manager)
    running = Ref(false)
    starting = Ref(false)
    points = Vector{Point}[]
    shutdown = Ref(false)
    worker = @async _measurement_worker(event_ch, manager, running, points, shutdown)

    try
        while true
            cmd = try
                take!(cmd_ch)
            catch ex
                ex isa InvalidStateException ? break : rethrow(ex)
            end
            if cmd isa StartMeasurement
                #points = axis_set_to_points(cmd.params)
                running[] = true
                starting[] = true
            elseif cmd isa StopMeasurement
                running[] = false
            elseif cmd isa ShutdownMeasurement
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

