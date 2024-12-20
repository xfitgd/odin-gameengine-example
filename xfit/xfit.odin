package xfit

import "core:fmt"
import "core:os"


is_android :: #config(__ANDROID__, false)
is_log :: #config(__log__, true)

LOG_FILE_NAME: string = "xfit_log.log"


XfitMain :: proc(
	_Init: proc(),
	_Update: proc(dt: f64) = proc(dt: f64) {},
	_Destroy: proc() = proc() {},
) {
	Init = _Init
	Update = _Update
	Destroy = _Destroy

	systemStart()
}
