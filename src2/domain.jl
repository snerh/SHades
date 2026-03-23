module Domain

export Spectrum, Point

struct Spectrum
    wavelength::Vector{Float64}
    signal::Vector{Float64}
end

Point = Dict{Symbol, Any}

end