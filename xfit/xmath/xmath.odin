package xmath

import "base:intrinsics"
import "core:math"
import "core:math/linalg"


@(private)
rect_ :: struct($T: typeid) #raw_union where intrinsics.type_is_numeric(T) {
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
recti :: rect_(i32)
rectu :: rect_(u32)
rectf :: rect_(f32)

pointf :: [2]f32
pointi :: [2]i32
pointu :: [2]u32
pointf64 :: [2]f64


__rectInit :: proc(pos: [2]$T, size: [2]T) -> rect_(T) {
	res: rect_(T)
	res.pos = pos
	res.size = size
	return res
}

__rectInit2 :: proc(x: $T, y: T, width: T, height: T) -> rect_(T) {
	res: rect_(T)
	res.pos = T{x, y}
	res.size = T{width, height}
	return res
}


rectInit :: proc {
	__rectInit,
	__rectInit2,
}

//returns a rect whose centre point is the position
rectGetFromCenter :: proc(_pos: [2]$T, _size: [2]T) -> rect_(T) {
	res: rect_(T)
	res.pos = _pos - _size / 2
	res.size = _size
	return res
}
//TODO
rectMulMatrix :: proc(_r: rectf, _mat: linalg.Matrix4x4f32) -> rectf {
	panic("")
}
//TODO
rectDivMatrix :: proc(_r: rectf, _mat: linalg.Matrix4x4f32) -> rectf {
	panic("")
}
rectRight :: #force_inline proc(_r: rect_($T)) -> T {
	return _r.pos.x + _r.size.x
}
rectBottom :: #force_inline proc(_r: rect_($T)) -> T {
	return _r.pos.y + _r.size.y
}
rectRightBottom :: #force_inline proc(_r: rect_($T)) -> [2]T {
	return _r.pos + _r.size
}
rectAnd :: proc(_r1: rect_($T), _r2: rect_(T)) -> (rect_(T), bool) #optional_ok {
	res: rect_(T)
	for _, i in res.pos {
		res.pos[i] = math.max(_r1.pos[i], _r2.pos[i])
		res.size[i] = math.min(rectRightBottom(_r1)[i], rectRightBottom(_r2)[i])
		if res.size[i] <= res.pos[i] do return {}, false
		else do res.size[i] -= res.pos[i]
	}
	return res, true
}
rectOr :: proc(_r1: rect_($T), _r2: rect_(T)) -> rect_(T) {
	res: rect_(T)
	for _, i in res.pos {
		res.pos[i] = math.min(_r1.pos[i], _r2.pos[i])
		res.size[i] = math.max(rectRightBottom(_r1)[i], rectRightBottom(_r2)[i])
	}
	return res
}
rectPointIn :: proc(_r: rect_($T), p: [2]T) -> bool {
	for _, i in _r.pos {
		if _r.pos[i] > p[i] do return false
		if rectRightBottom(_r)[i] < p[i] do return false
	}
	return true
}
