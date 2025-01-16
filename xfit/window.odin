package xfit

import "core:sync"

@(private) __windowWidth: Maybe(u32)
@(private) __windowHeight: Maybe(u32)
@(private) __windowX: Maybe(i32)
@(private) __windowY: Maybe(i32)

@(private) prevWindowX: i32
@(private) prevWindowY: i32
@(private) prevWindowWidth: u32
@(private) prevWindowHeight: u32

@(private) __screenIdx: int = 0
@(private) __screenMode: ScreenMode
@(private) __windowTitle: cstring
@(private) __screenOrientation:ScreenOrientation = .Unknown

@(private) monitorsMtx:sync.Mutex
@(private) monitors: [dynamic]MonitorInfo
@(private) primaryMonitor: ^MonitorInfo
@(private) currentMonitor: ^MonitorInfo = nil

@(private) __isFullScreenEx := false
@(private) __vSync:VSync
@(private) monitorLocked:bool = false

@(private) paused := false
@(private) activated := false
@(private) sizeUpdated := false

@(private) fullScreenMtx : sync.Mutex

VSync :: enum {Double, Triple, None}

ScreenMode :: enum {Window, Borderless, Fullscreen}

ScreenOrientation :: enum {
	Unknown,
	Landscape90,
	Landscape270,
	Vertical180,
	Vertical360,
}

MonitorInfo :: struct {
	rect:       RectI,
	refreshRate: u32,
	name:       string,
	isPrimary:  bool,
}

Paused :: proc "contextless" () -> bool {
	return paused
}

Activated :: proc "contextless" () -> bool {
	return activated
}

@private SavePrevWindow :: proc "contextless" () {
	prevWindowX = __windowX.?
    prevWindowY = __windowY.?
    prevWindowWidth = __windowWidth.?
    prevWindowHeight = __windowHeight.?
}

SetFullScreenMode :: proc "contextless" (monitor:^MonitorInfo) {
	when !is_mobile {
		sync.mutex_lock(&fullScreenMtx)
		defer sync.mutex_unlock(&fullScreenMtx)
		SavePrevWindow()
		glfwSetFullScreenMode(monitor)
		__screenMode = .Fullscreen
	}
}
SetBorderlessScreenMode :: proc "contextless" (monitor:^MonitorInfo) {
	when !is_mobile {
		sync.mutex_lock(&fullScreenMtx)
		defer sync.mutex_unlock(&fullScreenMtx)
		SavePrevWindow()
		glfwSetBorderlessScreenMode(monitor)
		__screenMode = .Borderless
	}
}
SetWindowMode :: proc "contextless" () {
	when !is_mobile {
		sync.mutex_lock(&fullScreenMtx)
		defer sync.mutex_unlock(&fullScreenMtx)
		SavePrevWindow()
		glfwSetWindowMode()
		__screenMode = .Window
	}
}
MonitorLock :: proc "contextless" () {
	sync.mutex_lock(&monitorsMtx)
	if monitorLocked do panicLog("already monitorLocked locked")
	monitorLocked = true
}
MonitorUnlock :: proc "contextless" () {
	if !monitorLocked do panicLog("already monitorLocked unlocked")
	monitorLocked = false
	sync.mutex_unlock(&monitorsMtx)
}

GetMonitors :: proc "contextless" () -> []MonitorInfo {
	if !monitorLocked do panicLog("call inside monitorLock")
	return monitors[:len(monitors)]
}

GetCurrentMonitor :: proc "contextless" () -> ^MonitorInfo {
	if !monitorLocked do panicLog("call inside monitorLock")
	return currentMonitor
}

GetMonitorFromWindow :: proc "contextless" () -> ^MonitorInfo #no_bounds_check {
	if !monitorLocked do panicLog("call inside monitorLock")
	for &value in monitors {
		if Rect_PointIn(value.rect, [2]i32{__windowX.?, __windowY.?}) do return &value
	}
	return primaryMonitor
}