module AppEvents

using ..DeviceManager: SystemEvent
using ..Domain: Point

export SyncRawParams, SetDeviceLifecycle, DirectoryLoaded

struct SyncRawParams <: SystemEvent
    values::Vector{Pair{Symbol,String}}
end

struct DirectoryLoaded <: SystemEvent
    dir::String
    points::Vector{Point}
end

struct SetDeviceLifecycle <: SystemEvent
    connected::Bool
    initialized::Bool
    message::String
end

end
