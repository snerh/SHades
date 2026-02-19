const _SAFE_CONSTS = Dict{Symbol,Float64}(
    :pi => π,
    :e => ℯ,
)

const _SAFE_FUNCS = Dict{Symbol,Function}(
    :+ => (args...) -> +(args...),
    :- => (args...) -> -(args...),
    :* => (args...) -> *(args...),
    :/ => (args...) -> /(args...),
    :^ => (a, b) -> a ^ b,
    :sin => sin,
    :cos => cos,
    :tan => tan,
    :asin => asin,
    :acos => acos,
    :atan => atan,
    :abs => abs,
    :sqrt => sqrt,
    :exp => exp,
    :log => log,
    :min => (args...) -> min(args...),
    :max => (args...) -> max(args...),
    :floor => floor,
    :ceil => ceil,
    :round => round,
    :deg2rad => deg2rad,
    :rad2deg => rad2deg,
)

_NUM = raw"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?"

function _parse_num(s::AbstractString)
    parse(Float64, strip(s))
end

function _collect_deps!(acc::Set{Symbol}, ex)
    if ex isa Symbol
        if !haskey(_SAFE_CONSTS, ex) && !haskey(_SAFE_FUNCS, ex)
            push!(acc, ex)
        end
    elseif ex isa Expr
        if ex.head == :call
            f = ex.args[1]
            f isa Symbol || error("Only simple function names are allowed")
            haskey(_SAFE_FUNCS, f) || error("Function '$f' is not allowed")
            for arg in ex.args[2:end]
                _collect_deps!(acc, arg)
            end
        else
            error("Expression node '$(ex.head)' is not allowed")
        end
    elseif !(ex isa Number)
        error("Unsupported expression element: $(typeof(ex))")
    end
    return acc
end

function _safe_eval(ex, env::Dict{Symbol,Float64})
    if ex isa Number
        return Float64(ex)
    elseif ex isa Symbol
        if haskey(env, ex)
            return env[ex]
        elseif haskey(_SAFE_CONSTS, ex)
            return _SAFE_CONSTS[ex]
        end
        error("Unknown symbol '$ex'")
    elseif ex isa Expr
        ex.head == :call || error("Only function calls are allowed")
        f = ex.args[1]
        f isa Symbol || error("Only simple function names are allowed")
        haskey(_SAFE_FUNCS, f) || error("Function '$f' is not allowed")
        vals = map(arg -> _safe_eval(arg, env), ex.args[2:end])
        return _SAFE_FUNCS[f](vals...)
    end
    error("Unsupported expression type: $(typeof(ex))")
end

function _make_numeric_values(start::Float64, step::Float64, stop::Float64)
    step == 0 && error("step cannot be 0")
    if start < stop && step < 0
        error("step must be > 0 for ascending range")
    elseif start > stop && step > 0
        error("step must be < 0 for descending range")
    end
    collect(start:step:stop)
end

function _parse_numeric_axis(name::Symbol, spec::AbstractString)
    m3 = match(Regex("^\\s*($_NUM)\\s*:\\s*($_NUM)\\s*:\\s*($_NUM)\\s*\$"), spec)
    if m3 !== nothing
        a = _parse_num(m3.captures[1])
        b = _parse_num(m3.captures[2])
        c = _parse_num(m3.captures[3])
        return IndependentAxis(name, _make_numeric_values(a, b, c))
    end

    m3dots = match(Regex("^\\s*($_NUM)\\s*\\.\\.\\s*($_NUM)\\s*\\.\\.\\s*($_NUM)\\s*\$"), spec)
    if m3dots !== nothing
        a = _parse_num(m3dots.captures[1])
        b = _parse_num(m3dots.captures[2])
        c = _parse_num(m3dots.captures[3])
        return IndependentAxis(name, _make_numeric_values(a, c, b))
    end

    m2 = match(Regex("^\\s*($_NUM)\\s*:\\s*($_NUM)\\s*\$"), spec)
    if m2 !== nothing
        a = _parse_num(m2.captures[1])
        b = _parse_num(m2.captures[2])
        step = a <= b ? 1.0 : -1.0
        return IndependentAxis(name, _make_numeric_values(a, step, b))
    end

    m2dots = match(Regex("^\\s*($_NUM)\\s*\\.\\.\\s*($_NUM)\\s*\$"), spec)
    if m2dots !== nothing
        a = _parse_num(m2dots.captures[1])
        b = _parse_num(m2dots.captures[2])
        step = a <= b ? 1.0 : -1.0
        return IndependentAxis(name, _make_numeric_values(a, step, b))
    end

    if occursin(",", spec)
        vals = map(x -> _parse_num(x), split(spec, ","))
        return IndependentAxis(name, vals)
    end

    if occursin(Regex("^\\s*$_NUM\\s*\$"), spec)
        return FixedAxis(name, _parse_num(spec))
    end

    return nothing
end

function parse_axis_spec(name::Symbol, raw_spec::AbstractString; numeric_only::Bool=false)
    spec = strip(raw_spec)
    isempty(spec) && return nothing

    if startswith(spec, "=")
        expr_src = strip(spec[2:end])
        isempty(expr_src) && error("Empty expression for axis '$name'")
        ex = Meta.parse(expr_src)
        deps = collect(_collect_deps!(Set{Symbol}(), ex))
        if isempty(deps)
            v = _safe_eval(ex, Dict{Symbol,Float64}())
            return FixedAxis(name, v)
        elseif length(deps) == 1
            dep = deps[1]
            return DependentAxis(name, dep, x -> _safe_eval(ex, Dict(dep => Float64(x))))
        else
            dep_order = sort(deps)
            return MultiDependentAxis(name, dep_order, (xs...) -> begin
                env = Dict{Symbol,Float64}()
                for (i, d) in enumerate(dep_order)
                    env[d] = Float64(xs[i])
                end
                _safe_eval(ex, env)
            end)
        end
    end

    axis = _parse_numeric_axis(name, spec)
    axis !== nothing && return axis

    if numeric_only
        error("Axis '$name' expects numeric value/range/list, or dependent expression starting with '='")
    end

    # Safe string literal mode for categorical fixed params.
    if startswith(spec, "\"") && endswith(spec, "\"")
        return FixedAxis(name, spec[2:end-1])
    end
    return FixedAxis(name, spec)
end

function build_scan_plan_from_text_specs(
    specs::Vector{Pair{Symbol,String}};
    fixed::AbstractVector{<:Pair}=Pair{Symbol,Any}[],
    numeric_axes::AbstractSet{Symbol}=Set{Symbol}(),
)
    axes = ScanAxis[]
    for (name, spec) in specs
        ax = parse_axis_spec(name, spec; numeric_only=(name in numeric_axes))
        ax === nothing || push!(axes, ax)
    end
    for (name, val) in fixed
        push!(axes, FixedAxis(name, val))
    end
    return ScanPlan(axes)
end

function validate_scan_plan(plan::ScanPlan)
    errors = Dict{Symbol,String}()
    seen = Set{Symbol}()

    for ax in plan.axes
        name = axis_name(ax)
        if name in seen
            errors[name] = "Axis '$name' is defined more than once"
            continue
        end

        if ax isa DependentAxis
            if !(ax.depends_on in seen)
                errors[name] = "Axis '$name' depends on '$(ax.depends_on)', but it is missing or defined later"
            end
        elseif ax isa MultiDependentAxis
            missing = [d for d in ax.depends_on if !(d in seen)]
            if !isempty(missing)
                errors[name] = "Axis '$name' has missing/late dependencies: $(join(string.(missing), ", "))"
            end
        end

        push!(seen, name)
    end

    return errors
end

function validate_scan_text_specs(
    specs::Vector{Pair{Symbol,String}};
    fixed::AbstractVector{<:Pair}=Pair{Symbol,Any}[],
    numeric_axes::AbstractSet{Symbol}=Set{Symbol}(),
)
    errors = Dict{Symbol,String}()
    axes = ScanAxis[]

    for (name, spec) in specs
        try
            ax = parse_axis_spec(name, spec; numeric_only=(name in numeric_axes))
            ax === nothing || push!(axes, ax)
        catch e
            errors[name] = sprint(showerror, e)
        end
    end

    for (name, val) in fixed
        push!(axes, FixedAxis(name, val))
    end

    plan = ScanPlan(axes)
    merge!(errors, validate_scan_plan(plan))

    return (
        ok = isempty(errors),
        plan = isempty(errors) ? plan : nothing,
        errors = errors,
    )
end
