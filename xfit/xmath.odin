package xfit

import "base:intrinsics"
import "core:math"
import "core:simd"
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

PointF ::  linalg.Vector2f32
Point3DwF :: linalg.Vector4f32
PointI :: [2]i32
PointU :: [2]u32
PointF64 :: [2]f64
Matrix :: linalg.Matrix4x4f32


//! 현재 매개변수에 배열 이외의 값 (숫자) 을 넣어도 작동되는 버그 있음.
min_array :: proc "contextless" (value0:$T/[$N]$E, values:..T) -> (result:[N]E) {
	for i := 0;i < N;i += 1 {
		m : E = value0[i]
		for v in values {
			if m > v[i] do m = v[i]
		}
		result[i] = m
	}
	return
}

max_array :: proc "contextless" (value0:$T/[$N]$E, values:..T) -> (result:[N]E) {
	for i in 0..<int(N) {
		m : E = value0[i]
		for v in values {
			if m < v[i] do m = v[i]
		}
		result[i] = m
	}
	return
}

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
Rect_MulMatrix :: proc (_r: RectF, _mat: Matrix) -> RectF #no_bounds_check {
	panic("")
}
//TODO
Rect_DivMatrix :: proc (_r: RectF, _mat: Matrix) -> RectF #no_bounds_check {
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

splat_2 :: proc "contextless" (scalar:$T) -> [2]T where intrinsics.type_is_numeric(T) {
	return { 0..<2 = scalar }
}
splat_3 :: proc "contextless" (scalar:$T) -> [3]T where intrinsics.type_is_numeric(T) {
	return { 0..<3 = scalar }
}
splat_4 :: proc "contextless" (scalar:$T) -> [4]T where intrinsics.type_is_numeric(T) {
	return { 0..<4 = scalar }
}


// Algorithm from http://www.blackpawn.com/texts/pointinpoly/default.html
PointInTriangle :: proc "contextless" (p : [2]$T, a : [2]T, b : [2]T, c : [2]T) -> bool where intrinsics.type_is_float(T){
    v0 := c - a
    v1 := b - a
	v2 := p - a

	dot00 := linalg.vector_dot(v0, v1)
	dot01 := linalg.vector_dot(v0, v1)
	dot02 := linalg.vector_dot(v0, v2)
	dot11 := linalg.vector_dot(v1, v1)
	dot12 := linalg.vector_dot(v1, v2)
	denominator := dot00 * dot11 - dot01 * dot01
	if denominator == 0 do return false

	inverseDenominator := 1 / denominator
	u := (dot11 * dot02 - dot01 * dot12) * inverseDenominator
	v := (dot00 * dot12 - dot01 * dot02) * inverseDenominator

	return (u >= 0) && (v >= 0) && (u + v < 1)
}

PointInLine :: proc "contextless" (p:[2]$T, l0:[2]T, l1:[2]T) -> (bool, T) where intrinsics.type_is_float(T) {
	a := l1.y - l0.y
	b := l0.x - l1.x
	c := l1.x * l0.y + l0.x * l1.y
	res := a * p.x + b * p.y + c

	return res == 0 &&
		p.x >= min(l0.x, l1.x) &&
		p.x <= max(l0.x, l1.x) &&
		p.y >= min(l0.y, l1.y) &&
		p.y <= max(l0.y, l1.y), res
}

PointInVector :: proc "contextless" (p:[2]$T, v0:[2]T, v1:[2]T) -> (bool, T) where intrinsics.type_is_float(T) {
	a := v1.y - v0.y
	b := v0.x - v1.x
	c := v1.x * v0.y + v0.x * v1.y
	res := a * p.x + b * p.y + c
	return res == 0, res
}

PointLineDistance :: #force_inline proc "contextless" (p : [2]$T, l0 : [2]T, l1 : [2]T) -> T where intrinsics.type_is_float(T) {
	return (l1.x - l0.x) * (p.y - l0.y) - (p.x - l0.x) * (l1.y - l0.y)
}

//https://bowbowbow.tistory.com/24
PointInPolygon :: proc "contextless" (p: [2]$T, polygon:[][2]T) -> bool where intrinsics.type_is_float(T) {
	 //crosses는 점p와 오른쪽 반직선과 다각형과의 교점의 개수
	 crosses := 0
	 for i in  0..<len(polygon) {
		j := (i + 1) % len(polygon)
		//점 p가 선분 (polygon[i], polygon[j])의 y좌표 사이에 있음
        if ((polygon[i].y > p.y) != (polygon[j].y > p.y)) {
            //atX는 점 p를 지나는 수평선과 선분 (polygon[i], polygon[j])의 교점
            atx := (polygon[j].x - polygon[i].x) * (p.y - polygon[i].y) / (polygon[j].y - polygon[i].y) + polygon[i].x;
            //atX가 오른쪽 반직선과의 교점이 맞으면 교점의 개수를 증가시킨다.
            if (p.x < atx) do crosses += 1;
        }
	 }
	 return (crosses % 2) > 0
}

CenterPointInPolygon :: proc "contextless" (polygon : [][2]$T) -> [2]T where intrinsics.type_is_float(T) {
	area :f32 = 0
	p : [2]T = {0,0}
	for i in 0..<len(polygon) {
		j := (i + 1) % len(polygon)
		factor := linalg.vector_cross2(polygon[i], polygon[j])
		area += factor
		p = (polygon[i] + polygon[j]) * splat_2(factor) + p
	}
	area = area / 2 * 6
	p *= splat_2(1 / area)
	return p
}

LineInPolygon :: proc "contextless" (a : [2]$T, b : [2]T, polygon : [][2]T, checkInsideLine := true) -> bool where intrinsics.type_is_float(T) {
	//Points a, b must all be inside the polygon so that line a, b and polygon line segments do not intersect, so b does not need to be checked.
	if checkInsideLine && PointInPolygon(a, polygon) do return true

	res : PointF
	ok:bool
	for i in 0..<len(polygon) {
		j := (i + 1) % len(polygon)
		ok, res = LinesIntersect(polygon[i], polygon[j], a, b)
		if ok {
			if a == res || b == res do continue
			return true
		}
	}
	return false
}

LinesIntersect :: proc(a1 : [2]$T, a2 : [2]T, b1: [2]T, b2 : [2]T) -> (bool, [2]T) where intrinsics.type_is_float(T) {
	a := a2 - a1
	b := b2 - b1
	ab := a1 - b1
	aba := linalg.vector_cross2(a, b)
	if aba == 0 do return false, {}

	

	A := linalg.vector_cross2(b, ab) / aba
	B := linalg.vector_cross2(a, ab) / aba
	if A <= 1 && B <= 1 && A >= 0 && B >= 0 {
		return true, a1 + splat_2(A) * (a2 - a1) 
	}
	return false, {}
}

NearestPointBetweenPointAndLine :: proc(p:[2]$T, l0:[2]T, l1:[2]T) -> [2]T where intrinsics.type_is_float(T) {
	a := (l0.y - l1.y) / (l0.x - l1.x)
	c := (l1.x - l0.x) / (l0.y - l1.y)

	x := (p.y - l0.y + l0.x * a - p.x) / (a - c)
	return { x, a * p.x + l0.y - l0.x * a }
}

Circle :: struct(T:typeid) where intrinsics.type_is_float(T) {
	p : [2]T,
	radius : T,
}

CircleF :: Circle(f32)
CircleF64 :: Circle(f64)

CCW :: enum {
	Clockwise,
	Counterclockwise
}

//https://stackoverflow.com/a/73061541
LineExtendPoint :: proc "contextless" (prev:[2]$T, cur:[2]T, next:[2]T, thickness:T, ccw:CCW) -> [2]T where intrinsics.type_is_float(T) {
	vn : [2]T = next - cur
	vnn : [2]T = linalg.normalize(vn)
	nnnX := vnn.y
	nnnY := -vnn.x

	ccw_ : T = (ccw == .Clockwise ? -1 : 1)
	vp : [2]T = cur - prev
	vpn: [2]T = linalg.normalize(vp)
	npnX := vpn.y * ccw_
	npnY := vpn.x * ccw_

	bis := [2]T{(nnnX + npnY) * ccw, (nnnY + npnX) * ccw}
	bisn : [2]T = linalg.normalize(bis)
	bislen := thickness / intrinsics.sqrt((1 + nnnX * npnX + nnnY * npnY) / 2)

	return {cur.x + bislen * bisn.x, cur.y + bislen * bisn.y}
}

MirrorPoint :: #force_inline proc "contextless" (pivot : [2]$T, target : [2]T) -> [2]T where intrinsics.type_is_float(T) {
	return [2]T{2,2} * pivot - target
}