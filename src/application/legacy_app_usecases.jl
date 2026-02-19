Base.@kwdef struct LegacyFormData
    wl_spec::String = ""
    sol_spec::String = ""
    pol_spec::String = ""
    ana_spec::String = ""
    power_spec::String = ""
    cam_temp::String = ""
    inter::String = "SIG"
    acq_ms::String = "50"
    frames::String = "1"
    delay_s::String = "0.01"
    out_dir::String = ""
    stab_duration_s::Float64 = 5.0
    stab_kp::Float64 = 0.5
end

const _LEGACY_NUMERIC_AXES = Set([:wl, :sol_wl, :polarizer, :analyzer, :power])

function _safe_parse_int(s::AbstractString, d::Int)
    try
        parse(Int, strip(s))
    catch
        d
    end
end

function _safe_parse_float(s::AbstractString, d::Float64)
    try
        parse(Float64, replace(strip(s), "," => "."))
    catch
        d
    end
end

function _opt_float_text(txt::AbstractString)::Union{Nothing,Float64}
    st = strip(txt)
    isempty(st) && return nothing
    return _safe_parse_float(st, NaN)
end

function _axis_first_value(name::Symbol, spec::AbstractString; wl::Union{Nothing,Float64}=nothing)
    ax = parse_axis_spec(name, spec; numeric_only=true)
    ax === nothing && return nothing
    if ax isa FixedAxis
        return Float64(ax.value)
    elseif ax isa IndependentAxis
        isempty(ax.values) && return nothing
        return Float64(ax.values[1])
    elseif ax isa DependentAxis
        ax.depends_on == :wl || error("Dependent axis '$name' requires '$(ax.depends_on)'")
        wl === nothing && error("Dependent axis '$name' needs wl")
        return Float64(ax.f(wl))
    else
        error("Axis '$name' is not supported for focus mode")
    end
end

function build_run_request(data::LegacyFormData)
    specs = Pair{Symbol,String}[]
    spec_order = (
        :wl => data.wl_spec,
        :sol_wl => data.sol_spec,
        :polarizer => data.pol_spec,
        :analyzer => data.ana_spec,
        :power => data.power_spec,
    )
    for (sym, txt) in spec_order
        t = strip(txt)
        isempty(t) || push!(specs, sym => t)
    end

    inter_txt = strip(data.inter)
    inter_txt = isempty(inter_txt) ? "SIG" : inter_txt

    fixed = Pair{Symbol,Any}[
        :inter => inter_txt,
        :acq_time => (max(_safe_parse_int(data.acq_ms, 50), 1), "ms"),
        :frames => max(_safe_parse_int(data.frames, 1), 1),
    ]

    vr = validate_scan_text_specs(specs; fixed=fixed, numeric_axes=_LEGACY_NUMERIC_AXES)
    if !vr.ok
        return (
            ok = false,
            plan = nothing,
            errors = vr.errors,
            delay_s = 0.0,
            output_dir = nothing,
            camera_temp_c = nothing,
        )
    end

    dly = max(_safe_parse_float(data.delay_s, 0.01), 0.0)
    out_dir = strip(data.out_dir)
    out = isempty(out_dir) ? nothing : out_dir

    return (
        ok = true,
        plan = vr.plan,
        errors = Dict{Symbol,String}(),
        delay_s = dly,
        output_dir = out,
        camera_temp_c = _opt_float_text(data.cam_temp),
    )
end

function build_focus_params(data::LegacyFormData; require_wl::Bool=false)
    wl_txt = strip(data.wl_spec)
    wl_val = _axis_first_value(:wl, wl_txt)
    (wl_val === nothing && require_wl) && error("wl spec is empty")
    wl_val === nothing && (wl_val = 0.0)

    sol_txt = strip(data.sol_spec)
    sol_val = isempty(sol_txt) ? nothing : _axis_first_value(:sol_wl, sol_txt; wl=wl_val)

    inter_txt = strip(data.inter)
    inter_txt = isempty(inter_txt) ? "SIG" : inter_txt

    acq_s = max(_safe_parse_int(data.acq_ms, 50), 1) / 1000
    fr = max(_safe_parse_int(data.frames, 1), 1)
    dly = max(_safe_parse_float(data.delay_s, 0.01), 0.0)
    pol = _safe_parse_float(data.pol_spec, 0.0)
    ana = _safe_parse_float(data.ana_spec, 0.0)
    ct = _opt_float_text(data.cam_temp)

    return ScanParams(
        wavelengths=[wl_val],
        interaction=inter_txt,
        acq_time_s=acq_s,
        frames=fr,
        delay_s=dly,
        fixed_sol_wavelength=sol_val,
        polarizer_deg=pol,
        analyzer_deg=ana,
        camera_temp_c=ct,
    )
end

function build_stabilize_request(data::LegacyFormData)
    tgt = _axis_first_value(:power, strip(data.power_spec))
    tgt === nothing && error("power spec is empty")
    return (
        target_power = Float64(tgt),
        duration_s = Float64(data.stab_duration_s),
        k_p = Float64(data.stab_kp),
    )
end
