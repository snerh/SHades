module Measurement

using Statistics
using JSON
using ..Domain
using ..Parameters
using ..DeviceManager

export MeasurementCommand, StartMeasurement, StopMeasurement, ShutdownMeasurement, UpdateMeasurementParams
export measurement_loop, MeasurementStarted, MeasurementStep, MeasurementDone, MeasurementStopped
export DirChosen

abstract type MeasurementCommand end

struct StartMeasurement <: MeasurementCommand
    params::ScanAxisSet
    output_dir::Union{Nothing,String}
end
StartMeasurement(params::ScanAxisSet) = StartMeasurement(params, nothing)

struct StopMeasurement <: MeasurementCommand end
struct ShutdownMeasurement <: MeasurementCommand end
struct UpdateMeasurementParams <: MeasurementCommand
    params::Dict{Symbol,Any}
end

struct DirChosen <: SystemEvent
    dir::Union{Nothing,String}
end

struct MeasurementStarted <: SystemEvent
    output_dir::Union{Nothing,String}
end

struct MeasurementStep <: SystemEvent
    index::Int
    point::Point
    raw::Vector{Float64}
    spectrum::Spectrum
    file_path::Union{Nothing,String}
    reused::Bool
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

function _hub_ready(manager)::Bool
    try
        return devices_ready(manager)
    catch
        return false
    end
end

function _to_float_vector(x)
    if x isa AbstractVector
        return Float64.(collect(x))
    elseif x isa Number
        return [Float64(x)]
    end
    return Float64.(collect(x))
end

_fname_atom(v) = replace(string(v), r"[^0-9A-Za-z._-]+" => "_")

function _save_raw_file(path::AbstractString, params::Dict{Symbol,Any}, data::Vector{Float64})
    json = JSON.json(params)
    open(path, "w") do io
        println(io, "# ", json)
        for y in data
            println(io, y)
        end
    end
    return path
end

function _load_raw_file(path::AbstractString)
    data = Float64[]
    open(path, "r") do io
        s = readline(io)
        point = Dict(JSON.parse(s[2:end],Dict{Symbol,Any}))
        println(point)
        for line in eachline(io)
            s = strip(line)
            isempty(s) && continue
            startswith(s, "#") && continue
            try
                push!(data, parse(Float64, s))
            catch
            end
        end
        return (point, data)
    end
end

function import_dir(path::AbstractString)
	files = readdir(path,join = true,sort = true)
    dat_files = filter(x -> x[end-3:end]==".dat",files)
    if length(dat_files) == 0
        return nothing
    end
    function aux(file)
        point, data = _load_raw_file(file)
        new_p = new_point(point, data)
        new_p
    end
    full_list = map(aux, dat_files)
    return full_list
end

function _as_seconds(v)
    if v isa Number
        return Float64(v)
    elseif v isa String
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
    elseif v isa Vector{Any}
        val = v[1]
        unit = v[2]
        unit == "s" && return val
        unit == "ms" && return val / 1000.0
        unit == "us" && return val / 1_000_000.0
    end

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

function _walk_axes_measurement!(
    axes::Vector{ScanAxis},
    i::Int,
    body::Function,
    stop_requested,
    p::Dict{Symbol,Any}=Dict{Symbol,Any}(),
    stem::String=""
)
    stop_requested[] && return :stop
    if i > length(axes)
        file_stem = isempty(stem) ? "point" : (endswith(stem, "_") ? stem[1:end-1] : stem)
        return body(copy(p), file_stem)
    end

    ax = axes[i]
    name = axis_name(ax)

    if ax isa ListAxis
        for el in ax.values
            stop_requested[] && return :stop
            p[name] = el
            chunk = "$(name)_$(_fname_atom(el))_"
            res = _walk_axes_measurement!(axes, i + 1, body, stop_requested, p, stem * chunk)
            res == :stop && return :stop
        end
        return :continue
    elseif ax isa RangeAxis
        for el in collect(ax.range)
            stop_requested[] && return :stop
            p[name] = el
            chunk = "$(name)_$(_fname_atom(el))_"
            res = _walk_axes_measurement!(axes, i + 1, body, stop_requested, p, stem * chunk)
            res == :stop && return :stop
        end
        return :continue
    elseif ax isa FixedAxis
        p[name] = ax.value
        return _walk_axes_measurement!(axes, i + 1, body, stop_requested, p, stem)
    elseif ax isa DependentAxis
        haskey(p, ax.depends_on) || error("DependentAxis $(ax.name) depends on missing $(ax.depends_on)")
        p[name] = ax.f(p[ax.depends_on])
        return _walk_axes_measurement!(axes, i + 1, body, stop_requested, p, stem)
    elseif ax isa MultiDependentAxis
        vals = map(dep -> get(p, dep, nothing), ax.depends_on)
        any(isnothing, vals) && error("MultiDependentAxis $(ax.name) has missing dependency")
        p[name] = ax.f(vals...)
        return _walk_axes_measurement!(axes, i + 1, body, stop_requested, p, stem)
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
            chunk = "$(name)_$(_fname_atom(v))_"
            res = _walk_axes_measurement!(axes, i + 1, body, stop_requested, p, stem * chunk)
            res == :stop && return :stop
            v += ax.step
        end
    end

    return _walk_axes_measurement!(axes, i + 1, body, stop_requested, p, stem)
end

function _first_point(scan_axes::ScanAxisSet)
    firstp = Ref{Union{Nothing,Dict{Symbol,Any}}}(nothing)
    _walk_axes_measurement!(scan_axes.axes, 1, (p, _stem) -> begin
        firstp[] = p
        return :stop
    end, Ref(false))
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

function new_point(p, data)
    new_p = copy(p)
    sig = isempty(data) ? NaN : maximum(data) - median(data)
    t_s = _as_seconds(get(p, :acq_time, get(p, :time_s, 0.1)))
    
    new_p = copy(p)
    new_p[:time_s] = t_s
    new_p[:sig] = sig
    return new_p
end

function _measurement_step!(
    event_ch,
    manager,
    ctx::MeasurementContext,
    point::Dict{Symbol,Any},
    step_index::Int;
    output_dir::Union{Nothing,String}=nothing,
    stem::String="point"
)
    p = copy(point)
    #_normalize_params!(p)
    ctx.oldp = _apply_new_params!(ctx.oldp, p, manager)

    file_path = output_dir === nothing ? nothing : joinpath(output_dir, "$(stem).dat")
    reused = false
    data = Float64[]

    if file_path !== nothing && isfile(file_path) && False
        (p, data) = _load_raw_file(file_path)
        reused = true
    else
        delay_s = Float64(get(p, :delay_s, 1.5))
        delay_s > 0 && sleep(delay_s)
        data = _acquire_with_back(manager, p, ctx.back)
    end

    real_power = try
        Float64(_read_signal(manager, :pd, :power))
    catch
        NaN
    end

    point_payload = new_point(p, data)
    point_payload[:real_power] = real_power   
    sig = point_payload[:sig]
    wl = point_payload[:wl] 

    if !reused && file_path !== nothing
        _save_raw_file(file_path, point_payload, data)
    end

    push!(ctx.wls, wl)
    push!(ctx.sigs, sig)
    put!(
        event_ch,
        MeasurementStep(
            step_index,
            point_payload,
            copy(data),
            Spectrum(copy(ctx.wls), copy(ctx.sigs)),
            file_path,
            reused,
        )
    )

    return nothing
end

function _run_measurement!(event_ch, manager, scan_axes::ScanAxisSet, output_dir::Union{Nothing,String}, stop_requested, live_params)
    ctx = _measurement_start!(manager, scan_axes)
    step_index = Ref(0)
    output_dir !== nothing && mkpath(output_dir)
    put!(event_ch, MeasurementStarted(output_dir))

    body = function (p::Dict{Symbol,Any}, stem::String)
        stop_requested[] && return :stop
        step_index[] += 1
        p_eff = copy(p)
        lp = live_params[]
        if !isempty(lp)
            merge!(p_eff, lp)
        end
        _measurement_step!(event_ch, manager, ctx, p_eff, step_index[]; output_dir=output_dir, stem=stem)
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
    live_params = Ref(Dict{Symbol,Any}())

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
                live_params[] = Dict{Symbol,Any}()
                if !_hub_ready(manager)
                    put!(event_ch, DeviceError("Devices are not initialized. Run Connect/Init first."))
                    continue
                end
                running_task = @async begin
                    try
                        _run_measurement!(event_ch, manager, cmd.params, cmd.output_dir, stop_requested, live_params)
                    catch ex
                        put!(event_ch, DeviceError("Measurement loop failed: $(sprint(showerror, ex))"))
                    end
                end
            elseif cmd isa StopMeasurement
                _stop_running!(running_task, stop_requested)
                live_params[] = Dict{Symbol,Any}()
            elseif cmd isa ShutdownMeasurement
                _stop_running!(running_task, stop_requested)
                break
            elseif cmd isa UpdateMeasurementParams
                merge!(live_params[], cmd.params)
            end
        end
    finally
        close(event_ch)
    end
end

end
