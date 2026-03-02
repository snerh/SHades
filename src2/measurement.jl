module Measurement

using Statistics
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

mutable struct MeasurementContext
    oldp::Dict{Symbol,Any}
    back::Union{Nothing,Vector{Float64}}
    wls::Vector{Float64}
    sigs::Vector{Float64}
end

function _stop_running!(running_task, stop_requested)
    if running_task !== nothing && !istaskdone(running_task)
        stop_requested[] = true
        wait(running_task)
    end
    return nothing
end

function _set_param!(manager, dev::Symbol, name::Symbol, value)
    reply = Channel(1)
    put!(manager.devices[dev], SetParameter(name, value, reply))
    resp = take!(reply)
    resp == :ok || throw(ErrorException("SetParameter failed: device=$(dev), name=$(name), resp=$(resp)"))
    return nothing
end

function _read_signal(manager, dev::Symbol, name::Symbol)
    reply = Channel(1)
    put!(manager.devices[dev], ReadSignal(name, reply))
    return take!(reply)
end

function _to_float_vector(x)
    if x isa AbstractVector
        return Float64.(collect(x))
    elseif x isa Number
        return [Float64(x)]
    end
    return Float64.(collect(x))
end

function _as_seconds(v)
    v isa Number && return Float64(v)
    s = strip(String(v))
    m = match(r"^([-+]?(?:\d+(?:\.\d*)?|\.\d+))\s*(us|ms|s)?$", s)
    m === nothing && return 0.1
    val = parse(Float64, m.captures[1])
    unit = m.captures[2]
    unit === nothing && return val
    unit == "s" && return val
    unit == "ms" && return val / 1000.0
    unit == "us" && return val / 1_000_000.0
    return val
end

_frames(p::Dict{Symbol,Any}) = Int(round(Float64(get(p, :frames, 1))))

function _normalize_params!(p::Dict{Symbol,Any})
    if haskey(p, :sol_wl)
        p[:sol_wl] = round(Float64(p[:sol_wl]) / 20.0) * 20.0
    end
    return p
end

function _apply_new_params!(oldp::Dict{Symbol,Any}, newp::Dict{Symbol,Any}, manager)
    for (k, v) in newp
        if get(oldp, k, :__none__) == v
            continue
        end

        if k == :wl
            _set_param!(manager, :laser, :wl, Float64(v))
        elseif k == :inter || k == :interaction
            _set_param!(manager, :laser, :interaction, String(v))
        elseif k == :sol_wl
            _set_param!(manager, :spec, :wl, Float64(v))
        elseif k == :slit
            _set_param!(manager, :spec, :slit, Float64(v))
        elseif k == :acq_time || k == :time_s
            _set_param!(manager, :cam, :acq_time, _as_seconds(v))
        elseif k == :frames
            _set_param!(manager, :cam, :frames, _frames(newp))
        elseif k == :power
            _set_param!(manager, :pd, :target_power, Float64(v))
        elseif k == :analyzer || k == :analizer
            _set_param!(manager, :ell, :analyzer, Float64(v))
        elseif k == :polarizer
            _set_param!(manager, :ell, :polarizer, Float64(v))
        elseif k == :temp || k == :camera_temp
            _set_param!(manager, :cam, :temp, Float64(v))
        end
    end
    return copy(newp)
end

function _acquire_with_back(manager, p::Dict{Symbol,Any}, back::Union{Nothing,Vector{Float64}})
    _set_param!(manager, :cam, :acq_time, _as_seconds(get(p, :acq_time, get(p, :time_s, 0.1))))
    _set_param!(manager, :cam, :frames, _frames(p))
    data = _to_float_vector(_read_signal(manager, :cam, :spectrum))
    if back === nothing || length(back) != length(data)
        return data
    end
    return data .- back
end

function _capture_background!(manager, p::Dict{Symbol,Any})
    _set_param!(manager, :spec, :shutter, false)
    sleep(2.0)
    back = _acquire_with_back(manager, p, nothing)
    _set_param!(manager, :spec, :shutter, true)
    return back
end

function _walk_axes_measurement!(axes::Vector{ScanAxis}, i::Int, body::Function, stop_requested, p::Dict{Symbol,Any}=Dict{Symbol,Any}())
    stop_requested[] && return :stop
    i > length(axes) && return body(copy(p))

    ax = axes[i]
    name = axis_name(ax)

    if ax isa ListAxis
        for el in ax.values
            stop_requested[] && return :stop
            p[name] = el
            res = _walk_axes_measurement!(axes, i + 1, body, stop_requested, p)
            res == :stop && return :stop
        end
        return :continue
    elseif ax isa RangeAxis
        for el in collect(ax.range)
            stop_requested[] && return :stop
            p[name] = el
            res = _walk_axes_measurement!(axes, i + 1, body, stop_requested, p)
            res == :stop && return :stop
        end
        return :continue
    elseif ax isa FixedAxis
        p[name] = ax.value
        return _walk_axes_measurement!(axes, i + 1, body, stop_requested, p)
    elseif ax isa DependentAxis
        haskey(p, ax.depends_on) || error("DependentAxis $(ax.name) depends on missing $(ax.depends_on)")
        p[name] = ax.f(p[ax.depends_on])
        return _walk_axes_measurement!(axes, i + 1, body, stop_requested, p)
    elseif ax isa MultiDependentAxis
        vals = map(dep -> get(p, dep, nothing), ax.depends_on)
        any(isnothing, vals) && error("MultiDependentAxis $(ax.name) has missing dependency")
        p[name] = ax.f(vals...)
        return _walk_axes_measurement!(axes, i + 1, body, stop_requested, p)
    elseif ax isa LoopAxis
        ax.step == 0 && error("LoopAxis step cannot be 0")
        v = ax.start
        while true
            stop_requested[] && return :stop
            if ax.stop !== nothing
                if (ax.step > 0 && v > ax.stop) || (ax.step < 0 && v < ax.stop)
                    return :continue
                end
            end
            p[name] = v
            res = _walk_axes_measurement!(axes, i + 1, body, stop_requested, p)
            res == :stop && return :stop
            v += ax.step
        end
    end

    return _walk_axes_measurement!(axes, i + 1, body, stop_requested, p)
end

function _first_point(scan_axes::ScanAxisSet)
    firstp = Ref{Union{Nothing,Dict{Symbol,Any}}}(nothing)
    res = _walk_axes_measurement!(scan_axes.axes, 1, p -> begin
        firstp[] = p
        return :stop
    end, Ref(false))
    res
    return something(firstp[], Dict{Symbol,Any}())
end

function _measurement_start!(manager, scan_axes::ScanAxisSet)
    first_point = _first_point(scan_axes)
    _normalize_params!(first_point)

    if has_axis(scan_axes, :power)
        _set_param!(manager, :pd, :target_power, 0.0001)
    end

    oldp = _apply_new_params!(Dict{Symbol,Any}(), first_point, manager)
    back = _capture_background!(manager, first_point)
    sleep(2.0)

    return MeasurementContext(oldp, back, Float64[], Float64[])
end

function _point_wl(p::Dict{Symbol,Any}, fallback::Int)
    if haskey(p, :wl)
        return Float64(p[:wl])
    elseif haskey(p, :wavelength)
        return Float64(p[:wavelength])
    end
    return Float64(fallback)
end

function _measurement_step!(event_ch, manager, ctx::MeasurementContext, point::Dict{Symbol,Any}, step_index::Int)
    p = copy(point)
    _normalize_params!(p)
    ctx.oldp = _apply_new_params!(ctx.oldp, p, manager)

    delay_s = Float64(get(p, :delay_s, 1.5))
    delay_s > 0 && sleep(delay_s)

    data = _acquire_with_back(manager, p, ctx.back)
    sig = maximum(data) - median(data)
    wl = _point_wl(p, step_index)

    push!(ctx.wls, wl)
    push!(ctx.sigs, sig)
    put!(event_ch, MeasurementStep(Spectrum(copy(ctx.wls), copy(ctx.sigs))))

    return nothing
end

function _run_measurement!(event_ch, manager, scan_axes::ScanAxisSet, stop_requested)
    ctx = _measurement_start!(manager, scan_axes)
    step_index = Ref(0)

    body = function (p::Dict{Symbol,Any})
        stop_requested[] && return :stop
        step_index[] += 1
        _measurement_step!(event_ch, manager, ctx, p, step_index[])
        return :continue
    end

    res = _walk_axes_measurement!(scan_axes.axes, 1, body, stop_requested)
    if res == :stop
        put!(event_ch, MeasurementStopped())
    else
        put!(event_ch, MeasurementDone())
    end
    return nothing
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
                        _run_measurement!(event_ch, manager, cmd.params, stop_requested)
                    catch ex
                        put!(event_ch, DeviceError("Measurement loop failed: $(sprint(showerror, ex))"))
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
