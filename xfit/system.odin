package xfit

import "core:math"
import "core:os"
import "core:fmt"
import "core:thread"
import "core:math/linalg"
import "xmath"

__ANDROID__ :: #config(__ANDROID__, false)
__log__ :: #config(__log__, true)

LOG_FILE_NAME : string = "xfit_log.log"



@private render_th:thread.Thread
@private monitors:[dynamic]monitor_info
@private primaryMonitor:^monitor_info

init : proc()
update : proc(dt:f64)
destroy : proc()
activate : proc() = proc() {}



screen_info :: struct {
    monitor : ^monitor_info,
    size : xmath.pointu,
    refreshRate: f64,
}

monitor_info :: struct {
    rect:xmath.recti,
    resolution:screen_info,
    name:string,
    __windows:monitor_info_windows,
    isPrimary:bool
}

system_start :: proc() {
    when ODIN_OS == .Linux {
        systemLinuxStart()
    } else when ODIN_OS == .Windows {
        systemWindowsStart()
    } else {
        #panic("not support platform")
    }
}

panic_log ::proc(_err:any, expr := #caller_expression(_err), loc := #caller_location) {
    when ! __ANDROID__  {
        fd, err := os.open(LOG_FILE_NAME, os.O_WRONLY | os.O_CREATE | os.O_APPEND, 0o644)
        if err == nil {
            
            defer os.close(fd)
            fmt.fprintln(fd, expr)
            fmt.fprintln(fd, loc)
            fmt.fprintln(fd, #procedure, "called by", loc.procedure)
            fmt.fprintln(fd,"-------------------------------------------------")
        }
    }
    panic(expr, loc)
}