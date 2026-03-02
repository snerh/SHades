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
    points::Vector{Point}
    current_raw::Vector{Float64}
    current_power::Float64
    last_saved_file::Union{Nothing,String}
    devices_connected::Bool
    devices_initialized::Bool
    device_status::String

    app_config::AppConfig

    function AppState()
        new(Idle, Off, Pair{Symbol,String}[], nothing, nothing, Point[], Float64[], 0.0, nothing, false, false, "devices: disconnected", AppConfig("."))
    end
end

end
