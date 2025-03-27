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
Point3DF :: linalg.Vector3f32
Point3DwF :: linalg.Vector4f32
PointI :: [2]i32
PointU :: [2]u32
PointF64 :: [2]f64
Matrix :: matrix[4, 4]f32


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

epsilon :: proc "contextless" ($T:typeid) -> T where intrinsics.type_is_float(T) {
	if T == f16 || T == f16be || T == f16le do return T(math.F16_EPSILON)
	if T == f32 || T == f32be || T == f32le do return T(math.F32_EPSILON)
	return T(math.F64_EPSILON)
}

epsilonEqual :: proc "contextless" (a:$T, b:T) -> bool where intrinsics.type_is_float(T) {
	return math.abs(a - b) < epsilon(T)
}


PointInTriangle :: proc "contextless" (p : [2]$T, a : [2]T, b : [2]T, c : [2]T) -> bool where intrinsics.type_is_float(T){
    sign :: proc "contextless" (p1, p2, p3: [2]T) -> T {
        return (p1[0] - p3[0]) * (p2[1] - p3[1]) - (p2[0] - p3[0]) * (p1[1] - p3[1])
    }
    
    d1 := sign(p, a, b)
    d2 := sign(p, b, c)
    d3 := sign(p, c, a)
    
    has_neg := d1 < 0 || d2 < 0 || d3 < 0
    has_pos := d1 > 0 || d2 > 0 || d3 > 0
    
    return !(has_neg && has_pos)
}

PointInLine :: proc "contextless" (p:[2]$T, l0:[2]T, l1:[2]T) -> (bool, T) where intrinsics.type_is_float(T) {
	A := (l0.y - l1.y) / (l0.x - l1.x)
	B := l0.y - A * l0.x

	pY := A * p.x + B
	res := p.y >= pY - epsilon(T) && p.y <= pY + epsilon(T) 
	t :T = 0.0
	if res {
		minX := min(l0.x, l1.x)
		maxX := max(l0.x, l1.x)
		t = (p.x - minX) / (maxX - minX)
	}

	return res &&
		p.x >= min(l0.x, l1.x) &&
		p.x <= max(l0.x, l1.x) &&
		p.y >= min(l0.y, l1.y) &&
		p.y <= max(l0.y, l1.y), t
}

PointDeltaInLine :: proc "contextless" (p:[2]$T, l0:[2]T, l1:[2]T) -> T where intrinsics.type_is_float(T) {
	A := (l0.y - l1.y) / (l0.x - l1.x)
	B := l0.y - A * l0.x

	pp := NearestPointBetweenPointAndLine(p, l0, l1)

	pY := A * pp.x + B
	t :T = 0.0
	minX := min(l0.x, l1.x)
	maxX := max(l0.x, l1.x)
	t = (p.x - minX) / (maxX - minX)

	return t
}

PointInVector :: proc "contextless" (p:[2]$T, v0:[2]T, v1:[2]T) -> (bool, T) where intrinsics.type_is_float(T) {
	a := v1.y - v0.y
	b := v0.x - v1.x
	c := v1.x * v0.y + v0.x * v1.y
	res := a * p.x + b * p.y + c
	return res == 0, res
}

PointLineLeftOrRight :: #force_inline proc "contextless" (p : [2]$T, l0 : [2]T, l1 : [2]T) -> T where intrinsics.type_is_float(T) {
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

GetPolygonOrientation :: proc "contextless" (polygon : [][2]$T) -> PolyOrientation where intrinsics.type_is_float(T) {
	res :f32 = 0
	for i in 0..<len(polygon) {
		j := (i + 1) % len(polygon)
		factor := (polygon[j].x - polygon[i].x) * (polygon[j].y + polygon[i].y)
		res += factor
	}

	return res > 0 ? .Clockwise : .CounterClockwise
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

LinesIntersect :: proc "contextless" (a1 : [2]$T, a2 : [2]T, b1: [2]T, b2 : [2]T) -> (bool, [2]T) where intrinsics.type_is_float(T) {
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

NearestPointBetweenPointAndLine :: proc "contextless" (p:[2]$T, l0:[2]T, l1:[2]T) -> [2]T where intrinsics.type_is_float(T) {
	AB := l1 - l0
	AC := p - l0

	return l0 + AB * (linalg.vector_dot(AB, AC) / linalg.vector_dot(AB, AB))
}

Circle :: struct(T:typeid) where intrinsics.type_is_float(T) {
	p : [2]T,
	radius : T,
}

CircleF :: Circle(f32)
CircleF64 :: Circle(f64)

PolyOrientation :: enum {
	Clockwise,
	CounterClockwise
}

OppPolyOrientation :: #force_inline proc "contextless" (ccw:PolyOrientation) -> PolyOrientation {
	return ccw == .Clockwise ? .CounterClockwise : .Clockwise
}

//https://stackoverflow.com/a/73061541
LineExtendPoint :: proc "contextless" (prev:[2]$T, cur:[2]T, next:[2]T, thickness:T, ccw:PolyOrientation) -> [2]T where intrinsics.type_is_float(T) {
	vn : [2]T = next - cur
	vnn : [2]T = linalg.normalize(vn)
	nnnX := vnn.y
	nnnY := -vnn.x

	ccw_ : T = (ccw == .Clockwise ? -1 : 1)
	vp : [2]T = cur - prev
	vpn: [2]T = linalg.normalize(vp)
	npnX := vpn.y * ccw_
	npnY := vpn.x * ccw_

	bis := [2]T{(nnnX + npnY) * ccw_, (nnnY + npnX) * ccw_}
	bisn : [2]T = linalg.normalize(bis)
	bislen := thickness / intrinsics.sqrt((1 + nnnX * npnX + nnnY * npnY) / 2)

	return {cur.x + bislen * bisn.x, cur.y + bislen * bisn.y}
}

MirrorPoint :: #force_inline proc "contextless" (pivot : [2]$T, target : [2]T) -> [2]T where intrinsics.type_is_float(T) {
	return [2]T{2,2} * pivot - target
}