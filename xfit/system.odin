package xfit

import "base:intrinsics"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:os"
import "core:reflect"
import "core:thread"
import "xmath"

@(private)
render_th: ^thread.Thread
@(private)
monitors: [dynamic]monitorInfo
@(private)
primaryMonitor: ^monitorInfo

@(private)
exiting := false

Exiting :: proc() -> bool {return exiting}

Init: proc()
Update: proc(dt: f64)
Destroy: proc()
Activate: proc() = proc() {}


screenInfo :: struct {
	monitor:     ^monitorInfo,
	size:        xmath.pointu,
	refreshRate: f64,
}

monitorInfo :: struct {
	rect:       xmath.recti,
	resolution: screenInfo,
	name:       string,
	__windows:  monitor_info_windows,
	isPrimary:  bool,
}

systemStart :: proc() {
	when ODIN_OS == .Linux {
		systemLinuxStart()
	} else when ODIN_OS == .Windows {
		systemWindowsStart()
	} else {
		#panic("not support platform")
	}
}

panicLog :: proc(args: ..any, loc := #caller_location) {
	str := fmt.aprint(..args)
	str2 := fmt.aprintf(
		"%s%s\n%s called by %s\n-------------------------------------------------\n",
		str,
		loc,
		#procedure,
		loc.procedure,
	)

	when !is_android {
		if len(LOG_FILE_NAME) > 0 {
			fd, err := os.open(LOG_FILE_NAME, os.O_WRONLY | os.O_CREATE | os.O_APPEND, 0o644)
			if err == nil {
				defer os.close(fd)
				fmt.fprint(fd, str2)
			}
		}
	} else {
		//TODO
	}

	panic(str2, loc)
}

when !is_android {
	println :: fmt.println
	printfln :: fmt.printfln
	printf :: fmt.printf
	print :: fmt.print
} else {
	//TODO
}

@(private)
createRenderFuncThread :: proc() {
	render_th = thread.create(renderFunc)
}

@(private)
renderFunc :: proc(_: ^thread.Thread) {
	vulkanStart()

	Init()

	for !exiting {
		loop()
	}

	//TODO vulkan wait

	Destroy()

	//TODO vulkan destroy
}

@(private)
loop :: proc() {

}
