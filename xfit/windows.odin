#+private
package xfit

import "core:math"
import "core:math/linalg"
import "core:sys/windows"

when ODIN_OS == .Windows {
	monitor_info_windows :: struct {
		hmonitor: windows.HMONITOR,
	}
} else {
	monitor_info_windows :: struct {}
}
