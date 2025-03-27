package xfit

//TODO

import "core:math"
import "core:slice"
import "core:fmt"
import "core:math/linalg"
import "base:runtime"
import "base:intrinsics"

RawShape :: struct {
    vertices : []ShapeVertex2D,
    indices:[]u32,
}

CurveType :: enum {
    Line,
    Unknown,
    Serpentine,
    Loop,
    Cusp,
    Quadratic,
}

// LineError :: enum {
//     None,
//     IsPointNotLine,
//     IsNotCurve,
//     InvaildLine,
//     OutOfIdx,    
// }

ShapesError :: enum {
    None,
    IsPointNotLine,
    IsNotCurve,
    InvaildLine,
    OutOfIdx,
    IsNotPolygon,
    invaildPolygonLineCounts,
    CantPolygonMatchHoles,
}

// Line :: struct {
//     start:PointF,
//     control0:PointF,
//     control1:PointF,
//     type:CurveType,
// }

// Line_LineInit :: #force_inline proc "contextless" (start:PointF) -> Line {
//     return {
//         start = start,
//         type = .Line
//     }
// }
// Line_QuadraticInit :: #force_inline proc "contextless" (start:PointF, control:PointF) -> Line {
//     return {
//         start = start,
//         control0 = control,
//         control1 = control,
//         type = .Quadratic
//     }
// }


Shapes :: struct {
    poly:[]PointF,
    nPolys:[]u32,
    nTypes:[]u32,
    types:[]CurveType,
    colors:[]Maybe(Point3DwF),
    strokeColors:[]Maybe(Point3DwF),
    thickness:[]f32,
}

CvtQuadraticToCubic0 :: #force_inline proc "contextless" (_start : PointF, _control : PointF) -> PointF {
    return PointF{ _start.x + (2.0/3.0) * (_control.x - _start.x), _start.y + (2.0/3.0) * (_control.y - _start.y) }
}
CvtQuadraticToCubic1 :: #force_inline proc "contextless" (_end : PointF, _control : PointF) -> PointF {
    return CvtQuadraticToCubic0(_end, _control)
}


RawShape_BytesSize :: proc(self:^RawShape) -> (size:int = 0) {
    size += len(self.vertices) * size_of(ShapeVertex2D)
    size += len(self.indices) * size_of(u32)

    size += size_of(u32) * 2
    size += 4//rsb0
    return
}

RawShape_Free :: proc (self:^RawShape, allocator := context.allocator) {
    delete(self.vertices, allocator)
    delete(self.indices, allocator)
    free(self, allocator)
}

RawShape_ToCloneBytes :: proc (self:^RawShape, out:[^]byte) {
    out[0] = 'r'
    out[1] = 's'
    out[2] = 'b'
    out[3] = 0

    (transmute([^]u32)(&out[4]))[0] = auto_cast len(self.vertices)
    (transmute([^]u32)(&out[4]))[1] = auto_cast len(self.indices)

    off := 4 + (2 * size_of(u32))
    intrinsics.mem_copy_non_overlapping(&out[off], &self.vertices[0], len(self.vertices) * size_of(ShapeVertex2D))
    off += len(self.vertices) * size_of(ShapeVertex2D)
    intrinsics.mem_copy_non_overlapping(&out[off], &self.indices[0], len(self.indices) * size_of(u32))
}

RawShape_Clone :: proc (self:^RawShape, allocator := context.allocator) -> (res:^RawShape = nil) {
    res = new(RawShape, allocator)
    res.vertices = make_non_zeroed_slice([]ShapeVertex2D, len(self.vertices), allocator)
    res.indices = make_non_zeroed_slice([]u32, len(self.indices), allocator)
    intrinsics.mem_copy_non_overlapping(&res.vertices[0], &self.vertices[0], len(self.vertices) * size_of(ShapeVertex2D))
    intrinsics.mem_copy_non_overlapping(&res.indices[0], &self.indices[0], len(self.indices) * size_of(u32))
    return
}

RawShape_CloneFromBytes :: proc (_in :[]byte, allocator := context.allocator) -> (res:^RawShape = nil) {
    if !(_in[0] == 'r' && _in[1] == 's' && _in[2] == 'b' && _in[3] == 0) do return

    res = new(RawShape, allocator)
    res.vertices = make_non_zeroed_slice([]ShapeVertex2D,  (transmute([^]u32)(&_in[4]))[0], allocator)
    res.indices = make_non_zeroed_slice([]u32,  (transmute([^]u32)(&_in[4]))[1], allocator)

    off := 4 + (2 * size_of(u32))
    intrinsics.mem_copy_non_overlapping(&res.vertices[0], &_in[off], len(res.vertices) * size_of(ShapeVertex2D))
    off += len(res.vertices) * size_of(ShapeVertex2D)
    intrinsics.mem_copy_non_overlapping(&res.indices[0], &_in[off], len(res.indices) * size_of(u32))

    return
}


GetCubicCurveType :: proc "contextless" (_start:[2]$T, _control0:[2]T, _control1:[2]T, _end:[2]T) ->
(type:CurveType = .Unknown, err:ShapesError = .None, outD:[3]T) where intrinsics.type_is_float(T) {

    if _start == _control0 && _control0 == _control1 && _control1 == _end {
        err = .IsPointNotLine
        return
    }

    cross_1 := [3]T{_end.y - _control1.y,       _control1.x - _end.x,       _end.x * _control1.y - _end.y * _control1.x}
    cross_2 := [3]T{_start.y - _end.y,          _end.x - _start.x,          _start.x * _end.y - _start.y * _end.x}
    cross_3 := [3]T{_control0.y - _start.y,     _start.x - _control0.x,     _control0.x * _start.y - _control0.y * _start.x}

    a1 := _start.x * cross_1.x      + _start.y * cross_1.y      + cross_1.z
    a2 := _control0.x * cross_2.x   + _control0.y * cross_2.y   + cross_2.z
    a3 := _control1.x * cross_3.x   + _control1.y * cross_3.y   + cross_3.z

    outD[0] = a1 - 2 * a2 + 3 * a3
    outD[1] = -a2 + 3 * a3
    outD[2] = 3 * a3

    D := 3 * outD[1] * outD[1] - 4 * outD[2] * outD[0]
    discr := outD[0] * outD[0] * D

    if discr > epsilon(T) {
        type = .Serpentine
    } else if discr < -epsilon(T) {
        type = .Loop
    } else if abs(discr) <= epsilon(T) {
        if abs(outD[0]) <= epsilon(T) && abs(outD[1]) <= epsilon(T) {
            if abs(outD[2]) <= epsilon(T) {
                type = .Line
            }
            type = .Quadratic
        } else {
            type = .Cusp
        }
    } else {
        type = .Loop
    }
    return
}

LineSplitCubic :: proc "contextless" (pts:[4][$N]$T, t:T) -> (outPts1:[4][N]T, outPts2:[4][N]T) where intrinsics.type_is_float(T) {
    outPts1[0] = pts[0]
    outPts2[3] = pts[3]
    outPts1[1] = linalg.lerp(pts[0], pts[1], t)
    outPts2[2] = linalg.lerp(pts[2], pts[3], t)
    p11 := linalg.lerp(pts[1], pts[2], t)
    outPts1[2] = linalg.lerp(outPts1[1], p11, t)
    outPts2[1] = linalg.lerp(p11, outPts2[2], t)
    outPts1[3] = linalg.lerp(outPts1[2], outPts2[1], t)
    outPts2[0] = outPts1[3]
    return
}

LineSplitQuadratic :: proc "contextless" (pts:[3][$N]$T, t:T) -> (outPts1:[3][N]T, outPts2:[3][N]T) where intrinsics.type_is_float(T) {
    outPts1[0] = pts[0]
    outPts2[2] = pts[2]
    outPts1[1] = linalg.lerp(pts[0], pts[1], t)
    outPts2[1] = linalg.lerp(pts[1], pts[2], t)
    outPts1[2] = pts[1]
    outPts2[0] = pts[1]
    return
}

LineSplitLine :: proc "contextless" (pts:[2][$N]$T, t:T) -> (outPts1:[2][N]T, outPts2:[2][N]T) where intrinsics.type_is_float(T) {
    outPts1[0] = pts[0]
    outPts1[1] = linalg.lerp(pts[0], pts[1], t)
    outPts2[0] = outPts1[1]
    outPts2[1] = pts[1]
    return
}

@(private="file") _Shapes_ComputeLine :: proc(
    poly:^[dynamic]PointF,
    vertList:^[dynamic]ShapeVertex2D,
    indList:^[dynamic]u32,
    pts:[]PointF,
    type:CurveType,
    color:Point3DwF,
    _reverse := false,
    _subdiv :f32 = 0.0,
    _repeat := false) -> ShapesError {

    if _subdiv < 0 do panicLog("_subdiv can't negative.")

    curveType := type
    err:ShapesError = .None

    pts2 : [4][2]f32
    pts_:[4][2]f32
    intrinsics.mem_copy_non_overlapping(&pts_[0], &pts[0], len(pts) * size_of(PointF))

    reverse := false
    outD:[3]f32 = {0, 0, 0}
    if curveType != .Line && curveType != .Quadratic {
        curveType, err, outD = GetCubicCurveType(pts[0], pts[1], pts[2], pts[3])
        if err != .None do return err
    } else if curveType == .Quadratic && _subdiv == 0.0 {
        non_zero_append(poly, pts[0])

        if PointLineLeftOrRight(pts[1], pts[0], pts[2]) > 0 {
            non_zero_append(poly, pts[1])
        }

        vlen :u32 = u32(len(vertList))
        non_zero_append(vertList, ShapeVertex2D{
            uvw = {0,0,0},
            color = color,
            pos = pts[0],
        })
        non_zero_append(vertList, ShapeVertex2D{
            uvw = {-0.5,0,0.5},
            color = color,
            pos = pts[1],
        })
        non_zero_append(vertList, ShapeVertex2D{
            uvw = {-1,-1,1},
            color = color,
            pos = pts[2],
        })
        if _reverse {
            vertList[vlen].uvw.x *= -1
            vertList[vlen + 1].uvw.x *= -1
            vertList[vlen + 2].uvw.x *= -1

            vertList[vlen].uvw.y *= -1
            vertList[vlen + 1].uvw.y *= -1
            vertList[vlen + 2].uvw.y *= -1
        }

        non_zero_append(indList, vlen, vlen + 1, vlen + 2)
       
        return .None
    }

    F :matrix[4,4]f32

    reverseOrientation :: #force_inline proc "contextless" (F:matrix[4,4]f32) -> matrix[4,4]f32 {
        return {
            -F[0,0], -F[0,1], F[0,2], F[0,3],
            -F[1,0], -F[1,1], F[1,2], F[1,3],
            -F[2,0], -F[2,1], F[2,2], F[2,3],
            -F[3,0], -F[3,1], F[3,2], F[3,3],
        }
    }
    repeat := false
    subdiv :f32 = 0.0

    if _subdiv == 0.0 {
        switch curveType {
            case .Line:
                non_zero_append(poly, pts[0])
                return .None
            case .Quadratic:
                F = {
                    0,              0,              0,          0,
                    -1.0/3.0,       0,              1.0/3.0,    0,
                    -2.0/3.0,       -1.0/3.0,       2.0/3.0,    0,
                    -1,             -1,             1,          1,
                }
            case .Serpentine:
                t1 := math.sqrt_f32(9.0 * outD[1] * outD[1] - 12 * outD[0] * outD[2])
                ls := 3.0 * outD[1] - t1
                lt := 6.0 * outD[0]
                ms := 3.0 * outD[1] + t1
                mt := lt
                ltMinusLs := lt - ls
                mtMinusMs := mt - ms
    
                F = {
                    ls * ms,                                                            ls * ls * ls,                           ms * ms * ms,           0,
                    (1.0 / 3.0) * (3.0 * ls * ms - ls * mt - lt * ms),                  ls * ls * (ls - lt),                    ms * ms * (ms - mt),    0,
                    (1.0 / 3.0) * (lt * (mt - 2.0 * ms) + ls * (3.0 * ms - 2.0 * mt)),  ltMinusLs * ltMinusLs * ls,             mtMinusMs * mtMinusMs * ms,             0,
                    ltMinusLs * mtMinusMs,                                              -(ltMinusLs * ltMinusLs * ltMinusLs),   -(mtMinusMs * mtMinusMs * mtMinusMs),   1,
                }
    
                if F[0,0] > 0.0 do reverse = true
            case .Loop:
                t1 := math.sqrt_f32(4 * outD[0] * outD[2] - 3 * outD[1] * outD[1])
                ls := outD[1] - t1
                lt := 2 * outD[0]
                ms := outD[1] + t1
                mt := lt
    
                ql := ls / lt
                qm := ms / mt
               
                if !_repeat && 0.0 < ql && ql < 1.0 {
                    repeat = true
                    subdiv = ql
                } else if !_repeat && 0.0 < qm && qm < 1.0 {
                    repeat = true
                    subdiv = qm
                } else {
                    ltMinusLs := lt - ls
                    mtMinusMs := mt - ms
    
                    F = {
                        ls * ms,                                                            ls * ls * ms,                           ls * ms * ms,           0,
                        (1.0/3.0) * (-ls * mt - lt * ms + 3.0 * ls * ms),
                        -(1.0 / 3.0) * ls * (ls * (mt - 3.0 * ms) + 2.0 * lt * ms),
                        -(1.0 / 3.0) * ms * (ls * (2.0 * mt - 3.0 * ms) + lt * ms),    0,
                        (1.0/3.0) * (lt * (mt - 2.0 * ms) + ls * (3.0 * ms - 2.0 * mt)),
                        (1.0/3.0) * ltMinusLs * (ls * (2.0 * mt - 3.0 * ms) + lt * ms),
                        (1.0/3.0) * mtMinusMs * (ls * (mt - 3.0 * ms) + 2.0 * lt * ms),   0,
                        ltMinusLs * mtMinusMs,  -(ltMinusLs * ltMinusLs) * mtMinusMs,   -ltMinusLs * mtMinusMs * mtMinusMs, 1,
                    }
          
                    reverse = F[1, 0] > 0
                }
            case .Cusp:
                ls := outD[2]
                lt := 3.0 * outD[1]
                lsMinusLt := ls - lt
                F = {
                    ls,                         ls * ls * ls,                       1,  0,
                    (ls - (1.0 / 3.0) * lt),    ls * ls * lsMinusLt,                1,  0,
                    ls - (2.0 / 3.0) * lt,      lsMinusLt * lsMinusLt * ls,         1,  0,
                    lsMinusLt,                  lsMinusLt * lsMinusLt * lsMinusLt,  1,  1,
                }
                reverse = true
            case .Unknown:
                panicLog("GetCubicCurveType: unknown curve type")
        }
    }
   

    if repeat || _subdiv != 0.0 {
        //TODO Quadratic
        if subdiv == 0.0 {
            subdiv = _subdiv
        }
        x01 := (pts[1].x - pts[0].x) * subdiv + pts[0].x
        y01 := (pts[1].y - pts[0].y) * subdiv + pts[0].y
        x12 := (pts[2].x - pts[1].x) * subdiv + pts[1].x
        y12 := (pts[2].y - pts[1].y) * subdiv + pts[1].y

        x23 := (pts[3].x - pts[2].x) * subdiv + pts[2].x
        y23 := (pts[3].y - pts[2].y) * subdiv + pts[2].y

        x012 := (x12 - x01) * subdiv + x01
        y012 := (y12 - y01) * subdiv + y01

        x123 := (x23 - x12) * subdiv + x12
        y123 := (y23 - y12) * subdiv + y12

        x0123 := (x123 - x012) * subdiv + x012
        y0123 := (y123 - y012) * subdiv + y012

        // non_zero_append(indList, u32(len(vertList)))
        // non_zero_append(indList, u32(len(vertList)) + 1)
        // non_zero_append(indList, u32(len(vertList)) + 2)

        // non_zero_append(vertList, ShapeVertex2D{
        //     uvw = {1, 0, 0},
        //     color = color,
        //     pos = pts[0],
        // })
        // non_zero_append(vertList, ShapeVertex2D{
        //     uvw = {1, 0, 0},
        //     color = color,
        //     pos = PointF{x0123, y0123 },
        // })
        // non_zero_append(vertList, ShapeVertex2D{
        //     uvw = {1, 0, 0},
        //     color = color,
        //     pos = pts[3],
        // })

        err := _Shapes_ComputeLine(poly, vertList, indList, {pts[0], { x01, y01 }, { x012, y012 }, { x0123, y0123 }}, type, color, _reverse, 0.0, true)
        if err != .None do return err
        err = _Shapes_ComputeLine(poly, vertList, indList, {{ x0123, y0123 }, { x123, y123 }, { x23, y23 }, pts[3]}, type, color, _reverse, 0.0, true)
        if err != .None do return err

        return .None
    }

    if reverse != _reverse {
        F = reverseOrientation(F)
    }

    appendLine :: proc (poly:^[dynamic]PointF, vertList:^[dynamic]ShapeVertex2D, indList:^[dynamic]u32, pts:[]PointF, F:matrix[4,4]f32, color:Point3DwF) {
        if len(pts) == 2 {
            return
        }
        start :u32 = u32(len(vertList))
        non_zero_append(vertList, ShapeVertex2D{
            uvw = {F[0,0], F[0,1], F[0,2]},
            color = color,
        })
        non_zero_append(vertList, ShapeVertex2D{
            uvw = {F[1,0], F[1,1], F[1,2]},
            color = color,
        })
        non_zero_append(vertList, ShapeVertex2D{
            uvw = {F[2,0], F[2,1], F[2,2]},
            color = color,
        })
        non_zero_append(vertList, ShapeVertex2D{
            uvw = {F[3,0], F[3,1], F[3,2]},
            color = color,
        })
        if len(pts) == 3 {
            vertList[start].pos = pts[0]
            vertList[start+1].pos = CvtQuadraticToCubic0(pts[0], pts[1])
            vertList[start+2].pos = CvtQuadraticToCubic1(pts[2], pts[1])
            vertList[start+3].pos = pts[2]
        } else {// 4
            vertList[start].pos = pts[0]
            vertList[start+1].pos = pts[1]
            vertList[start+2].pos = pts[2]
            vertList[start+3].pos = pts[3]
        }
        //triangulate
        for i:u32 = 0; i < 4; i += 1 {
            for j:u32 = i + 1; j < 4; j += 1 {
                if vertList[start + i].pos == vertList[start + j].pos {
                    indices :[3]u32 = {start, start, start}
                    idx:u32 = 0
                    for k:u32 = 0; k < 4; k += 1 {
                        if k != j {
                            indices[idx] += k
                            idx += 1
                        }
                    }
                    non_zero_append(indList, ..indices[:])
                    return
                } 
            }
        }
        for i:u32 = 0; i < 4; i += 1 {
            indices :[3]u32 = {start, start, start}
            idx:u32 = 0
            for j:u32 = 0; j < 4; j += 1 {
                if j != i {
                    indices[idx] += j
                    idx += 1
                }
            }
            if PointInTriangle(vertList[start + i].pos, vertList[indices[0]].pos, vertList[indices[1]].pos, vertList[indices[2]].pos) {
                for k:u32 = 0; k < 3; k += 1 {
                    non_zero_append(indList, indices[k])
                    non_zero_append(indList, indices[(k + 1)%3])
                    non_zero_append(indList, start + i)
                }
                if i == 1 {
                    if PointLineLeftOrRight(pts[2], pts[0], pts[3]) > 0 {
                        non_zero_append(poly, pts[1])
                    }
                } else if i == 2 {
                    if PointLineLeftOrRight(pts[1], pts[0], pts[3]) > 0 {
                        non_zero_append(poly, pts[1])
                    }
                }
                return
            }
        }

        b, _ := LinesIntersect(vertList[start].pos, vertList[start + 2].pos, vertList[start + 1].pos, vertList[start + 3].pos)
        if b {
            if linalg.length2(vertList[start + 2].pos - vertList[start].pos) < linalg.length2(vertList[start + 3].pos - vertList[start + 1].pos) {
                non_zero_append(indList, start, start + 1, start + 2, start, start + 2, start + 3)
            } else {
                non_zero_append(indList, start, start + 1, start + 3, start + 1, start + 2, start + 3)
            }
            if PointLineLeftOrRight(pts[1], pts[0], pts[3]) > 0 {
                non_zero_append(poly, pts[1])
            }
            if PointLineLeftOrRight(pts[2], pts[0], pts[3]) > 0 {
                non_zero_append(poly, pts[2])
            }
            return
        }
        b, _ = LinesIntersect(vertList[start].pos, vertList[start + 3].pos, vertList[start + 1].pos, vertList[start + 2].pos)
        if b {
            if linalg.length2(vertList[start + 3].pos - vertList[start].pos) < linalg.length2(vertList[start + 2].pos - vertList[start + 1].pos) {
                non_zero_append(indList, start, start + 1, start + 3, start, start + 3, start + 2)
            } else {
                non_zero_append(indList, start, start + 1, start + 2, start + 2, start + 1, start + 3)
            }
            if PointLineLeftOrRight(pts[1], pts[0], pts[3]) > 0 {
                non_zero_append(poly, pts[1])
            }
            if PointLineLeftOrRight(pts[2], pts[0], pts[3]) > 0 {
                non_zero_append(poly, pts[2])
            }
            return
        }
        if linalg.length2(vertList[start + 1].pos - vertList[start].pos) < linalg.length2(vertList[start + 3].pos - vertList[start + 2].pos) {
            non_zero_append(indList, start, start + 2, start + 1, start, start + 1, start + 3)
        } else {
            non_zero_append(indList, start, start + 2, start + 3, start + 3, start + 2, start + 1)
        }
        //TODO
    }
    non_zero_append(poly, pts[0])
    appendLine(poly, vertList, indList, pts_[:len(pts)], F, color)

    return .None
}


Shapes_ComputePolygon :: proc(poly:^Shapes, allocator := context.allocator) -> (res:^RawShape = nil, err:ShapesError = .None) {
    vertList:[dynamic]ShapeVertex2D = make_non_zeroed_dynamic_array([dynamic]ShapeVertex2D, allocator)

    indList:[dynamic]u32 = make_non_zeroed_dynamic_array([dynamic]u32, context.temp_allocator)
    polyT:[dynamic]PointF = make_non_zeroed_dynamic_array([dynamic]PointF, context.temp_allocator)
    //polyT1:[dynamic]PointF = make_non_zeroed_dynamic_array([dynamic]PointF, context.temp_allocator)
    //polyT2:[dynamic]PointF = make_non_zeroed_dynamic_array([dynamic]PointF, context.temp_allocator)
    nPolysT:[dynamic]u32 = make_non_zeroed_dynamic_array([dynamic]u32, context.temp_allocator)
    defer {
        delete(indList)
        delete(polyT)
        delete(nPolysT)
        //delete(polyT2)
        //delete(polyT1)
    }

    res = new_non_zeroed(RawShape, allocator)
    defer if err != .None {
        delete(vertList)
        free(res, allocator)
        res = nil
    }

    start :u32 = 0
    ns :u32 = 0
    polyLen :u32 = u32(len(poly.poly))
    typeIdx :u32 = 0
    for n,i in poly.nPolys {
        //clear(&polyT2)
        //clear(&polyT1)

        rev := GetPolygonOrientation(poly.poly[start:start+n]) == .Clockwise ? true : false

        for i:u32 = start; i < start+n; typeIdx += 1 {
            SPLIT_CURVE :: proc "contextless" (poly:[]PointF, pts:[$N]PointF, start:u32) -> f32 {
                for p, i in poly {
                    if !(u32(i) >= start && u32(i) < start + u32(N)) {
                        when N == 3 {
                            if PointInTriangle(p, pts[0], pts[1], pts[2]) {
                                t := PointDeltaInLine(p, pts[0], pts[2])
                                assert_contextless(t >= 0.0 && t <= 1.0)
                                return t
                            }
                        } else when N == 4 {
                            res, _ := LinesIntersect(pts[0], pts[2], pts[1], pts[3])
                            if res {
                                if PointInPolygon(p, []PointF{pts[0], pts[1], pts[2], pts[3]}) {
                                    t := PointDeltaInLine(p, pts[0], pts[3])
                                    assert_contextless(t >= 0.0 && t <= 1.0)
                                    return t
                                }
                            }
                        } else {
                            #assert(N == 3 || N == 4)
                        }
                    } 
                }
                return 0.0
            }
            if poly.types[typeIdx] == .Line {
                if poly.colors != nil && poly.colors[i] != nil {
                    non_zero_append(&polyT, poly.poly[i])
                }
                if poly.strokeColors != nil && poly.strokeColors[i] != nil && poly.thickness[i] > 0 {
                    //TODO
                }
                i += 1
            } else if poly.types[typeIdx] == .Quadratic {
                pts := [3]PointF{poly.poly[i], poly.poly[i+1], i + 2 == u32(len(poly.poly)) ? poly.poly[start] : poly.poly[i+2]}
                subdiv := SPLIT_CURVE(poly.poly, pts, i)
                if poly.colors != nil && poly.colors[i] != nil {
                    err = _Shapes_ComputeLine(&polyT,
                        &vertList,
                        &indList,
                        pts[:],
                        .Quadratic,
                        poly.colors[i].?,
                        rev,
                        subdiv,)
                    if err != .None do return
                }
                if poly.strokeColors != nil && poly.strokeColors[i] != nil && poly.thickness[i] > 0 {
                   //TODO
                }
                i += 2
            } else {
                CALC_CUBIC :: proc (polyT:^[dynamic]PointF,
                    vertList:^[dynamic]ShapeVertex2D,
                    indList:^[dynamic]u32,
                    pts:[]PointF,
                    color:Point3DwF,
                    _reverse := false,
                    _subdiv:f32 = 0.0) -> (err:ShapesError = .None) {

                    ex: Maybe(PointF)
                    vlen := len(vertList^)
                    err = _Shapes_ComputeLine(polyT, vertList, indList, pts, .Unknown, color, _reverse, _subdiv, )
                    if err != .None do return
                    return
                }
                pts := [4]PointF{poly.poly[i], poly.poly[i+1], poly.poly[i+2], i + 3 == u32(len(poly.poly)) ? poly.poly[start] : poly.poly[i+3]}
                subdiv := SPLIT_CURVE(poly.poly, pts, i)
                assert(subdiv >= 0.0 && subdiv <= 1.0)
                if poly.colors != nil && poly.colors[i] != nil {
                    err = CALC_CUBIC(&polyT,
                        &vertList,
                        &indList,
                        pts[:],
                        poly.colors[i].?,
                        rev,
                        subdiv)
                    if err != .None do return
                }
                if poly.strokeColors != nil && poly.strokeColors[i] != nil && poly.thickness[i] > 0 {
                    //TODO
                }
                i += 3
            }
        }
        non_zero_append(&nPolysT, u32(len(polyT)) - ns)
        // if len(polyT1) > 0 {
        //     non_zero_append(&polyT, ..polyT1[:])
        //     non_zero_append(&nPolysT, auto_cast len(polyT1))
        // }
        // if len(polyT2) > 0 {
        //     non_zero_append(&polyT, ..polyT2[:])
        //     non_zero_append(&nPolysT, auto_cast len(polyT2))
        // }
        start += n
        ns = u32(len(polyT))
    }

    res.indices = TrianguatePolygons(polyT[:], nPolysT[:], allocator) //TODO
    defer if err != .None {
        delete(res.indices, allocator)
    }
    start = 0
    vLen :u32 = auto_cast len(vertList)//Existing Curve Vertices Length
    for _, i in nPolysT {
        for p in polyT[start:start+nPolysT[i]] {
            non_zero_append(&vertList, ShapeVertex2D{
                pos = p,
                uvw = {1,0,0},
                color = poly.colors[i].?,
            })
        }
        start += nPolysT[i]
    }
    for _, i in res.indices {
        res.indices[i] += vLen
    }
    if len(indList) > 0 {
        res.indices = resize_non_zeroed_slice(res.indices, len(res.indices) + len(indList), allocator)
        intrinsics.mem_copy_non_overlapping(&res.indices[len(res.indices) - len(indList)], &indList[0], len(indList) * size_of(u32))
    }
   
    shrink(&vertList)
    res.vertices = vertList[:]
    return
}
