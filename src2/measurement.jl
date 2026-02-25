module Measurement

using ..Domain
using ..Parameters
using ..DeviceManager

export MeasurementCommand, measurement_loop, MeasurementStep, MeasurementDone

abstract type MeasurementCommand end
struct StartMeasurement <: MeasurementCommand
    params::ScanAxisSet
end
struct StopMeasurement <: MeasurementCommand end

struct MeasurementStep <: SystemEvent
    spectrum::Spectrum
end

struct MeasurementDone <: SystemEvent end

function measurement_loop(cmd_ch, event_ch, manager)

    running = false
    params = nothing

    while true

        if isready(cmd_ch)
            cmd = take!(cmd_ch)

            if cmd isa StartMeasurement
                running = true
                params = cmd.params
            elseif cmd isa StopMeasurement
                running = false
            end
        end

        if running && params !== nothing
            ## переписать!!!

            wl_spec = axes_dict(params)[:wavelength]
            wavelengths = expand(wl_spec)

            signal = Float64[]

            for λ in wavelengths
                reply = Channel(1)
                put!(manager.devices[:spec], SetParameter(:wavelength, λ, reply))
                take!(reply)

                reply2 = Channel(1)
                put!(manager.devices[:spec], ReadSignal(:signal, reply2))
                val = take!(reply2)

                push!(signal, val)

                spec = Spectrum(copy(wavelengths[1:length(signal)]),
                                copy(signal))

                put!(event_ch, MeasurementStep(spec))
            end

            put!(event_ch, MeasurementDone())
            running = false
        else
            sleep(0.05)
        end
    end
end

end
