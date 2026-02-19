using Test

include(joinpath(@__DIR__, "..", "src", "SHades.jl"))
using .SHades

@testset "Axis parser" begin
    ax = parse_axis_spec(:wl, "500:2:504"; numeric_only=true)
    @test ax isa IndependentAxis
    @test ax.values == [500.0, 502.0, 504.0]

    dax = parse_axis_spec(:sol_wl, "=round(wl/40)*20"; numeric_only=true)
    @test dax isa DependentAxis
    @test dax.depends_on == :wl
    @test dax.f(503.0) == 260.0
end

@testset "Validation" begin
    vr_bad = validate_scan_text_specs([
        :sol_wl => "=wl/2",
        :wl => "500:2:504",
    ]; numeric_axes=Set([:wl, :sol_wl]))
    @test !vr_bad.ok
    @test haskey(vr_bad.errors, :sol_wl)

    vr_ok = validate_scan_text_specs([
        :wl => "500:2:504",
        :sol_wl => "=wl/2",
    ]; numeric_axes=Set([:wl, :sol_wl]))
    @test vr_ok.ok
    @test vr_ok.plan isa ScanPlan
end

@testset "ScanPoint" begin
    p = scan_point_from_params(Dict{Symbol,Any}(
        :wl => 500,
        :sig => 12.5,
        :real_power => "1.2",
        :time_s => 0.05,
    ))
    @test isapprox(scan_point_axis(p, :wl), 500.0)
    @test isapprox(scan_point_axis(p, :sig), 12.5)
    @test isapprox(scan_point_axis(p, :real_power), 1.2)

    d = scan_point_to_dict(p)
    @test d[:wl] == 500.0
    @test d[:sig] == 12.5
    @test d[:time_s] == 0.05
end

@testset "Dataset IO" begin
    mktempdir() do d
        path = joinpath(d, "sample.dat")
        params = Dict{Symbol,Any}(
            :wl => 500.0,
            :time_s => 0.025,
        )
        data = [1.0, 3.0, 2.0]

        save_dat_file(path, params, data)
        p2, d2 = read_dat_file(path)

        @test d2 == data
        @test isapprox(p2[:time_s], 0.025)
        @test isapprox(p2[:sig], 1.0)
        @test p2[:wl] == 500.0
    end
end

@testset "Presets (TOML)" begin
    mktempdir() do d
        p = ScanParams(
            wavelengths=[500.0, 502.0],
            interaction="SIG",
            acq_time_s=0.05,
            frames=2,
            delay_s=0.1,
            sol_divider=2.0,
            fixed_sol_wavelength=250.0,
            polarizer_deg=20.0,
            analyzer_deg=30.0,
            target_power=1.1,
            camera_temp_c=-10.0,
        )
        preset_path = joinpath(d, "preset.toml")
        save_preset(preset_path, p)
        p2 = load_preset(preset_path)

        @test p2.wavelengths == p.wavelengths
        @test p2.interaction == p.interaction
        @test p2.frames == p.frames
        @test isapprox(p2.acq_time_s, p.acq_time_s)
        @test isapprox(p2.fixed_sol_wavelength, 250.0)
        @test isapprox(p2.target_power, 1.1)

        state = Dict{String,Any}(
            "wl_spec" => "500:2:504",
            "plot_mode" => "line",
            "plot_log" => false,
            "stab_kp" => 0.5,
        )
        state_path = joinpath(d, "state.toml")
        save_preset_state(state_path, state)
        s2 = load_preset_state(state_path)

        @test s2["wl_spec"] == state["wl_spec"]
        @test s2["plot_mode"] == state["plot_mode"]
        @test s2["plot_log"] == state["plot_log"]
        @test isapprox(Float64(s2["stab_kp"]), 0.5)
    end
end
