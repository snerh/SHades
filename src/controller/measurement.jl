using Statistics

@inline function _choose_sol_wavelength(params::ScanParams, wl::Float64)
    if params.fixed_sol_wavelength !== nothing
        return params.fixed_sol_wavelength
    end
    return round((wl / params.sol_divider) / 20.0) * 20.0
end

function _emit_step!(ch::Channel{MeasurementEvent}, i::Int, wl::Float64, signal::Float64, power::Float64, raw::Vector{Float64}, wls::Vector{Float64}, sigs::Vector{Float64})
    spec = Spectrum(copy(wls), copy(sigs))
    put!(ch, StepResult(i, wl, signal, power, copy(raw), spec))
end

function run_measurement!(devices::DeviceBundle, params::ScanParams, ch::Channel{MeasurementEvent}, ctrl::MeasurementControl)
    wls = Float64[]
    sigs = Float64[]

    try
        put!(ch, MeasurementStarted(params))

        set_camera_acquisition!(devices.camera, params.acq_time_s)
        set_camera_temperature!(devices.camera, params.camera_temp_c)
        set_target_power!(devices.lockin, params.target_power)
        set_polarizer!(devices.ellipsometer, params.polarizer_deg)
        set_analyzer!(devices.ellipsometer, params.analyzer_deg)

        for (i, wl) in enumerate(params.wavelengths)
            _check_stop_or_pause!(ctrl) || begin
                put!(ch, MeasurementStopped())
                return
            end

            set_laser_wavelength!(devices.laser, wl, params.interaction)
            set_spectrometer_wavelength!(devices.spectrometer, _choose_sol_wavelength(params, wl))
            params.delay_s > 0 && sleep(params.delay_s)

            _check_stop_or_pause!(ctrl) || begin
                put!(ch, MeasurementStopped())
                return
            end

            raw = acquire_spectrum(devices.camera; frames=params.frames)
            power = read_lockin_power(devices.lockin)
            signal = maximum(raw) - median(raw)

            push!(wls, wl)
            push!(sigs, signal)
            _emit_step!(ch, i, wl, signal, power, raw, wls, sigs)
        end

        put!(ch, MeasurementFinished(Spectrum(copy(wls), copy(sigs))))
    catch ex
        put!(ch, MeasurementError(sprint(showerror, ex), ex))
        rethrow(ex)
    finally
        close(ch)
    end
end
