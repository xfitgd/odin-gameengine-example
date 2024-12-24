package xfit

@(private) __windowWidth: Maybe(u32)
@(private) __windowHeight: Maybe(u32)
@(private) __windowX: Maybe(i32)
@(private) __windowY: Maybe(i32)

@(private) prevWindowX: i32
@(private) prevWindowY: i32
@(private) prevWindowWidth: u32
@(private) prevWindowHeight: u32

@(private) __screenIdx: int
@(private) __screenMode: ScreenMode
@(private) __windowTitle: string
@(private) __screenOrientation:ScreenOrientation = .Unknown

@(private) monitors: [dynamic]monitorInfo
@(private) primaryMonitor: ^monitorInfo
@(private) currentMonitor: ^monitorInfo = nil

@(private) __isFullScreenEx := false
@(private) __vSync:VSync

VSync :: enum {Double, Triple, None}

ScreenMode :: enum {Window, Borderless, Fullscreen}

ScreenOrientation :: enum {
	Unknown,
	Landscape90,
	Landscape270,
	Vertical180,
	Vertical360,
}