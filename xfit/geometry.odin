package xfit

//TODO

import "core:math"
import "core:math/linalg"

RawShape :: struct {
    vertices : [][]shapeVertex2D,
    indices:[][]u32,
    colors:[]Point3DwF,
}

CurveType :: enum {
    Unkown,
    Line,
    Serpentine,
    Loop,
    Curp,
    Quadratic,
}

LineError :: enum {
    None,
    IsPointNotLine,
    IsNotCurve,
    InvaildLine,
    OutOfIdx,    
}

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

Line :: struct {
    start:PointF,
    control0:PointF,
    control1:PointF,
    type:CurveType,
}

Line_LineInit :: #force_inline proc "contextless" (start:PointF) -> Line {
    return {
        start = start,
        type = .Line
    }
}
Line_QuadraticInit :: #force_inline proc "contextless" (start:PointF, control:PointF) -> Line {
    return {
        start = start,
        control0 = control,
        control1 = control,
        type = .Quadratic
    }
}

ShapesNode :: struct {
    lines:[]Line,
    color:Maybe(Point3DwF),
    strokeColor:Maybe(Point3DwF),
    nPolygons:[]u32,
    thickness:f32,
}

Shapes :: struct {
    nodes:[]ShapesNode,
}

CvtQuadraticToCubic0 :: #force_inline proc "contextless" (_start : PointF, _control : PointF) -> PointF {
    return { _start.x + (2/3) * (_control.x - _start.x), _start.y + (2/3) * (_control.y - _start.y) }
}
CvtQuadraticToCubic1 :: #force_inline proc "contextless" (_end : PointF, _control : PointF) -> PointF {
    return CvtQuadraticToCubic0(_end, _control)
}

