package xfit

import "base:intrinsics"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:os"
import "core:mem"
import "core:mem/virtual"
import "core:io"
import "core:reflect"
import "core:thread"
import "core:sync"
import "core:strings"
import "base:runtime"
import "core:debug/trace"


@(private) KEY_SIZE :: 512
@(private) keys : [KEY_SIZE]bool = { 0..<KEY_SIZE = false }
@(private) isMouseOut:bool

KeyCode :: enum i32 {
    SPACE = 156,
    A = 30,
    B,
    C,
}

LEFT_MOUSE_BUTTON_IDX :: 0
MIDDLE_MOUSE_BUTTON_IDX :: 1
RIGHT_MOUSE_BUTTON_IDX :: 2

KeyDown : proc "contextless" (keycode:KeyCode) = proc "contextless" (keycode:KeyCode) {}
KeyUp : proc "contextless" (keycode:KeyCode) = proc "contextless" (keycode:KeyCode) {}
KeyRepeat : proc "contextless" (keycode:KeyCode) = proc "contextless" (keycode:KeyCode) {}
MouseButtonDown : proc "contextless" (buttonIdx:int) = proc "contextless" (buttonIdx:int) {}
MouseButtonUp : proc "contextless" (buttonIdx:int) = proc "contextless" (buttonIdx:int) {}
MouseMove : proc "contextless" (x:f64, y:f64) = proc "contextless" (x:f64, y:f64) {}
MouseIn : proc "contextless" () = proc "contextless" () {}
MouseOut : proc "contextless" () = proc "contextless" () {}

IsMouseOut :: proc "contextless" () -> bool {return isMouseOut}