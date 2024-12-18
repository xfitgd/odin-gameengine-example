#+private
package xfit

import "core:fmt"
import "core:c"
import "core:math"
import "core:strings"
import "core:math/linalg"
import "vendor:x11/xlib"
import "base:intrinsics"
import "xmath"

display:^xlib.Display
defScreenIdx := 0
wnd:xlib.Window
delWnd:xlib.Atom
stateWnd:xlib.Atom
wndExtent:[4]c.long


_NET_WM_STATE_TOGGLE :: 2

systemLinuxStart :: proc() {
    if display = xlib.OpenDisplay(nil); display == nil do panic("")

    screen_res := xlib.XRRGetScreenResources(display, xlib.DefaultRootWindow(display))
    defer xlib.XRRFreeScreenResources(screen_res)

    le := math.min(screen_res.ncrtc, screen_res.noutput)
    for i in 0..<le {
        crtc_info := xlib.XRRGetCrtcInfo(display, screen_res, screen_res.crtcs[i])
        output := xlib.XRRGetOutputInfo(display, screen_res, screen_res.outputs[i])
        defer xlib.XRRFreeCrtcInfo(crtc_info)
        defer xlib.XRRFreeOutputInfo(output)

        mode_:^xlib.XRRModeInfo = nil
        for k in 0..<screen_res.nmode {
            if output.modes[0] == screen_res.modes[k].id {
                mode_ = &screen_res.modes[k];
                break;
            }
        }
        if mode_ == nil do continue
        append(&monitors, monitor_info{isPrimary = i == i32(defScreenIdx), 
            rect=xmath.rectInit([2]i32{crtc_info.x,crtc_info.y},
                [2]i32{i32(crtc_info.width),i32(crtc_info.height)})})
        
        last := &monitors[len(monitors)-1]
        if last.isPrimary do primaryMonitor = last

        last.name = strings.clone(string(output.name))

        when __log__ {
            fmt.printf("XFIT SYSLOG : %smonitor %d name: %s, x:%d, y:%d, width:%d, height:%d [\n", "primary" if last.isPrimary else "",
            i, last.name,
            crtc_info.x, crtc_info.y, crtc_info.width, crtc_info.height)
        }
        hz := f64(mode_.dotClock) / f64(mode_.hTotal * mode_.vTotal)
        when __log__ {
            fmt.printf("monitor %d resolution: width:%d, height:%d refleshrate %f\n]\n",
            i, mode_.width, mode_.height, hz)
        }
        last.resolution = screen_info{
            monitor = last,
            refreshRate = hz,
            size = {mode_.width, mode_.height}
        }
    }
}

setWndSizeHint :: proc(first_call:bool) {

}

linuxStart :: proc() {
    if screenIdx > len(monitors) - 1 do screenIdx = defScreenIdx
    monitors[screenIdx].rect.x = 0

    if windowWidth == nil do windowWidth = u32(monitors[screenIdx].rect.width / 2)
    if windowHeight == nil do windowHeight = u32(monitors[screenIdx].rect.height / 2)
    if windowX == nil do windowX = i32(monitors[screenIdx].rect.x + monitors[screenIdx].rect.width / 4)
    if windowY == nil do windowY = i32(monitors[screenIdx].rect.y + monitors[screenIdx].rect.height / 4)

    wnd = xlib.CreateWindow(display, xlib.DefaultRootWindow(display), windowX.?, windowY.?, windowWidth.?, windowHeight.?, 0,
    xlib.CopyFromParent, xlib.WindowClass.InputOutput, (^xlib.Visual)(uintptr(xlib.CopyFromParent)), xlib.WindowAttributeMask{}, nil)

    xlib.SelectInput(display, wnd, xlib.EventMask{ .KeyPress, .KeyRelease, .ButtonRelease, .ButtonPress, .PointerMotion, .StructureNotify, .FocusChange })
    xlib.MapWindow(display, wnd)

    resAtom:xlib.Atom
    resFmt:i32
    resNum:uint
    resRemain:uint
    resData:rawptr

    for xlib.GetWindowProperty(display, wnd,
        xlib.InternAtom(display, "_NET_FRAME_EXTENTS", true),
        0, 4, false, xlib.AnyPropertyType,
        &resAtom, &resFmt, &resNum, &resRemain, &resData) != i32(xlib.Status.Success) || resNum != 4 || resRemain != 0 {
        evt:xlib.XEvent
        xlib.NextEvent(display, &evt)
    }
    intrinsics.mem_copy(&wndExtent, resData, size_of(c.long) * len(wndExtent))
    xlib.Free(resData)

    delWnd =  xlib.InternAtom(display, "WM_DELETE_WINDOW", false)
    stateWnd =  xlib.InternAtom(display, "WM_STATE", false)
    xlib.SetWMProtocols(display, wnd, &delWnd, 1)

    setWndSizeHint(true)
    xlib.MoveWindow(display, wnd, windowX.?, windowY.?)
    xlib.Flush(display)

    prevWindowX = windowX.?
    prevWindowY = windowY.?
    prevWindowWidth = windowWidth.?
    prevWindowHeight = windowHeight.?

    if screenMode != .window {
        
    }
}