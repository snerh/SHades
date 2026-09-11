using PackageCompiler

project = dirname(@__DIR__)

create_sysimage(
    [:SHades];
    project = project,
    sysimage_path = joinpath(project, "SHades.so"),
    precompile_statements_file =
        joinpath(project, "precompile", "trace.jl"),
)