function build_legacy_scan_plan(;
    wl::Union{Nothing,AbstractVector,AbstractRange}=500.0:1.0:510.0,
    interaction::Union{Nothing,AbstractString}="SIG",
    sol_wl::Union{Nothing,AbstractVector,AbstractRange}=nothing,
    sol_from_wl::Union{Nothing,Function}=wl -> round((wl / 2) / 20) * 20,
    polarizer::Union{Nothing,AbstractVector,AbstractRange}=nothing,
    analyzer::Union{Nothing,AbstractVector,AbstractRange}=nothing,
    analyzer_from_polarizer::Union{Nothing,Function}=nothing,
    power::Union{Nothing,AbstractVector,AbstractRange}=nothing,
    acq_time::Union{Nothing,Tuple{<:Number,<:AbstractString}}=(100, "ms"),
    frames::Union{Nothing,Int}=1,
    slit::Union{Nothing,Real}=nothing,
    extra_axes::Vector{ScanAxis}=ScanAxis[],
)
    axes = ScanAxis[]

    wl_enabled = wl !== nothing
    if wl_enabled
        push!(axes, IndependentAxis(:wl, collect(wl)))
    end
    interaction !== nothing && push!(axes, FixedAxis(:inter, String(interaction)))

    if sol_wl !== nothing
        push!(axes, IndependentAxis(:sol_wl, collect(sol_wl)))
    elseif wl_enabled && sol_from_wl !== nothing
        push!(axes, DependentAxis(:sol_wl, :wl, sol_from_wl))
    end

    polarizer !== nothing && push!(axes, IndependentAxis(:polarizer, collect(polarizer)))
    if analyzer_from_polarizer !== nothing
        push!(axes, DependentAxis(:analyzer, :polarizer, analyzer_from_polarizer))
    elseif analyzer !== nothing
        push!(axes, IndependentAxis(:analyzer, collect(analyzer)))
    end
    power !== nothing && push!(axes, IndependentAxis(:power, collect(power)))

    acq_time !== nothing && push!(axes, FixedAxis(:acq_time, acq_time))
    frames !== nothing && push!(axes, FixedAxis(:frames, frames))
    slit !== nothing && push!(axes, FixedAxis(:slit, Float64(slit)))

    append!(axes, extra_axes)
    return ScanPlan(axes)
end
