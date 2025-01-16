package xfit

import "base:intrinsics"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:os"
import "core:mem"
import "core:mem/virtual"
import "core:io"
import "core:time"
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
@(private) loopStart := false
@(private) maxFrame : f64
@(private) deltaTime : u64

Exiting :: #force_inline proc  "contextless"() -> bool {return exiting}
dt :: #force_inline proc "contextless" () -> f64 { return f64(deltaTime) / 1000000000.0 }
dt_u64 :: #force_inline proc "contextless" () -> u64 { return deltaTime }

Init: proc()
Update: proc()
Destroy: proc()
Activate: proc "contextless" () = proc "contextless" () {}
Close: proc "contextless" () -> bool = proc "contextless" () -> bool{ return true }

AndroidAPILevel :: enum u32 {
	Nougat = 24,
	Nougat_MR1 = 25,
	Oreo = 26,
	Oreo_MR1 = 27,
	Pie = 28,
	Q = 29,
	R = 30,
	S = 31,
	S_V2 = 32,
	Tiramisu = 33,
	UpsideDownCake = 34,
	VanillaIceCream = 35,
	Baklava = 36,
	Unknown = 0,
}

WindowsVersion :: enum {
	Windows7,
	WindowsServer2008R2,
	Windows8,
	WindowsServer2012,
	Windows8Point1,
	WindowsServer2012R2,
	Windows10,
	WindowsServer2016,
	Windows11,
	WindowsServer2019,
	WindowsServer2022,
	Unknown,
}

WindowsPlatformVersion :: struct {
	version:WindowsVersion,
	buildNumber:u32,
	servicePack:u32,
}
AndroidPlatformVersion :: struct {
	apiLevel:AndroidAPILevel,
}
LinuxPlatformVersion :: struct {
	sysName:string,
	nodeName:string,
	release:string,
	version:string,
	machine:string,
}

when is_android {
	@(private) androidPlatform:AndroidPlatformVersion
	GetPlatformVersion :: #force_inline proc "contextless" () -> AndroidPlatformVersion {
		return androidPlatform
	}
} else when ODIN_OS == .Linux {
	@(private) linuxPlatform:LinuxPlatformVersion
	GetPlatformVersion :: #force_inline proc "contextless" () -> LinuxPlatformVersion {
		return linuxPlatform
	}
} else when ODIN_OS == .Windows {
	@(private) windowsPlatform:WindowsPlatformVersion
	GetPlatformVersion :: #force_inline proc "contextless" () -> WindowsPlatformVersion {
		return windowsPlatform
	}
}

@(private) __depthFmt:TextureFmt
@(private) __swapImgCnt:u32 = 3

is_android :: #config(__ANDROID__, false)
is_mobile :: is_android
is_log :: #config(__log__, true)

@(private="file") inited := false

LOG_FILE_NAME: string = "xfit_log.log"


xfitInit :: proc() {
	systemInit()
	inited = true
}

xfitMain :: proc(
	_windowTitle:cstring = "xfit",
	_windowX:Maybe(i32) = nil,
	_windowY:Maybe(i32) = nil,
	_windowWidth:Maybe(u32) = nil,
	_windowHeight:Maybe(u32) = nil,
) {
	if(!inited) do panic("call xfitInit first!")

	__windowTitle = _windowTitle
	__windowX = _windowX
	__windowY = _windowY
	__windowWidth = _windowWidth
	__windowHeight = _windowHeight

	systemStart()
}

systemInit :: proc() {
	trace.init(&gTraceCtx)
	monitors = make([dynamic]MonitorInfo)
	when is_android {
		//TODO
	} else {
		glfwSystemInit()
	}
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
		glfwDestroy()
		glfwSystemDestroy()
	}
}
systemAfterDestroy :: proc() {
	trace.destroy(&gTraceCtx)
	delete(monitors)
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

@(private) CreateRenderFuncThread :: proc() {
	render_th = thread.create(RenderFunc)
}

@(private) RenderFunc :: proc(_: ^thread.Thread) {
	vkStart()

	Init()

	for !exiting {
		RenderLoop()
	}

	vkWaitDeviceIdle()

	Destroy()

	vkDestory()
}

@(private) RenderLoop :: proc() {
	@static start:time.Time
	@static now:time.Time
	Paused_ := Paused()

	if !loopStart {
		loopStart = true
		start = time.now()
		now = start
	} else {
		maxFrame_ := GetMaxFrame()
		if Paused_ && maxFrame_ == 0 {
			maxFrame_ = 60
		}
		n := time.now()
		delta := n._nsec - now._nsec

		if maxFrame_ > 0 {
			maxF := u64(1 * (1 / maxFrame_)) * 1000000000
			if maxF > auto_cast delta {
				time.sleep(auto_cast (i64(maxF) - delta))
				n = time.now()
				delta = n._nsec - now._nsec
			}
		}
		now = n
		deltaTime = auto_cast delta
	}
	Update()

	if !Paused_ {
		vkDrawFrame()
	}
}

GetMaxFrame :: #force_inline proc "contextless" () -> f64 {
	return intrinsics.atomic_load_explicit(&maxFrame,.Relaxed)
}

SetMaxFrame :: #force_inline proc "contextless" (_maxframe: f64) {
	intrinsics.atomic_store_explicit(&maxFrame, _maxframe, .Relaxed)
}

//_int * 1000000000 + _dec
SecondToNanoSecond :: #force_inline proc "contextless" (_int: $T, _dec: T) -> T where intrinsics.type_is_integer(T) {
    return _int * 1000000000 + _dec
}

SecondToNanoSecond2 :: #force_inline proc "contextless" (_sec: $T, _milisec: T, _usec: T, _nsec: T) -> T where intrinsics.type_is_integer(T) {
    return _sec * 1000000000 + _milisec * 1000000 + _usec * 1000 + _nsec
}