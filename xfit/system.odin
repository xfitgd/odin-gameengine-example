package xfit

import "base:intrinsics"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:os"
import "core:io"
import "core:reflect"
import "core:thread"
import "core:sync"
import "core:strings"
import "base:runtime"
import "core:debug/trace"
import "xmath"

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

TextureFmt :: enum u32 {
    Default,
    R8G8B8A8Unorm,
    B8G8R8A8Unorm,
    B8G8R8A8Srgb,
    R8G8B8A8Srgb,
    D24UnormS8Uint,
    D32SfloatS8Uint,
    D16UnormS8Uint,
}

TextureFmt_IsDepth :: proc(t:TextureFmt) -> bool {
	#partial switch(t) {
		case .D24UnormS8Uint, .D32SfloatS8Uint, .D16UnormS8Uint:
		return true
	}
	return false
}


screenInfo :: struct {
	monitor:     ^monitorInfo,
	size:        xmath.PointU,
	refreshRate: f64,
}

monitorInfo :: struct {
	rect:       xmath.RectI,
	resolution: screenInfo,
	name:       string,
	__windows:  monitor_info_windows,
	isPrimary:  bool,
}

systemInit :: proc() {
	trace.init(&gTraceCtx)
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

systemDestroy :: proc() {
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

panicLog :: proc(args: ..any, loc := #caller_location) {
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

when !is_mobile {
	println :: fmt.println
	printfln :: fmt.printfln
	printf :: fmt.printf
	print :: fmt.print
} else when is_android {
	//TODO
} else {
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
