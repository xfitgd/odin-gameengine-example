// #+private
package xfit

// import "base:intrinsics"
// import "core:c"
// import "core:fmt"
// import "core:math"
// import "core:math/linalg"
// import "core:strings"
// import vk "vendor:vulkan"
// import "vendor:x11/xlib"

// display: ^xlib.Display
// defScreenIdx := 0
// wnd: xlib.Window
// delWnd: xlib.Atom
// stateWnd: xlib.Atom
// wndExtent: [4]c.long
// rootWnd: xlib.Window


// _NET_WM_STATE_TOGGLE :: 2

// systemLinuxStart :: proc() {
// 	if display = xlib.OpenDisplay(nil); display == nil do panic("")

// 	rootWnd = xlib.DefaultRootWindow(display)

// 	screen_res := xlib.XRRGetScreenResources(display, rootWnd)
// 	defer xlib.XRRFreeScreenResources(screen_res)

// 	le := math.min(screen_res.ncrtc, screen_res.noutput)
// 	for i in 0 ..< le {
// 		crtc_info := xlib.XRRGetCrtcInfo(display, screen_res, screen_res.crtcs[i])
// 		output := xlib.XRRGetOutputInfo(display, screen_res, screen_res.outputs[i])
// 		defer xlib.XRRFreeCrtcInfo(crtc_info)
// 		defer xlib.XRRFreeOutputInfo(output)

// 		mode_: ^xlib.XRRModeInfo = nil
// 		for k in 0 ..< screen_res.nmode {
// 			if output.modes[0] == screen_res.modes[k].id {
// 				mode_ = &screen_res.modes[k]
// 				break
// 			}
// 		}
// 		if mode_ == nil do continue
// 		append(
// 			&monitors,
// 			monitorInfo {
// 				isPrimary = i == i32(defScreenIdx),
// 				rect = Rect_Init(
// 					[2]i32{crtc_info.x, crtc_info.y},
// 					[2]i32{i32(crtc_info.width), i32(crtc_info.height)},
// 				),
// 			},
// 		)

// 		last := &monitors[len(monitors) - 1]
// 		if last.isPrimary do primaryMonitor = last

// 		last.name = strings.clone(string(output.name))

// 		when is_log {
// 			printf(
// 				"XFIT SYSLOG : %smonitor %d name: %s, x:%d, y:%d, width:%d, height:%d [\n",
// 				"primary" if last.isPrimary else "",
// 				i,
// 				last.name,
// 				crtc_info.x,
// 				crtc_info.y,
// 				crtc_info.width,
// 				crtc_info.height,
// 			)
// 		}
// 		hz := f64(mode_.dotClock) / f64(mode_.hTotal * mode_.vTotal)
// 		when is_log {
// 			printf(
// 				"monitor %d resolution: width:%d, height:%d refleshrate %f\n]\n",
// 				i,
// 				mode_.width,
// 				mode_.height,
// 				hz,
// 			)
// 		}
// 		last.refreshRate = hz
// 	}
// }

// setWndSizeHint :: proc(first_call: bool) {

// }

// linuxGetMonitorFromWindow :: proc() -> ^monitorInfo #no_bounds_check {
// 	for &value in monitors {
// 		if Rect_PointIn(value.rect, [2]i32{__windowX.?, __windowY.?}) do return &value
// 	}
// 	return primaryMonitor
// }

// linuxSendFullScreenEvent :: proc(toggle: bool) {
// 	evt: xlib.XEvent
// 	evt.type = xlib.EventType.ClientMessage
// 	evt.xclient.window = wnd
// 	evt.xclient.message_type = xlib.InternAtom(display, "_NET_WM_STATE", true)
// 	evt.xclient.format = 32
// 	evt.xclient.data.l[0] = int(toggle)
// 	evt.xclient.data.l[1] = int(xlib.InternAtom(display, "_NET_WM_STATE_FULLSCREEN", true))
// 	evt.xclient.data.l[2] = 0

// 	xlib.SendEvent(
// 		display,
// 		rootWnd,
// 		false,
// 		xlib.EventMask{.SubstructureRedirect, .SubstructureNotify},
// 		&evt,
// 	)
// }
// //!not support fullscreen exclusive linux
// // linuxSetFullScreenVulKan :: proc() {
// // 	if __screenMode == .Fullscreen {
// // 		//vulkan
// // 	}
// // }

// linuxStart :: proc() {
// 	if __screenIdx > len(monitors) - 1 do __screenIdx = defScreenIdx
// 	monitors[__screenIdx].rect.x = 0

// 	if __windowWidth == nil do __windowWidth = u32(monitors[__screenIdx].rect.width / 2)
// 	if __windowHeight == nil do __windowHeight = u32(monitors[__screenIdx].rect.height / 2)
// 	if __windowX == nil do __windowX = i32(monitors[__screenIdx].rect.x + monitors[__screenIdx].rect.width / 4)
// 	if __windowY == nil do __windowY = i32(monitors[__screenIdx].rect.y + monitors[__screenIdx].rect.height / 4)

// 	wnd = xlib.CreateWindow(
// 		display,
// 		rootWnd,
// 		__windowX.?,
// 		__windowY.?,
// 		__windowWidth.?,
// 		__windowHeight.?,
// 		0,
// 		xlib.CopyFromParent,
// 		xlib.WindowClass.InputOutput,
// 		(^xlib.Visual)(uintptr(xlib.CopyFromParent)),
// 		xlib.WindowAttributeMask{},
// 		nil,
// 	)

// 	xlib.SelectInput(
// 		display,
// 		wnd,
// 		xlib.EventMask {
// 			.KeyPress,
// 			.KeyRelease,
// 			.ButtonRelease,
// 			.ButtonPress,
// 			.PointerMotion,
// 			.StructureNotify,
// 			.FocusChange,
// 		},
// 	)
// 	xlib.MapWindow(display, wnd)

// 	resAtom: xlib.Atom
// 	resFmt: i32
// 	resNum: uint
// 	resRemain: uint
// 	resData: rawptr

// 	for xlib.GetWindowProperty(
// 		    display,
// 		    wnd,
// 		    xlib.InternAtom(display, "_NET_FRAME_EXTENTS", true),
// 		    0,
// 		    4,
// 		    false,
// 		    xlib.AnyPropertyType,
// 		    &resAtom,
// 		    &resFmt,
// 		    &resNum,
// 		    &resRemain,
// 		    &resData,
// 	    ) !=
// 		    i32(xlib.Status.Success) ||
// 	    resNum != 4 ||
// 	    resRemain != 0 {
// 		evt: xlib.XEvent
// 		xlib.NextEvent(display, &evt)
// 	}
// 	intrinsics.mem_copy(&wndExtent, resData, size_of(c.long) * len(wndExtent))
// 	xlib.Free(resData)

// 	delWnd = xlib.InternAtom(display, "WM_DELETE_WINDOW", false)
// 	stateWnd = xlib.InternAtom(display, "WM_STATE", false)
// 	xlib.SetWMProtocols(display, wnd, &delWnd, 1)

// 	setWndSizeHint(true)
// 	xlib.MoveWindow(display, wnd, __windowX.?, __windowY.?)
// 	xlib.Flush(display)

// 	prevWindowX = __windowX.?
// 	prevWindowY = __windowY.?
// 	prevWindowWidth = __windowWidth.?
// 	prevWindowHeight = __windowHeight.?

// 	if __screenMode != .Window {
// 		monitor := linuxGetMonitorFromWindow()

// 		linuxSendFullScreenEvent(true)

// 		xlib.MoveResizeWindow(
// 			display,
// 			wnd,
// 			monitor.rect.x,
// 			monitor.rect.y,
// 			u32(monitor.rect.width),
// 			u32(monitor.rect.height),
// 		)

// 		//!linuxSetFullScreenVulKan()
// 	}
// 	createRenderFuncThread()
// }
// vulkanLinuxStart :: proc(surface: ^vk.SurfaceKHR) {
// 	if surface != nil do vk.DestroySurfaceKHR(vkInstance, surface^, nil)
// 	xlibSurfaceCreateInfo: VkXlibSurfaceCreateInfoKHR = {
// 		window = wnd,
// 		dpy    = display,
// 		sType  = VK_STRUCTURE_TYPE_XLIB_SURFACE_CREATE_INFO_KHR,
// 		pNext  = nil,
// 		flags  = 0,
// 	}
// 	surface_: vk.SurfaceKHR
// 	res := vkCreateXlibSurfaceKHR(vkInstance, &xlibSurfaceCreateInfo, nil, &surface_)
// 	if (res != .SUCCESS) do panicLog(res)
// 	surface^ = surface_
// }
