package xfit

import "core:fmt"
import "core:os"


is_android :: #config(__ANDROID__, false)
is_mobile :: is_android
is_log :: #config(__log__, true)

when ODIN_DEBUG {
@(private="file") inited := false
}

LOG_FILE_NAME: string = "xfit_log.log"


xfitInit :: proc() {
	systemInit()
	when ODIN_DEBUG {
		inited = true;
	}
}

xfitMain :: proc(
	_Init: proc(),
	_Update: proc(dt: f64) = proc(dt: f64) {},
	_Destroy: proc() = proc() {},
) {
	when ODIN_DEBUG {
		if(!inited) do panic("call xfitInit first!")
	}
	Init = _Init
	Update = _Update
	Destroy = _Destroy

	systemStart()
}
