using Statistics

function _scan_check_stop_or_pause!(ctrl::MeasurementControl)
    ctrl.stop && return false
    while ctrl.pause
        ctrl.stop && return false
        sleep(0.05)
    end
    return true
end

function _time_to_seconds_scan(v)
    if v isa Number
        return Float64(v)
    end
    if v isa Tuple && length(v) == 2 && v[1] isa Number && v[2] isa AbstractString
        t0, unit = v
        return Float64(t0) * (
            unit == "ns" ? 1e-9 :
            unit == "mks" ? 1e-6 :
            unit == "ms" ? 1e-3 :
            unit == "s" ? 1.0 :
            unit == "min" ? 60.0 :
            unit == "h" ? 3600.0 : 1.0)
    end
    return 0.1
end

function _acq_time_s(p::Dict{Symbol,Any})
    if haskey(p, :acq_time)
        return _time_to_seconds_scan(p[:acq_time])
    end
    return get(p, :time_s, 0.1)
end

function _frames(p::Dict{Symbol,Any})
    Int(round(get(p, :frames, 1)))
end

function _interaction(p::Dict{Symbol,Any})
    String(get(p, :inter, "SIG"))
end

function _normalize_params!(p::Dict{Symbol,Any})
    if haskey(p, :sol_wl)
        p[:sol_wl] = round(Float64(p[:sol_wl]) / 20.0) * 20.0
    end
    return p
end

function _apply_new_params!(oldp::Dict{Symbol,Any}, newp::Dict{Symbol,Any}, devices::DeviceBundle)
    for (k, v) in newp
        if get(oldp, k, :__none__) == v
            continue
        end

        if k == :wl
            set_laser_wavelength!(devices.laser, Float64(v), _interaction(newp))
        elseif k == :sol_wl
            set_spectrometer_wavelength!(devices.spectrometer, Float64(v))
        elseif k == :acq_time
            set_camera_acquisition!(devices.camera, _time_to_seconds_scan(v))
        elseif k == :slit
            set_spectrometer_slit!(devices.spectrometer, Float64(v))
        elseif k == :power
            set_target_power!(devices.lockin, Float64(v))
        elseif k == :analyzer
            set_analyzer!(devices.ellipsometer, Float64(v))
        elseif k == :polarizer
            set_polarizer!(devices.ellipsometer, Float64(v))
        end
    end
    return copy(newp)
end

function _acquire_with_back(devices::DeviceBundle, t_s::Float64, frames::Int, back::Union{Nothing,Vector{Float64}})
    set_camera_acquisition!(devices.camera, t_s)
    data = acquire_spectrum(devices.camera; frames=frames)
    if back === nothing
        return data
    end
    if length(back) != length(data)
        return data
    end
    return data .- back
end

function _capture_background!(devices::DeviceBundle, p::Dict{Symbol,Any})
    set_shutter!(devices.spectrometer, false)
    sleep(2.0)
    back = _acquire_with_back(devices, _acq_time_s(p), _frames(p), nothing)
    set_shutter!(devices.spectrometer, true)
    return back
end

_fname_atom(v) = replace(string(v), r"[^0-9A-Za-z._-]+" => "_")

function _walk_axes!(axes::Vector{ScanAxis}, i::Int, body::Function, ctrl::MeasurementControl, p::Dict{Symbol,Any}=Dict{Symbol,Any}(), fname::String="")
    ctrl.stop && return :stop
    i > length(axes) && return body(copy(p), isempty(fname) ? "point" : fname[1:end-1])

    ax = axes[i]
    name = axis_name(ax)

    if ax isa IndependentAxis
        for el in ax.values
            ctrl.stop && return :stop
            p[name] = el
            chunk = "$(name)_$(_fname_atom(el))_"
            res = _walk_axes!(axes, i + 1, body, ctrl, p, fname * chunk)
            res == :stop && return :stop
        end
        return :continue
    elseif ax isa FixedAxis
        p[name] = ax.value
        return _walk_axes!(axes, i + 1, body, ctrl, p, fname)
    elseif ax isa DependentAxis
        haskey(p, ax.depends_on) || error("DependentAxis $(ax.name) depends on missing $(ax.depends_on)")
        p[name] = ax.f(p[ax.depends_on])
        return _walk_axes!(axes, i + 1, body, ctrl, p, fname)
    elseif ax isa MultiDependentAxis
        vals = map(dep -> get(p, dep, nothing), ax.depends_on)
        any(isnothing, vals) && error("MultiDependentAxis $(ax.name) has missing dependency")
        p[name] = ax.f(vals...)
        return _walk_axes!(axes, i + 1, body, ctrl, p, fname)
    elseif ax isa LoopAxis
        v = ax.start
        while true
            ctrl.stop && return :stop
            if ax.stop !== nothing && v > ax.stop
                return :continue
            end
            p[name] = v
            res = _walk_axes!(axes, i + 1, body, ctrl, p, fname * "$(name)_$(v)_")
            res == :stop && return :stop
            v += ax.step
        end
    end
    return _walk_axes!(axes, i + 1, body, ctrl, p, fname)
end

function run_legacy_scan!(devices::DeviceBundle, plan::ScanPlan; ch::Channel{MeasurementEvent}, ctrl::MeasurementControl, delay_s::Float64=1.5, output_dir::Union{Nothing,String}=nothing)
    acc = Dict{Symbol,Any}[]
    oldp = Dict{Symbol,Any}()
    back = nothing
    step_index = Ref(0)

    try
        put!(ch, LegacyScanStarted(output_dir))

        if has_axis(plan, :power)
            set_target_power!(devices.lockin, 0.0001)
        end

        body = function (p::Dict{Symbol,Any}, fname::String)
            _scan_check_stop_or_pause!(ctrl) || return :stop

            _normalize_params!(p)
            oldp = _apply_new_params!(oldp, p, devices)

            if back === nothing
                back = _capture_background!(devices, p)
                sleep(2.0)
            end

            delay_s > 0 && sleep(delay_s)
            _scan_check_stop_or_pause!(ctrl) || return :stop

            t_s = _acq_time_s(p)
            data = _acquire_with_back(devices, t_s, _frames(p), back)
            real_power = read_lockin_power(devices.lockin)
            sig = maximum(data) - median(data)

            point = copy(p)
            point[:time_s] = t_s
            point[:real_power] = real_power
            point[:sig] = sig
            push!(acc, point)

            step_index[] += 1
            put!(ch, LegacyScanStep(step_index[], fname, copy(point), copy(data), copy(acc)))

            if output_dir !== nothing
                mkpath(output_dir)
                save_dat_file(joinpath(output_dir, "$fname.dat"), point, data)
            end

            return :continue
        end

        res = _walk_axes!(plan.axes, 1, body, ctrl)
        if res == :stop
            put!(ch, MeasurementStopped())
        else
            put!(ch, LegacyScanFinished(length(acc)))
        end
    catch ex
        put!(ch, MeasurementError(sprint(showerror, ex), ex))
        rethrow(ex)
    finally
        close(ch)
    end
end

function run_legacy_scan!(devices::DeviceBundle, p_init; ch::Channel{MeasurementEvent}, ctrl::MeasurementControl, delay_s::Float64=1.5, output_dir::Union{Nothing,String}=nothing)
    run_legacy_scan!(devices, legacy_axes_to_plan(p_init); ch=ch, ctrl=ctrl, delay_s=delay_s, output_dir=output_dir)
end

function start_legacy_scan(devices::DeviceBundle, plan::ScanPlan; delay_s::Float64=1.5, output_dir::Union{Nothing,String}=nothing, buffer_size::Int=32)
    ctrl = MeasurementControl()
    events = Channel{MeasurementEvent}(buffer_size)
    task = @async run_legacy_scan!(devices, plan; ch=events, ctrl=ctrl, delay_s=delay_s, output_dir=output_dir)
    return MeasurementSession(ctrl, events, task)
end

function start_legacy_scan(devices::DeviceBundle, p_init; delay_s::Float64=1.5, output_dir::Union{Nothing,String}=nothing, buffer_size::Int=32)
    plan = legacy_axes_to_plan(p_init)
    ctrl = MeasurementControl()
    events = Channel{MeasurementEvent}(buffer_size)
    task = @async run_legacy_scan!(devices, plan; ch=events, ctrl=ctrl, delay_s=delay_s, output_dir=output_dir)
    return MeasurementSession(ctrl, events, task)
end
