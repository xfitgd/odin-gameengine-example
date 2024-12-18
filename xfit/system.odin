package xfit

import "core:math"
import "core:os"
import "core:fmt"
import "core:thread"
import "core:math/linalg"
import "xmath"

@private render_th:thread.Thread
@private monitors:[dynamic]monitorInfo
@private primaryMonitor:^monitorInfo

init : proc()
update : proc(dt:f64)
destroy : proc()
activate : proc() = proc() {}


screenInfo :: struct {
    monitor : ^monitorInfo,
    size : xmath.pointu,
    refreshRate: f64,
}

monitorInfo :: struct {
    rect:xmath.recti,
    resolution:screenInfo,
    name:string,
    __windows:monitor_info_windows,
    isPrimary:bool
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

panicLog ::proc(_err:any, expr := #caller_expression(_err), loc := #caller_location) {
    when !is_android  {
        if len(LOG_FILE_NAME) > 0 {
            fd, err := os.open(LOG_FILE_NAME, os.O_WRONLY | os.O_CREATE | os.O_APPEND, 0o644)
            if err == nil {          
                defer os.close(fd)
                fmt.fprintln(fd, expr)
                fmt.fprintln(fd, loc)
                fmt.fprintln(fd, #procedure, "called by", loc.procedure)
                fmt.fprintln(fd,"-------------------------------------------------")
            }
        }
    }
    panic(expr, loc)
}

@private renderFunc :: proc() {
    
}