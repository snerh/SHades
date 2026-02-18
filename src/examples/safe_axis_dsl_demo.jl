include("../SHades.jl")
using .SHades

specs = Pair{Symbol,String}[
    :wl => "500:2:506",
    :polarizer => "0,30,60",
    :analyzer => "=polarizer+10",
    :sol_wl => "=round(wl/40)*20",
]

plan = build_scan_plan_from_text_specs(specs; fixed=[:inter=>"SIG", :acq_time=>(50, "ms"), :frames=>2])

println("axes = ", length(plan.axes))
for ax in plan.axes
    println(typeof(ax), " -> ", axis_name(ax))
end
