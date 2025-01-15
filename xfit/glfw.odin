#+private
package xfit

import "glfw"
import "core:c"
import "core:sync"
import "base:runtime"
import "base:intrinsics"
import vk "vendor:vulkan"


@(private="file") wnd:glfw.WindowHandle = nil
@(private="file") glfwMonitors:[dynamic]glfw.MonitorHandle


glfwStart :: proc() {
    //?default screen idx 0
    if __windowWidth == nil do __windowWidth = u32(monitors[0].rect.width / 2)
	if __windowHeight == nil do __windowHeight = u32(monitors[0].rect.height / 2)
	if __windowX == nil do __windowX = i32(monitors[0].rect.x + monitors[0].rect.width / 4)
	if __windowY == nil do __windowY = i32(monitors[0].rect.y + monitors[0].rect.height / 4)

    SavePrevWindow()

    //? change use glfw.SetWindowAttrib()
    if __screenMode ==.Borderless {
        glfw.WindowHint (glfw.DECORATED, glfw.FALSE)
        glfw.WindowHint(glfw.FLOATING, glfw.TRUE)

        wnd = glfw.CreateWindow(monitors[__screenIdx].rect.width,
            monitors[__screenIdx].rect.height,
            __windowTitle,
            nil,
            nil)

        glfw.SetWindowPos(wnd, monitors[__screenIdx].rect.x, monitors[__screenIdx].rect.y)
        glfw.SetWindowSize(wnd, monitors[__screenIdx].rect.width, monitors[__screenIdx].rect.height)
    } else if __screenMode == .Fullscreen {
        wnd = glfw.CreateWindow(monitors[__screenIdx].rect.width,
            monitors[__screenIdx].rect.height,
            __windowTitle,
            glfwMonitors[__screenIdx],
            nil)
    } else {
        wnd = glfw.CreateWindow(auto_cast __windowWidth.?,
            auto_cast __windowHeight.?,
            __windowTitle,
            nil,
            nil)

        glfw.SetWindowPos(wnd, __windowX.?, __windowY.?)
    }

    createRenderFuncThread()
}

glfwSetFullScreen :: proc "contextless" (monitor:^monitorInfo) {
    for &m, i in monitors {
        if raw_data(m.name) == raw_data(monitor.name) {
            glfw.SetWindowMonitor(wnd, glfwMonitors[i], monitor.rect.x,
                 monitor.rect.y,
                monitor.rect.width,
                monitor.rect.height,
                auto_cast monitor.refreshRate)
            return
        }
    }
}

glfwVulkanStart :: proc "contextless" (surface: ^vk.SurfaceKHR) {
    if surface != nil do vk.DestroySurfaceKHR(vkInstance, surface^, nil)

    res := glfw.CreateWindowSurface(vkInstance, wnd, nil, surface)
    if (res != .SUCCESS) do panicLog(res)
}

@(private="file") glfwInitMonitors :: proc() {
    glfwMonitors = make([dynamic]glfw.MonitorHandle)
    _monitors := glfw.GetMonitors()

    for m in _monitors {
        glfwAppendMonitor(m)
    }
}

@(private="file") glfwAppendMonitor :: proc(m:glfw.MonitorHandle) {
    info:monitorInfo
    info.name = glfw.GetMonitorName(m)
    info.rect.x, info.rect.y, info.rect.width, info.rect.height = glfw.GetMonitorWorkarea(m)
    info.isPrimary = m == glfw.GetPrimaryMonitor()

    vidMode :^glfw.VidMode = glfw.GetVideoMode(m)
    info.refreshRate = auto_cast vidMode.refresh_rate

    when is_log {
        printf(
            "XFIT SYSLOG : ADD %s monitor name: %s, x:%d, y:%d, width:%d, height:%d, refleshrate%d\n",
            "primary" if info.isPrimary else "",
            info.name,
            info.rect.x,
            info.rect.y,
            info.rect.width,
            info.rect.height,
            info.refreshRate,
        )
    }

    append(&monitors, info)
    append(&glfwMonitors, m)
}

glfwSystemStart :: proc() {
    glfwMonitorProc :: proc "c" (monitor: glfw.MonitorHandle, event: c.int) {
        sync.mutex_lock(&monitorsMtx)
        defer sync.mutex_unlock(&monitorsMtx)
        
        context = runtime.default_context() 
        if event == glfw.CONNECTED {
            glfwAppendMonitor(monitor)
        } else if event == glfw.DISCONNECTED {
            for m, i in glfwMonitors {
                if m == monitor {
                    when is_log {
                        printf(
                            "XFIT SYSLOG : DEL %s monitor name: %s, x:%d, y:%d, width:%d, height:%d, refleshrate%d\n",
                            "primary" if monitors[i].isPrimary else "",
                            monitors[i].name,
                            monitors[i].rect.x,
                            monitors[i].rect.y,
                            monitors[i].rect.width,
                            monitors[i].rect.height,
                            monitors[i].refreshRate,
                        )
                    }
                    ordered_remove(&glfwMonitors, i)
                    ordered_remove(&monitors, i)
                    break
                }
            }
        }
    }

    //Unless you will be using OpenGL or OpenGL ES with the same window as Vulkan, there is no need to create a context. You can disable context creation with the GLFW_CLIENT_API hint.
    glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)

    glfwInitMonitors()
    glfw.SetMonitorCallback(glfwMonitorProc)
}

glfwDestroy :: proc() {
    if wnd != nil do glfw.DestroyWindow(wnd)
    wnd = nil
}


glfwSystemDestroy :: proc() {
    delete(glfwMonitors)
    glfw.Terminate()
}

glfwLoop :: proc() {
    glfwKeyProc :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: c.int) {
        //glfw.KEY_SPACE
        if key > KEY_SIZE-1 || key < 0 || !IsValidEnumValue(KeyCode, key) {
            return
        }
        switch action {
            case glfw.PRESS:
                if !keys[key] {
                    keys[key] = true
                    KeyDown(KeyCode(key))
                }
            case glfw.RELEASE:
                keys[key] = false
                KeyUp(KeyCode(key))
            case glfw.REPEAT:
                KeyRepeat(KeyCode(key))
        }
    }
    glfwMouseButtonProc :: proc "c" (window: glfw.WindowHandle, button, action, mods: c.int) {
        switch action {
            case glfw.PRESS:
                MouseButtonDown(auto_cast button)
            case glfw.RELEASE:
                MouseButtonUp(auto_cast button)
        }
    }
    glfwCursorPosProc :: proc "c" (window: glfw.WindowHandle, xpos,  ypos: f64) {
        MouseMove(xpos, ypos)
    }
    glfwCursorEnterProc :: proc "c" (window: glfw.WindowHandle, entered: c.int) {
        if b32(entered) {
            isMouseOut = false
            MouseIn()
        } else {
            isMouseOut = true
            MouseOut()
        }
    }
    glfwCharProc :: proc "c"  (window: glfw.WindowHandle, codepoint: rune) {
        //TODO
    }
    glfwJoystickProc :: proc "c" (joy, event: c.int) {
        //TODO
    }
    glfwWindowSizeProc :: proc "c" (window: glfw.WindowHandle, width, height: c.int) {
        __windowWidth = u32(width)
        __windowHeight = u32(height)

        intrinsics.atomic_store_explicit(&sizeUpdated, false, .Release)
    }
    glfwWindowPosProc :: proc "c" (window: glfw.WindowHandle, xpos, ypos: c.int) {
        __windowX = xpos
        __windowY = ypos
    }
    glfwWindowCloseProc :: proc "c" (window: glfw.WindowHandle) {
        glfw.SetWindowShouldClose(window, auto_cast Close())
    }
    glfwWindowFocusProc :: proc "c" (window: glfw.WindowHandle, focused: c.int) {
        if focused != 0 {
            sync.atomic_store_explicit(&paused, false, .Relaxed)
            activated = true
        } else {
            activated = false
        }
        Activate()
    }
    glfw.SetKeyCallback(wnd, glfwKeyProc)
    glfw.SetMouseButtonCallback(wnd, glfwMouseButtonProc)
    glfw.SetCharCallback(wnd, glfwCharProc)
    glfw.SetCursorPosCallback(wnd, glfwCursorPosProc)
    glfw.SetCursorEnterCallback(wnd, glfwCursorEnterProc)
    glfw.SetJoystickCallback(glfwJoystickProc)
    glfw.SetWindowCloseCallback(wnd, glfwWindowCloseProc)
    glfw.SetWindowFocusCallback(wnd, glfwWindowFocusProc)
    glfw.SetWindowSizeCallback(wnd, glfwWindowSizeProc)
    glfw.SetWindowPosCallback(wnd, glfwWindowPosProc)

    for !glfw.WindowShouldClose(wnd) {
        glfw.WaitEvents()   
    }
}