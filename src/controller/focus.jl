using Statistics

@inline function _push_ring!(v::Vector{Float64}, x::Float64, max_points::Int)
    push!(v, x)
    if length(v) > max_points
        deleteat!(v, 1)
    end
    return v
end

function run_focus!(
    devices::DeviceBundle,
    params::ScanParams,
    ch::Channel{MeasurementEvent},
    ctrl::MeasurementControl;
    max_points::Int=2000
)
    wls = Float64[]
    sigs = Float64[]
    wl = isempty(params.wavelengths) ? 0.0 : params.wavelengths[1]

    try
        put!(ch, MeasurementStarted(params))

        set_camera_acquisition!(devices.camera, params.acq_time_s)
        set_camera_temperature!(devices.camera, params.camera_temp_c)
        set_target_power!(devices.lockin, params.target_power)
        set_polarizer!(devices.ellipsometer, params.polarizer_deg)
        set_analyzer!(devices.ellipsometer, params.analyzer_deg)

        set_laser_wavelength!(devices.laser, wl, params.interaction)
        set_spectrometer_wavelength!(devices.spectrometer, _choose_sol_wavelength(params, wl))

        i = 0
        while true
            _check_stop_or_pause!(ctrl) || begin
                put!(ch, MeasurementStopped())
                return
            end

            params.delay_s > 0 && sleep(params.delay_s)
            _check_stop_or_pause!(ctrl) || begin
                put!(ch, MeasurementStopped())
                return
            end

            raw = acquire_spectrum(devices.camera; frames=params.frames)
            power = read_lockin_power(devices.lockin)
            signal = maximum(raw) - median(raw)

            _push_ring!(wls, wl, max_points)
            _push_ring!(sigs, signal, max_points)
            i += 1
            _emit_step!(ch, i, wl, signal, power, raw, wls, sigs)
        end
    catch ex
        put!(ch, MeasurementError(sprint(showerror, ex), ex))
        rethrow(ex)
    finally
        close(ch)
    end
end

function start_focus_measurement(
    devices::DeviceBundle,
    params::ScanParams;
    buffer_size::Int=32,
    max_points::Int=2000
)
    ctrl = MeasurementControl()
    events = Channel{MeasurementEvent}(buffer_size)
    task = @async run_focus!(devices, params, events, ctrl; max_points=max_points)
    return MeasurementSession(ctrl, events, task)
end
