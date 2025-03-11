package xfit

//TODO

import "core:math"
import "core:slice"
import "core:math/linalg"
import "base:runtime"
import "base:intrinsics"

RawShape :: struct {
    vertices : []ShapeVertex2D,
    indices:[]u32,
}

CurveType :: enum {
    Line,
    Unkown,
    Serpentine,
    Loop,
    Cusp_Inf,
    Cusp_Inflection_Inf,
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


GetCubicCurveType :: proc "contextless" (_start:[2]$T, _control0:[2]T, _control1:[2]T, _end:[2]T) -> (type:CurveType = .Unkown, err:ShapesError = .None, outD:[3]T) where intrinsics.type_is_float(T) {
    if _start == _control0 && _control0 == _control1 && _control1 == _end {
        err = .IsPointNotLine
        return
    }

    c1 := -3 * _start + 3 * _control0
    c2 := 3 * _start - 6 * _control0 + 3 * _control1
    c3 := -3 * _start + 3 * _control0 - 3 * _control1 + _end

    outD[0] = linalg.matrix2_determinant(
        matrix[2, 2]T{
            c3.x, c3.y,
            c2.x, c2.y,
        }
    )
    outD[1] = linalg.matrix2_determinant(
        matrix[2, 2]T{
            c3.x, c3.y,
            c1.x, c1.y,
        }
    )
    outD[2] = linalg.matrix2_determinant(
        matrix[2, 2]T{
            c2.x, c2.y,
            c1.x, c1.y,
        }
    )
    outD = linalg.normalize(outD)

    D := 3 * outD[1] * outD[1] - 4 * outD[2] * outD[0]

    if outD[0] > epsilon(T) {
        discr := outD[0] * outD[0] * D

        if discr > epsilon(T) {
            type = .Serpentine
        } else if discr < -epsilon(T) {
            type = .Loop
        }
        type = .Cusp_Inflection_Inf
    } else if outD[1] > epsilon(T) {
        type = .Cusp_Inf
    } else if outD[2] > epsilon(T) {
        type = .Quadratic
    } else {
        type = .Line
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

@(private="file") _Shapes_ComputeLine :: proc(vertList:^[dynamic]ShapeVertex2D, indList:^[dynamic]u32, pts:[]PointF, type:CurveType, color:Point3DwF) -> ShapesError {
    curveType := type
    err:ShapesError = .None

    F2 : matrix[4,4]f32
    pts2 : [4][2]f32
    pts_:[4][2]f32
    intrinsics.mem_copy_non_overlapping(&pts_[0], &pts[0], len(pts) * size_of(PointF))

    reverse := false
    segmentCreated := false
    outD:[3]f32 = {0, 0, 0}
    if curveType != .Line && curveType != .Quadratic {
        curveType, err, outD = GetCubicCurveType(pts[0], pts[1], pts[2], pts[3])
        if err != .None do return err
    }

    k_INVERSE_M :matrix[4,4]f32 = {
        1, 0, 0, 0,
        1, 1.0/3.0, 0, 0,
        1, 2.0/3.0, 1.0/3.0, 0,
        1, 1, 1, 1,
    }
    F :matrix[4,4]f32

    solveQuadratic :: proc "contextless" (a:$T, b:T, c:T) -> (T,T) where intrinsics.type_is_float(T) {
        if a == 0 do panicLog("solveQuadratic: a == 0")

        if b != 0 {
            b_ := b * 0.5
            q := -(b_ + (b_ < 0 ? -1 : 1) * math.sqrt(abs(b_ * b_ - a * c)))
            return q / a, c / q
        } else {
            n := math.sqrt(abs(a * c))
            return -n / a, n / a
        }
    }

    loopNeedReverse :: #force_inline proc "contextless" (d1:$T, k1:T) -> bool where intrinsics.type_is_float(T) {
        return (d1 > epsilon(T) && k1 < -epsilon(T)) || (d1 < -epsilon(T) && k1 > epsilon(T))
    }

    splitSegment :: proc "contextless" (pts:[4][2]$T, F:matrix[4,4]T, t:T) -> (outPts1:[4][2]T, outPts2:[4][2]T, outF1:matrix[4,4]T, outF2:matrix[4,4]T) where intrinsics.type_is_float(T) {
        if !(0 < t && t < 1) do panicLog("splitSegment: t is not in [0, 1]")

        //TODO split Quadratic and Line

        outPts1, outPts2 = LineSplitCubic(pts, t)
        Fs : [4][3]T = {
            {F[0, 0], F[0, 1], F[0, 2]},
            {F[1, 0], F[1, 1], F[1, 2]},
            {F[2, 0], F[2, 1], F[2, 2]},
            {F[3, 0], F[3, 1], F[3, 2]},
        }
        oF1, oF2 := LineSplitCubic(Fs, t)
        outF1 = {
            oF1[0][0], oF1[0][1], oF1[0][2], 0,
            oF1[1][0], oF1[1][1], oF1[1][2], 0,
            oF1[2][0], oF1[2][1], oF1[2][2], 0,
            oF1[3][0], oF1[3][1], oF1[3][2], 1,
        }
        outF2 = {
            oF2[0][0], oF2[0][1], oF2[0][2], 0,
            oF2[1][0], oF2[1][1], oF2[1][2], 0,
            oF2[2][0], oF2[2][1], oF2[2][2], 0,
            oF2[3][0], oF2[3][1], oF2[3][2], 1,
        }
        return
    }

    reverseOrientation :: #force_inline proc "contextless" (F:matrix[4,4]f32) -> matrix[4,4]f32 {
        return {
            -F[0][0], -F[0][1], -F[0][2], F[0][3],
            -F[1][0], -F[1][1], -F[1][2], F[1][3],
            -F[2][0], -F[2][1], -F[2][2], F[2][3],
            -F[3][0], -F[3][1], -F[3][2], F[3][3],
        }
    }

    switch curveType {
        case .Line:
            return .None
        case .Quadratic:
            F = {
                1, 0,   0,   0,
                1, 1.0/3.0, 0,   0,
                1, 2.0/3.0, 1.0/3.0, 0,
                1, 1,   1,   1,
            }
            reverse = outD[2] < -epsilon(f32)
        case .Serpentine:
        case .Cusp_Inflection_Inf:
            tl, tm : f32 = solveQuadratic(-3.0 * outD[0], 3.0 * outD[1], -outD[2])
            l :[2]f32 = {tl, 1}
            m :[2]f32 = {tm, 1}
            l = linalg.normalize(l)
            m = linalg.normalize(m)
            F = {
                l.x * m.x,                  l.x * l.x * m.x,        l.x * m.x * m.x,        0,
                -m.y * l.x - l.y * m.x,     -3.0 * l.y * l.x * l.x,   -3.0 * m.y * m.x * m.x,   0,
                l.y * m.y,                  3.0 * l.y * l.y * l.x,    3.0 * m.y * m.y * m.x,    0,
                0,                          -l.y * l.y * l.y,       -m.y * m.y * m.y,       1,
            }
            F *= k_INVERSE_M
            reverse = outD[0] < -epsilon(f32)
        case .Loop:
            td, te : f32 = solveQuadratic(-outD[0] * outD[0], outD[0] * outD[1], outD[2] * outD[0] - outD[1] * outD[1])
            l :[2]f32 = {td, 1}
            m :[2]f32 = {te, 1}
            l = linalg.normalize(l)
            m = linalg.normalize(m)
            F = {
                l.x * m.x,                  l.x * l.x * m.x,                            l.x * m.x * m.x,                            0,
                -m.y * l.x - m.x * l.y,     -m.y * l.x * l.x - 2.0 * l.y * m.x * l.x,     -l.y * m.x * m.x - 2.0 * m.y * l.x * m.x,     0,
                l.y * m.y,                  m.x * l.y * l.y + 2.0 * m.y * l.x * l.y,      l.x * m.y * m.y + 2.0 * l.y * m.x * m.y,      0,
                0,                          -l.y * l.y * m.y,                           -l.y * m.y * m.y,                           1,
            }
            F *= k_INVERSE_M
            l.x /= l.y
            m.x /= m.y
           
            if l.x > epsilon(f32) && l.x < 1 - epsilon(f32) {   
                pts_, pts2, F, F2 = splitSegment(pts_, F, l.x)
                segmentCreated = true
            } else if m.x > epsilon(f32) && m.x < 1 - epsilon(f32) {
                pts_, pts2, F, F2 = splitSegment(pts_, F, m.x)
                segmentCreated = true
            }
            reverse = loopNeedReverse(outD[0], F[0, 1])
            if segmentCreated && loopNeedReverse(outD[0], F2[0, 1]) {
                F2 = reverseOrientation(F2)
            }
        case .Cusp_Inf:
            l :PointF = linalg.normalize(PointF{outD[2],3 * outD[1]})
            F = {
                l.x,    l.x * l.x * l.x,        1,  0,
                -l.y,   -3.0 * l.y * l.x * l.x,   0,  0,
                0,      3.0 * l.y * l.y * l.x,    0,  0,
                0,      -l.y * l.y * l.y,       0,  1,
            }
            reverse = outD[2] < -epsilon(f32)
        case .Unkown:
            panicLog("GetCubicCurveType: unknown curve type")
    }
    if reverse {
        F = reverseOrientation(F)
    }

    appendLine :: proc (vertList:^[dynamic]ShapeVertex2D, indList:^[dynamic]u32, pts:[]PointF, F:matrix[4,4]f32, color:Point3DwF) {
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
            return
        }
        b, _ = LinesIntersect(vertList[start].pos, vertList[start + 3].pos, vertList[start + 1].pos, vertList[start + 2].pos)
        if b {
            if linalg.length2(vertList[start + 3].pos - vertList[start].pos) < linalg.length2(vertList[start + 2].pos - vertList[start + 1].pos) {
                non_zero_append(indList, start, start + 1, start + 3, start, start + 3, start + 2)
            } else {
                non_zero_append(indList, start, start + 1, start + 2, start + 2, start + 1, start + 3)
            }
            return
        }
        if linalg.length2(vertList[start + 1].pos - vertList[start].pos) < linalg.length2(vertList[start + 3].pos - vertList[start + 2].pos) {
            non_zero_append(indList, start, start + 2, start + 1, start, start + 1, start + 3)
        } else {
            non_zero_append(indList, start, start + 2, start + 3, start + 3, start + 2, start + 1)
        }
    }
    appendLine(vertList, indList, pts_[:len(pts)], F, color)
    if segmentCreated {
        appendLine(vertList, indList, pts2[:len(pts)], F2, color)
    }
    return .None
}

Shapes_ComputePolygon :: proc(poly:^Shapes, allocator := context.allocator) -> (res:^RawShape = nil, err:ShapesError = .None) {
    vertList:[dynamic]ShapeVertex2D = make_non_zeroed_dynamic_array([dynamic]ShapeVertex2D, allocator)

    indList:[dynamic]u32 = make_non_zeroed_dynamic_array([dynamic]u32, context.temp_allocator)
    polyT:[dynamic]PointF = make_non_zeroed_dynamic_array([dynamic]PointF, context.temp_allocator)
    polyT1:[dynamic]PointF = make_non_zeroed_dynamic_array([dynamic]PointF, context.temp_allocator)
    polyT2:[dynamic]PointF = make_non_zeroed_dynamic_array([dynamic]PointF, context.temp_allocator)
    nPolysT:[dynamic]u32 = make_non_zeroed_dynamic_array([dynamic]u32, context.temp_allocator)
    defer {
        delete(indList)
        delete(polyT)
        delete(nPolysT)
        delete(polyT2)
        delete(polyT1)
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
    for n,i in poly.nPolys {
        typeIdx :u32 = 0
        clear(&polyT2)
        clear(&polyT1)
        for i:u32 = start; i < start+n; typeIdx += 1 {
            prevIdx :: #force_inline proc "contextless" (i:u32, len:u32) -> u32 {
                if i > 0 do return i - 1
                return len - 1
            }
            nextIdx :: #force_inline proc "contextless" (i:u32, len:u32) -> u32 {
                if i < len - 1 do return i + 1
                return 0
            }
            if poly.types[typeIdx] == .Line {
                if poly.colors != nil && poly.colors[i] != nil {
                    non_zero_append(&polyT, poly.poly[i])
                }
                if poly.strokeColors != nil &&poly.strokeColors[i] != nil && poly.thickness[i] > 0 {
                    p := LineExtendPoint(poly.poly[prevIdx(i, polyLen)], poly.poly[i], poly.poly[nextIdx(i, polyLen)], poly.thickness[i], .Counterclockwise)
                    p2 := LineExtendPoint(poly.poly[prevIdx(i, polyLen)], poly.poly[i], poly.poly[nextIdx(i, polyLen)], -poly.thickness[i], .Counterclockwise)
                    non_zero_append(&polyT1, p)
                    non_zero_append(&polyT2, p2)
                }
                i += 1
            } else if poly.types[typeIdx] == .Quadratic {
                if poly.colors != nil && poly.colors[i] != nil {
                    non_zero_append(&polyT, poly.poly[i])
                    err = _Shapes_ComputeLine(&vertList, &indList, poly.poly[i:i+3], .Quadratic, poly.colors[i].?)
                    if err != .None do return
                }
                if poly.strokeColors != nil && poly.strokeColors[i] != nil && poly.thickness[i] > 0 {
                    p:[3]PointF
                    p2:[3]PointF
                    p[0] = LineExtendPoint(poly.poly[prevIdx(i, polyLen)], poly.poly[i], poly.poly[i+1], poly.thickness[i], .Counterclockwise)
                    p[1] = LineExtendPoint(poly.poly[i], poly.poly[i+1], poly.poly[i+2], poly.thickness[i], .Counterclockwise)
                    p[2] = LineExtendPoint(poly.poly[i+1], poly.poly[i+2], poly.poly[nextIdx(i, polyLen)], poly.thickness[i], .Counterclockwise)
                    
                    p2[0] = LineExtendPoint(poly.poly[prevIdx(i, polyLen)], poly.poly[i], poly.poly[i+1], -poly.thickness[i], .Counterclockwise)
                    p2[1] = LineExtendPoint(poly.poly[i], poly.poly[i+1], poly.poly[i+2], -poly.thickness[i], .Counterclockwise)
                    p2[2] = LineExtendPoint(poly.poly[i+1], poly.poly[i+2], poly.poly[nextIdx(i, polyLen)], -poly.thickness[i], .Counterclockwise)

                    if PointLineDistance(p2[1], p[0], p[2]) > 0 {
                        pT := NearestPointBetweenPointAndLine(p2[1], p[0], p[2])
                        _, t := PointInLine(pT, p[0], p[2])
                        ps:[3]PointF
                        p, ps = LineSplitQuadratic(p, t)
                        err = _Shapes_ComputeLine(&vertList, &indList, p[:], .Quadratic, poly.strokeColors[i].?)
                        if err != .None do return
                        err = _Shapes_ComputeLine(&vertList, &indList, ps[:], .Quadratic, poly.strokeColors[i].?)
                        if err != .None do return
                        non_zero_append(&polyT1, p[0])
                        non_zero_append(&polyT1, ps[0])
                    } else {
                        err = _Shapes_ComputeLine(&vertList, &indList, p[:], .Quadratic, poly.strokeColors[i].?)
                        if err != .None do return
                        non_zero_append(&polyT1, p[0])
                    }
                    non_zero_append(&polyT2, p2[0])
                }
                i += 2
            } else {
                APPEND_CUBIC :: proc (polyT:^[dynamic]PointF, pts:[4]PointF) {
                    if PointLineDistance(pts[1], pts[0], pts[3]) > 0 {
                        non_zero_append(polyT, pts[1])
                    }
                    if PointLineDistance(pts[2], pts[0], pts[3]) > 0 {
                        non_zero_append(polyT, pts[2])
                    }
                }
                CALC_CUBIC :: proc (polyT:^[dynamic]PointF, vertList:^[dynamic]ShapeVertex2D, indList:^[dynamic]u32, pts:[4]PointF, color:Point3DwF) -> (err:ShapesError = .None) {
                    non_zero_append(polyT, pts[0])
                    vlen := len(vertList^)
                    err = _Shapes_ComputeLine(vertList, indList, []PointF{pts[0], pts[1], pts[2], pts[3]}, .Unkown, color)
                    if err != .None do return
                    if vlen + 4 < len(vertList^) {
                        APPEND_CUBIC(polyT, {vertList^[vlen - 1].pos, vertList^[vlen - 1 + 1].pos, vertList^[vlen - 1 + 2].pos, vertList^[vlen - 1 + 3].pos})
                        non_zero_append(polyT, vertList^[vlen - 1 + 3].pos)
                        APPEND_CUBIC(polyT, {vertList^[vlen - 1 + 3].pos, vertList^[vlen - 1 + 4].pos, vertList^[vlen - 1 + 5].pos, vertList^[vlen - 1 + 6].pos})
                    } else {
                        APPEND_CUBIC(polyT, {pts[0], pts[1], pts[2], pts[3]})
                    }
                    return
                }
                if poly.colors != nil && poly.colors[i] != nil {
                    err = CALC_CUBIC(&polyT, &vertList, &indList, {poly.poly[i], poly.poly[i+1], poly.poly[i+2], poly.poly[i+3]}, poly.colors[i].?)
                    if err != .None do return
                }
                if poly.strokeColors != nil && poly.strokeColors[i] != nil && poly.thickness[i] > 0 {
                    p:[4]PointF
                    p2:[4]PointF
                    p[0] = LineExtendPoint(poly.poly[prevIdx(i, polyLen)], poly.poly[i], poly.poly[i+1], poly.thickness[i], .Counterclockwise)
                    p[1] = LineExtendPoint(poly.poly[i], poly.poly[i+1], poly.poly[i+2], poly.thickness[i], .Counterclockwise)
                    p[2] = LineExtendPoint(poly.poly[i+1], poly.poly[i+2], poly.poly[i+3], poly.thickness[i], .Counterclockwise)
                    p[3] = LineExtendPoint(poly.poly[i+2], poly.poly[i+3], poly.poly[nextIdx(i, polyLen)], poly.thickness[i], .Counterclockwise)
                    
                    p2[0] = LineExtendPoint(poly.poly[prevIdx(i, polyLen)], poly.poly[i], poly.poly[i+1], -poly.thickness[i], .Counterclockwise)
                    p2[1] = LineExtendPoint(poly.poly[i], poly.poly[i+1], poly.poly[i+2], -poly.thickness[i], .Counterclockwise)
                    p2[2] = LineExtendPoint(poly.poly[i+1], poly.poly[i+2], poly.poly[i+3], -poly.thickness[i], .Counterclockwise)
                    p2[3] = LineExtendPoint(poly.poly[i+2], poly.poly[i+3], poly.poly[nextIdx(i, polyLen)], -poly.thickness[i], .Counterclockwise)

                    err = CALC_CUBIC(&polyT1, &vertList, &indList, {p[0], p[1], p[2], p[3]}, poly.strokeColors[i].?)
                    if err != .None do return
                    err = CALC_CUBIC(&polyT2, &vertList, &indList, {p2[0], p2[1], p2[2], p2[3]}, poly.strokeColors[i].?)
                    if err != .None do return
                }
                i += 3
            }
        }
        non_zero_append(&nPolysT, u32(len(polyT)) - ns)
        if len(polyT1) > 0 {
            non_zero_append(&polyT, ..polyT1[:])
            non_zero_append(&nPolysT, auto_cast len(polyT1))
        }
        if len(polyT2) > 0 {
            non_zero_append(&polyT, ..polyT2[:])
            non_zero_append(&nPolysT, auto_cast len(polyT2))
        }
        start += n
        ns = u32(len(polyT))
    }

    res.indices = TrianguatePolygons(polyT[:], nPolysT[:], allocator) //TODO
    defer if err != .None {
        delete(res.indices, allocator)
    }
    start = 0
    vLen :u32= auto_cast len(vertList)//Existing Curve Vertices Length
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
