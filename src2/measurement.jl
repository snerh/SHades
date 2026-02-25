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

function _stop_running!(running_task, stop_requested)
    if running_task !== nothing && !istaskdone(running_task)
        stop_requested[] = true
        wait(running_task)
    end
    return nothing
end

function _run_measurement(params::ScanAxisSet, event_ch, manager, stop_requested)
    axis = get(axes_dict(params), :wavelength, nothing)
    axis === nothing && throw(ArgumentError("Missing :wavelength axis"))

    wavelengths = expand(axis)
    signal = Float64[]

    for λ in wavelengths
        if stop_requested[]
            put!(event_ch, MeasurementStopped())
            return
        end

        reply = Channel(1)
        put!(manager.devices[:spec], SetParameter(:wavelength, λ, reply))
        take!(reply)

        reply2 = Channel(1)
        put!(manager.devices[:spec], ReadSignal(:signal, reply2))
        val = take!(reply2)

        push!(signal, val)
        spec = Spectrum(copy(wavelengths[1:length(signal)]), copy(signal))
        put!(event_ch, MeasurementStep(spec))
    end

    stop_requested[] ? put!(event_ch, MeasurementStopped()) : put!(event_ch, MeasurementDone())
end

function measurement_loop(cmd_ch, event_ch, manager)
    running_task = nothing
    stop_requested = Ref(false)

    try
        while true
            cmd = try
                take!(cmd_ch)
            catch ex
                ex isa InvalidStateException ? break : rethrow(ex)
            end

            if cmd isa StartMeasurement
                _stop_running!(running_task, stop_requested)
                stop_requested = Ref(false)
                running_task = @async begin
                    try
                        _run_measurement(cmd.params, event_ch, manager, stop_requested)
                    catch ex
                        put!(event_ch, DeviceError("Measurement failed: $(sprint(showerror, ex))"))
                    end
                end
            elseif cmd isa StopMeasurement
                _stop_running!(running_task, stop_requested)
            elseif cmd isa ShutdownMeasurement
                _stop_running!(running_task, stop_requested)
                break
            end
        end
    finally
        close(event_ch)
    end
end

end
