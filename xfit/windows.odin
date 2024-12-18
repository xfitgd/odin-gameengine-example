#+private
package xfit

import "core:sys/windows"
import "xmath"
import "core:math"
import "core:math/linalg"

when ODIN_OS == .Windows {
    monitor_info_windows :: struct {
        hmonitor:windows.HMONITOR
    }
} else {
    monitor_info_windows :: struct {
    }
}
