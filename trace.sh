#!/bin/sh
julia --project=. --trace-compile=precompile/trace.jl precompile/workload.jl
