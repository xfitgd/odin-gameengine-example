package xfit

@private windowWidth : Maybe(u32)
@private windowHeight : Maybe(u32)
@private windowX : Maybe(i32)
@private windowY : Maybe(i32)

@private prevWindowX : i32
@private prevWindowY : i32
@private prevWindowWidth : u32
@private prevWindowHeight : u32

@private screenIdx : int
@private screenMode : ScreenMode

ScreenMode :: enum { window, borderless, fullscreen }

