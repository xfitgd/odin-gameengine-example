package xfit

import "core:fmt"
import "core:os"

is_android :: __ANDROID__


xfit_main :: proc(
_init : proc(),
_update : proc(dt:f64) =  proc(dt:f64) {},
_destroy : proc() =  proc() {}
) {
    init = _init
    update = _update
    destroy = _destroy

    system_start()
}




