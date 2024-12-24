package xmath

import "base:intrinsics"
import "core:math"
import "core:math/linalg"

ceilUp :: proc "contextless"(num:$T, multiple:T) -> T where intrinsics.type_is_integer(T) {
	if multiple == 0 do return num

	remain := abs(num) % multiple
	if remain == 0 do return num

	if num < 0 do return -(abs(num) + multiple - remain)
	return num + multiple - remain
}

floorUp :: proc "contextless"(num:$T, multiple:T) -> T where intrinsics.type_is_integer(T) {
	if multiple == 0 do return num

	remain := abs(num) % multiple
	if remain == 0 do return num

	if num < 0 do return -(abs(num) - remain)
	return num - remain
}


Rect_ :: struct($T: typeid) #raw_union where intrinsics.type_is_numeric(T) {
	using _: struct {
		x:      T,
		y:      T,
		width:  T,
		height: T,
	},
	using _: struct {
		pos:  [2]T,
		size: [2]T,
	},
}
RectI :: Rect_(i32)
RectU :: Rect_(u32)
RectF :: Rect_(f32)

PointF :: [2]f32
PointI :: [2]i32
PointU :: [2]u32
PointF64 :: [2]f64


__Rect_Init :: #force_inline proc "contextless"(pos: [2]$T, size: [2]T) -> Rect_(T) {
	res: Rect_(T)
	res.pos = pos
	res.size = size
	return res
}

__Rect_Init2 :: #force_inline proc "contextless"(x: $T, y: T, width: T, height: T) -> Rect_(T) {
	res: Rect_(T)
	res.pos = T{x, y}
	res.size = T{width, height}
	return res
}


Rect_Init :: proc {
	__Rect_Init,
	__Rect_Init2,
}

//returns a rect whose centre point is the position
Rect_GetFromCenter :: #force_inline proc "contextless" (_pos: [2]$T, _size: [2]T) -> Rect_(T)  {
	res: Rect_(T)
	res.pos = _pos - _size / 2
	res.size = _size
	return res
}
//TODO
Rect_MulMatrix :: proc (_r: RectF, _mat: linalg.Matrix4x4f32) -> RectF #no_bounds_check {
	panic("")
}
//TODO
Rect_DivMatrix :: proc (_r: RectF, _mat: linalg.Matrix4x4f32) -> RectF #no_bounds_check {
	panic("")
}
Rect_Right :: #force_inline proc "contextless" (_r: Rect_($T)) -> T {
	return _r.pos.x + _r.size.x
}
Rect_Bottom :: #force_inline proc "contextless" (_r: Rect_($T)) -> T {
	return _r.pos.y + _r.size.y
}
Rect_RightBottom :: #force_inline proc "contextless" (_r: Rect_($T)) -> [2]T {
	return _r.pos + _r.size
}
Rect_And :: #force_inline proc "contextless" (_r1: Rect_($T), _r2: Rect_(T)) -> (Rect_(T), bool) #optional_ok #no_bounds_check {
	res: Rect_(T)
	for _, i in res.pos {
		res.pos[i] = math.max(_r1.pos[i], _r2.pos[i])
		res.size[i] = math.min(Rect_RightBottom(_r1)[i], Rect_RightBottom(_r2)[i])
		if res.size[i] <= res.pos[i] do return {}, false
		else do res.size[i] -= res.pos[i]
	}
	return res, true
}
Rect_Or :: #force_inline proc "contextless" (_r1: Rect_($T), _r2: Rect_(T)) -> Rect_(T) #no_bounds_check {
	res: Rect_(T)
	for _, i in res.pos {
		res.pos[i] = math.min(_r1.pos[i], _r2.pos[i])
		res.size[i] = math.max(Rect_RightBottom(_r1)[i], Rect_RightBottom(_r2)[i])
	}
	return res
}
Rect_PointIn :: #force_inline proc "contextless" (_r: Rect_($T), p: [2]T) -> bool #no_bounds_check {
	for _, i in _r.pos {
		if _r.pos[i] > p[i] do return false
		if Rect_RightBottom(_r)[i] < p[i] do return false
	}
	return true
}
