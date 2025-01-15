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
@(private) monitors: [dynamic]monitorInfo
@(private) primaryMonitor: ^monitorInfo
@(private) currentMonitor: ^monitorInfo = nil

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

GetMonitorsLock :: proc "contextless" () -> []monitorInfo {
	if !monitorLocked do panicLog("call inside monitorLock")
	return monitors[:len(monitors)]
}

GetMonitorFromWindow :: proc "contextless" () -> ^monitorInfo #no_bounds_check {
	for &value in monitors {
		if Rect_PointIn(value.rect, [2]i32{__windowX.?, __windowY.?}) do return &value
	}
	return primaryMonitor
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

SetFullScreen :: proc "contextless" (monitor:^monitorInfo) {
	sync.mutex_lock(&fullScreenMtx)
	defer sync.mutex_unlock(&fullScreenMtx)
	SavePrevWindow()
	glfwSetFullScreen(monitor)
	__screenMode = .Fullscreen
}
