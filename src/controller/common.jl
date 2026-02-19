@inline function _check_stop_or_pause!(ctrl::MeasurementControl)
    ctrl.stop && return false
    while ctrl.pause
        ctrl.stop && return false
        sleep(0.05)
    end
    return true
end
