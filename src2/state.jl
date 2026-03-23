module State

using ..Domain
using ..Parameters

export AppState, MeasurementDataState, DeviceRuntimeState, SessionState
export MeasurementState, PowerState

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

mutable struct MeasurementDataState
    raw_params::Vector{Pair{Symbol,String}}
    scan_params::Union{Nothing,ScanAxisSet}
    current_spectrum::Union{Nothing,Spectrum}
    points::Vector{Point}
    current_raw::Vector{Float64}
    last_saved_file::Union{Nothing,String}

    function MeasurementDataState()
        new(Pair{Symbol,String}[], nothing, nothing, Point[], Float64[], nothing)
    end
end

mutable struct DeviceRuntimeState
    current_power::Float64
    connected::Bool
    initialized::Bool
    status::String

    function DeviceRuntimeState()
        new(0.0, false, false, "devices: disconnected")
    end
end

mutable struct SessionState
    config::AppConfig

    function SessionState()
        new(AppConfig("."))
    end
end

mutable struct AppState
    measurement_state::MeasurementState
    power_state::PowerState
    measurement::MeasurementDataState
    devices::DeviceRuntimeState
    session::SessionState

    function AppState()
        new(Idle, Off, MeasurementDataState(), DeviceRuntimeState(), SessionState())
    end
end

end
