module State

using ..Domain
using ..Parameters

export AppState, MeasurementState, PowerState

# Measurement state machine 
@enum MeasurementState begin
    Idle
    Preparing
    Running
    Paused
    Stopping
    Finished
    Error
end

# Power stabilizing state machine
@enum PowerState begin
    Off
    Stabilizing
    ErrorPower
end

mutable struct AppConfig
    dir::String
end

mutable struct AppState
    measurement_state::MeasurementState
    power_state::PowerState

    raw_params::Vector{Pair{Symbol,String}}
    scan_params::Union{Nothing,ScanAxisSet}
    current_spectrum::Union{Nothing,Spectrum}
    current_power::Float64

    app_config::AppConfig

    function AppState()
        new(Idle, Off, Pair{Symbol,String}[], nothing, nothing, 0.0, AppConfig("."))
    end
end

end
