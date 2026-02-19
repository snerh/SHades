function stabilize_power!(
    devices::DeviceBundle;
    target_power::Float64,
    duration_s::Float64=5.0,
    interval_s::Float64=0.2,
    k_p::Float64=0.5,
    min_target::Union{Nothing,Float64}=nothing,
    max_target::Union{Nothing,Float64}=nothing
)
    t0 = time()
    log = Vector{Tuple{Float64,Float64,Float64}}()
    current_target = target_power
    set_target_power!(devices.lockin, current_target)

    while true
        now = time()
        if now - t0 > duration_s
            break
        end

        power = read_lockin_power(devices.lockin)
        err = target_power - power
        current_target = current_target + k_p * err
        if min_target !== nothing
            current_target = max(current_target, min_target)
        end
        if max_target !== nothing
            current_target = min(current_target, max_target)
        end
        set_target_power!(devices.lockin, current_target)
        push!(log, (now - t0, power, current_target))
        sleep(interval_s)
    end
    return log
end
