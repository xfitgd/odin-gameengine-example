package xfit

import "base:intrinsics"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:os"
import "core:mem"
import "core:mem/virtual"
import "core:io"
import "core:reflect"
import "core:thread"
import "core:sync"
import "core:strings"
import "base:runtime"
import "core:debug/trace"

@(private) render_th: ^thread.Thread

@(private) exiting := false
@(private) gTraceCtx: trace.Context
@(private) programStart := true

Exiting :: proc() -> bool {return exiting}

Init: proc()
Update: proc(dt: f64)
Destroy: proc()
Activate: proc() = proc() {}

@(private) __depthFmt:TextureFmt
@(private) __swapImgCnt:u32 = 3

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

screenInfo :: struct {
	monitor:     ^monitorInfo,
	size:        PointU,
	refreshRate: f64,
}

monitorInfo :: struct {
	rect:       RectI,
	resolution: screenInfo,
	name:       string,
	__windows:  monitor_info_windows,
	isPrimary:  bool,
}

systemInit :: proc() {
	trace.init(&gTraceCtx)
}

systemStart :: proc() {
	when is_android {
		//TODO
	} else {
		glfwSystemStart()
	}
}

systemDestroy :: proc() {
	when is_android {
		//TODO
	} else {
		glfwSystemDestroy()
	}
}
systemAfterDestroy :: proc() {
	trace.destroy(&gTraceCtx)
}

gTraceMtx: sync.Mutex
printTrace :: proc() {
	sync.mutex_lock(&gTraceMtx)
	defer sync.mutex_unlock(&gTraceMtx)
	if !trace.in_resolve(&gTraceCtx) {
		buf: [64]trace.Frame
		frames := trace.frames(&gTraceCtx, 1, buf[:])
		for f, i in frames {
			fl := trace.resolve(&gTraceCtx, f, context.temp_allocator)
			if fl.loc.file_path == "" && fl.loc.line == 0 do continue
			fmt.printf("%s\n%s called by %s - frame %d\n",
				fl.loc, fl.procedure, fl.loc.procedure, i)
		}
	}
	fmt.printf("-------------------------------------------------\n")
}
printTraceBuf :: proc(str:^strings.Builder) {
	sync.mutex_lock(&gTraceMtx)
	defer sync.mutex_unlock(&gTraceMtx)
	if !trace.in_resolve(&gTraceCtx) {
		buf: [64]trace.Frame
		frames := trace.frames(&gTraceCtx, 1, buf[:])
		for f, i in frames {
			fl := trace.resolve(&gTraceCtx, f, context.temp_allocator)
			if fl.loc.file_path == "" && fl.loc.line == 0 do continue
			fmt.sbprintf(str,"%s\n%s called by %s - frame %d\n",
				fl.loc, fl.procedure, fl.loc.procedure, i)
		}
	}
	fmt.sbprintln(str, "-------------------------------------------------\n")
}
@(cold) panicLog :: proc "contextless" (args: ..any, loc := #caller_location) -> ! {
	context = runtime.default_context()
	str: strings.Builder
	strings.builder_init(&str)
	fmt.sbprintln(&str,..args)
	fmt.sbprintf(&str,"%s\n%s called by %s\n",
		loc,
		#procedure,
		loc.procedure)

	printTraceBuf(&str)

	str2 := string(str.buf[:len(str.buf)])
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

when is_android {
	//TODO
} else {
	println :: fmt.println
	printfln :: fmt.printfln
	printf :: fmt.printf
	print :: fmt.print
}

@(private) createRenderFuncThread :: proc() {
	render_th = thread.create(renderFunc)
}

@(private) renderFunc :: proc(_: ^thread.Thread) {
	vulkanStart()

	Init()

	for !exiting {
		loop()
	}

	//TODO vulkan wait

	Destroy()

	//TODO vulkan destroy
}

@(private) loop :: proc() {

}
