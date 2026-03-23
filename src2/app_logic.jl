module AppLogic

using ..Domain
using ..Parameters
using ..ParameterParser
using ..State
using ..TimeUtils: try_parse_duration_seconds

export set_raw_param!, sync_raw_params!, validate_raw_params, collect_fixed_params
export is_measurement_active, is_focus_mode, focus_scan_params
export signal_points, raw_points

function is_measurement_active(state::AppState)
    state.measurement_state in (State.Preparing, State.Running, State.Paused, State.Stopping)
end

function _refresh_scan_params!(state::AppState)
    is_measurement_active(state) && return state.measurement.scan_params
    try
        state.measurement.scan_params = build_scan_axis_set_from_text_specs(state.measurement.raw_params)
    catch
        # Keep previous scan_params while user is still editing.
    end
    return state.measurement.scan_params
end

function set_raw_param!(state::AppState, name::Symbol, val::String)
    idx = findfirst(p -> p.first == name, state.measurement.raw_params)
    if idx === nothing
        push!(state.measurement.raw_params, name => val)
    else
        state.measurement.raw_params[idx] = name => val
    end
    _refresh_scan_params!(state)
    return state
end

function sync_raw_params!(state::AppState, raw_params::Vector{Pair{Symbol,String}})
    state.measurement.raw_params = copy(raw_params)
    _refresh_scan_params!(state)
    return state
end

function collect_fixed_params(raw_params::Vector{Pair{Symbol,String}})
    out = Dict{Symbol,Any}()
    for (name, spec) in raw_params
        ax = try
            parse_axis_spec(name, spec)
        catch
            nothing
        end
        ax isa FixedAxis || continue
        out[name] = ax.value
    end
    return out
end

function validate_raw_params(raw_params::Vector{Pair{Symbol,String}})
    errs = Dict{Symbol,String}()
    for (name, spec) in raw_params
        spec_str = String(spec)
        stripped = strip(spec_str)
        uses_expr = startswith(stripped, "=")
        uses_sequence = occursin(":", spec_str) || occursin("..", spec_str) || occursin(",", spec_str)

        ax = nothing
        try
            ax = parse_axis_spec(name, spec_str)
        catch ex
            errs[name] = sprint(showerror, ex)
            continue
        end

        if name in (:acq_time, :time_s) && !isempty(stripped) && !uses_expr && !uses_sequence
            if try_parse_duration_seconds(stripped) === nothing
                errs[name] = "invalid duration format"
                continue
            end
        end

        if uses_expr
            if !(ax isa FixedAxis || ax isa DependentAxis || ax isa MultiDependentAxis)
                errs[name] = "invalid expression"
            elseif ax isa FixedAxis && ax.value isa AbstractString
                errs[name] = "invalid expression"
            end
        elseif uses_sequence
            if !(ax isa RangeAxis || ax isa ListAxis)
                errs[name] = "invalid range/list format"
            end
        end
    end
    return errs
end

function is_focus_mode(state::AppState)
    sp = state.measurement.scan_params
    sp === nothing && return false
    return any(ax -> ax isa LoopAxis && ax.name == :loop && ax.stop === nothing, sp.axes)
end

function focus_scan_params(scan_params::ScanAxisSet)
    axes = ScanAxis[ax for ax in scan_params.axes if !(ax isa LoopAxis && ax.name == :loop)]
    push!(axes, LoopAxis(name=:loop, start=1, step=1, stop=nothing))
    return ScanAxisSet(axes)
end

function signal_points(state::AppState)
    if !isempty(state.measurement.points)
        return state.measurement.points
    end
    if state.measurement.current_spectrum !== nothing
        n = min(length(state.measurement.current_spectrum.wavelength), length(state.measurement.current_spectrum.signal))
        return [Dict{Symbol,Any}(:wl => state.measurement.current_spectrum.wavelength[i], :sig => state.measurement.current_spectrum.signal[i]) for i in 1:n]
    end
    return Dict{Symbol,Any}[]
end

function raw_points(state::AppState)
    pts = Dict{Symbol,Any}[]
    for i in eachindex(state.measurement.current_raw)
        push!(pts, Dict{Symbol,Any}(:idx => Float64(i), :value => state.measurement.current_raw[i]))
    end
    return pts
end

end
