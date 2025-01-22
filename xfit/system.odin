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
import "xpanic"

@(private) render_th: ^thread.Thread

@(private) exiting := false
@(private) programStart := true
@(private) loopStart := false
@(private) maxFrame : f64
@(private) deltaTime : u64
@(private) processorCoreLen : uint

printTrace :: xpanic.printTrace
printTraceBuf :: xpanic.printTraceBuf
panicLog :: xpanic.panicLog

Exiting :: #force_inline proc  "contextless"() -> bool {return exiting}
dt :: #force_inline proc "contextless" () -> f64 { return f64(deltaTime) / 1000000000.0 }
dt_u64 :: #force_inline proc "contextless" () -> u64 { return deltaTime }
GetProcessorCoreLen :: #force_inline proc "contextless" () -> uint { return processorCoreLen }

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
	xpanic.Start()
	monitors = make_non_zeroed([dynamic]MonitorInfo)
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
	xpanic.Destroy()
	delete(monitors)
}

@private @thread_local trackAllocator:mem.Tracking_Allocator

StartTrackingAllocator :: proc() {
	when ODIN_DEBUG {
		mem.tracking_allocator_init(&trackAllocator, context.allocator)
		context.allocator = mem.tracking_allocator(&trackAllocator)
	}
}

DestroyTrackAllocator :: proc() {
	when ODIN_DEBUG {
		if len(trackAllocator.allocation_map) > 0 {
			fmt.eprintf("=== %v allocations not freed: ===\n", len(trackAllocator.allocation_map))
			for _, entry in trackAllocator.allocation_map {
				fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
			}
		}
		if len(trackAllocator.bad_free_array) > 0 {
			fmt.eprintf("=== %v incorrect frees: ===\n", len(trackAllocator.bad_free_array))
			for entry in trackAllocator.bad_free_array {
				fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
			}
		}
		mem.tracking_allocator_destroy(&trackAllocator)
	}
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

make_non_zeroed :: proc {
	make_non_zeroed_slice,
	make_non_zeroed_dynamic_array,
	make_non_zeroed_dynamic_array_len,
	make_non_zeroed_dynamic_array_len_cap,

	//make_non_zeroed_map,
	//make_non_zeroed_map_cap, //?no required
	make_non_zeroed_multi_pointer,

	//TODO
	// make_non_zeroed_soa_slice,
	// make_non_zeroed_soa_dynamic_array,
	// make_non_zeroed_soa_dynamic_array_len,
	// make_non_zeroed_soa_dynamic_array_len_cap,
}

@(require_results)
make_non_zeroed_slice :: proc($T: typeid/[]$E, #any_int len: int, allocator := context.allocator, loc := #caller_location) -> (T, runtime.Allocator_Error) #optional_allocator_error {
	runtime.make_slice_error_loc(loc, len)
	data, err := runtime.mem_alloc_non_zeroed(size_of(E)*len, align_of(E), allocator, loc)
	if data == nil && size_of(E) != 0 {
		return nil, err
	}
	s := runtime.Raw_Slice{raw_data(data), len}
	return transmute(T)s, err
}

@(require_results)
make_non_zeroed_dynamic_array :: proc($T: typeid/[dynamic]$E, allocator := context.allocator, loc := #caller_location) -> (T, runtime.Allocator_Error) #optional_allocator_error {
	return make_dynamic_array_len_cap(T, 0, 0, allocator, loc)
}

@(require_results)
make_non_zeroed_dynamic_array_len :: proc($T: typeid/[dynamic]$E,  #any_int len: int, allocator := context.allocator, loc := #caller_location) -> (T, runtime.Allocator_Error) #optional_allocator_error {
	return make_dynamic_array_len_cap(T, len, len, allocator, loc)
}

@(require_results)
make_non_zeroed_dynamic_array_len_cap :: proc($T: typeid/[dynamic]$E, #any_int len: int, #any_int cap: int, allocator := context.allocator, loc := #caller_location) -> (array: T, err: runtime.Allocator_Error) #optional_allocator_error {
	runtime.make_dynamic_array_error_loc(loc, 0, 0)

	raw_array := (^runtime.Raw_Dynamic_Array)(&array)

	raw_array.allocator = allocator // initialize allocator before just in case it fails to allocate any memory
	data := runtime.mem_alloc_non_zeroed(size_of(E) * cap, align_of(E), allocator, loc) or_return
	use_zero := data == nil /*&& size_of(E) != 0*/
	raw_array.data = raw_data(data)
	raw_array.len = 0 if use_zero else len
	raw_array.cap = 0 if use_zero else cap
	raw_array.allocator = allocator
	return
}

@(require_results)
make_non_zeroed_multi_pointer :: proc($T: typeid/[^]$E, #any_int len: int, allocator := context.allocator, loc := #caller_location) -> (mp: T, err: runtime.Allocator_Error) #optional_allocator_error {
	runtime.make_slice_error_loc(loc, len)
	data := runtime.mem_alloc_non_zeroed(size_of(E)*len, align_of(E), allocator, loc) or_return
	if data == nil && size_of(E) != 0 {
		return
	}
	mp = cast(T)raw_data(data)
	return
}