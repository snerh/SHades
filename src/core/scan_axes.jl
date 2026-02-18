abstract type ScanAxis end

struct IndependentAxis{T} <: ScanAxis
    name::Symbol
    values::Vector{T}
end

IndependentAxis(name::Symbol, values) = IndependentAxis(name, collect(values))

struct FixedAxis{T} <: ScanAxis
    name::Symbol
    value::T
end

struct DependentAxis{F} <: ScanAxis
    name::Symbol
    depends_on::Symbol
    f::F
end

struct MultiDependentAxis{F} <: ScanAxis
    name::Symbol
    depends_on::Vector{Symbol}
    f::F
end

struct LoopAxis <: ScanAxis
    name::Symbol
    start::Int
    step::Int
    stop::Union{Nothing,Int}
end

LoopAxis(; name::Symbol=:loop, start::Int=1, step::Int=1, stop::Union{Nothing,Int}=nothing) = LoopAxis(name, start, step, stop)

struct ScanPlan
    axes::Vector{ScanAxis}
end

ScanPlan(axes::ScanAxis...) = ScanPlan(collect(axes))

axis_name(ax::ScanAxis) = ax.name

function has_axis(plan::ScanPlan, name::Symbol)
    any(ax -> axis_name(ax) == name, plan.axes)
end

function legacy_axes_to_plan(p_init)
    axes = ScanAxis[]
    for (k, v) in p_init
        if k == :loop
            push!(axes, LoopAxis(name=:loop, start=Int(v), step=1, stop=nothing))
        elseif v isa AbstractRange || v isa AbstractVector
            push!(axes, IndependentAxis(k, collect(v)))
        elseif v isa Tuple && length(v) == 2 && v[1] isa Symbol && v[2] isa Function
            push!(axes, DependentAxis(k, v[1], v[2]))
        else
            push!(axes, FixedAxis(k, v))
        end
    end
    return ScanPlan(axes)
end
