package xfmt

import "core:strings"
import "core:fmt"
import "core:os"
import "core:sync"
import "core:debug/trace"
import "base:runtime"

is_android :: ODIN_PLATFORM_SUBTARGET == .Android
is_mobile :: is_android
is_log :: #config(__log__, true)

LOG_FILE_NAME: string = "xfit_log.log"

Start :: proc() {
    sync.mutex_lock(&gTraceMtx)
	defer sync.mutex_unlock(&gTraceMtx)
    if started do panic("xpanic already started")
    trace.init(&gTraceCtx)
    started = true
}

Destroy :: proc() {
    sync.mutex_lock(&gTraceMtx)
	defer sync.mutex_unlock(&gTraceMtx)
    if !started do panic("xpanic not started")
    trace.destroy(&gTraceCtx)
    started = false
}

@(private) gTraceCtx: trace.Context
@(private) gTraceMtx: sync.Mutex
@(private) started: bool = false

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

	printToFile(str.buf[:len(str.buf)])
	panic(string(str.buf[:len(str.buf)]), loc)
}

@private printToFile :: proc(str:[]byte) {
	str2 := string(str)
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
}

printLog :: proc "contextless" (args: ..any) {
	context = runtime.default_context()
	str: strings.Builder
	strings.builder_init(&str)
	defer strings.builder_destroy(&str)
	fmt.sbprint(&str, ..args)

	printToFile(str.buf[:len(str.buf)])
}


printlnLog :: proc "contextless" (args: ..any) {
	context = runtime.default_context()
	str: strings.Builder
	strings.builder_init(&str)
	defer strings.builder_destroy(&str)
	fmt.sbprintln(&str, ..args)

	printToFile(str.buf[:len(str.buf)])
}

printfLog :: proc "contextless" (_fmt:string ,args: ..any) {
	context = runtime.default_context()
	str: strings.Builder
	strings.builder_init(&str)
	defer strings.builder_destroy(&str)
	fmt.sbprintf(&str, _fmt, ..args)

	printToFile(str.buf[:len(str.buf)])
}

printflnLog :: proc "contextless" (_fmt:string ,args: ..any) {
	context = runtime.default_context()
	str: strings.Builder
	strings.builder_init(&str)
	defer strings.builder_destroy(&str)
	fmt.sbprintfln(&str, _fmt, ..args)

	printToFile(str.buf[:len(str.buf)])
}
