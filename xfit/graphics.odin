package xfit

//TODO

import "core:math"
import "core:math/linalg"

shapeVertex2D :: struct #align(1) {
    pos: PointF,
    uvw: linalg.Vector3f32,
};

ResourceUsage :: enum {GPU,CPU}