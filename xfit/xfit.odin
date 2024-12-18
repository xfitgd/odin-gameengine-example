package xfit

import "core:fmt"
import "core:os"


is_android :: #config(__ANDROID__, false)
is_log :: #config(__log__, true)

LOG_FILE_NAME : string = "xfit_log.log"


xfit_main :: proc(
_init : proc(),
_update : proc(dt:f64) =  proc(dt:f64) {},
_destroy : proc() =  proc() {}
) {
    init = _init
    update = _update
    destroy = _destroy

    systemStart()
}




