#+private
package xfit_system

import "core:fmt"
import "core:c"
import "vendor:x11/xlib"

display:^xlib.Display
def_screen_idx := 0
wnd:xlib.Window
del_wnd:xlib.Atom
state_wnd:xlib.Atom
wnd_extent:[4]c.long



system_linux_start :: proc() {
    

}