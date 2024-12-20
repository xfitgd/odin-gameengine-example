#+private
package xfit

import "core:math"
import "core:math/linalg"
import "core:sys/windows"
import "xmath"

when ODIN_OS == .Windows {
	monitor_info_windows :: struct {
		hmonitor: windows.HMONITOR,
	}
} else {
	monitor_info_windows :: struct {}
}
