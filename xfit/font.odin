package xfit

//TODO

import "core:math"
import "core:c"
import "core:mem"
import "core:slice"
import "core:math/linalg"
import "core:unicode"
import "core:unicode/utf8"
import "core:sync"
import "core:fmt"
import "base:runtime"
import "external/freetype"

FontError :: enum {
    None,
    InvalidHeader,
}

@(private="file") CharData :: struct {
    rawShape : ^RawShape,
    advanceX : f32,
}
@(private="file") CharNode :: struct #packed {
    size:u32,
    char:rune,
    advanceX:f32,
}

Font :: struct {}

@(private="file") SCALE_DEFAULT : f32 : 256

@(private="file") __Font :: struct {
    charArray : map[rune]CharData,
    height:f32,
    scale:f32,//default 1
    mutex:sync.Mutex,
}

FontRenderOpt :: struct {
    scale:PointF,    //(0,0) -> (1,1)
    offset:PointF,
    pivot:PointF,
    area:Maybe(PointF),
    color:Point3DwF,
    flag:ResourceUsage,
}

FontRenderOpt2 :: struct {
    opt:FontRenderOpt,
    ranges:[]FontRenderRange,
}

FontRenderRange :: struct {
    font:^Font,
    scale:PointF,    //(0,0) -> (1,1)
    color:Point3DwF,
    len:uint,
}

//convert font format to VFF(vector font file)
Font_ConvertFontFmtToVFF :: proc(_fontFmtData:[]byte, _fontFmtFaceIdx:uint) -> ([]byte, freetype.Error, ShapesError) {
    FTMoveTo :: proc "c" (to: ^freetype.Vector, user: rawptr) -> c.int {
        data : ^FontUserData = auto_cast user
        data.pen = PointF{f32(to.x) / (64 * data.scale), f32(to.y) / (64 * data.scale)}

        if data.idx > 0 {
            data.polygon.nPolys[data.nPoly] = data.nPolyLen
            data.nPoly += 1
            data.polygon.nTypes[data.nTypes] = data.nTypesLen
            data.nTypes += 1
            data.nPolyLen = 0
            data.nTypesLen = 0
        }
        return 0
    }
    FTLineTo :: proc "c" (to: ^freetype.Vector, user: rawptr) -> c.int {
        data : ^FontUserData = auto_cast user
        end := PointF{f32(to.x) / (64 * data.scale), f32(to.y) / (64 * data.scale)}
    
        data.polygon.poly[data.idx] = data.pen
        data.polygon.types[data.typeIdx] = .Line
        data.pen = end
        data.idx += 1
        data.nPolyLen += 1
        data.typeIdx += 1
        data.nTypesLen += 1
        return 0
    }
    FTConicTo :: proc "c" (control: ^freetype.Vector, to: ^freetype.Vector, user: rawptr) -> c.int {
        data : ^FontUserData = auto_cast user
        ctl := PointF{f32(control.x) / (64 * data.scale), f32(control.y) / (64 * data.scale)}
        end := PointF{f32(to.x) / (64 * data.scale), f32(to.y) / (64 * data.scale)}
    
        data.polygon.poly[data.idx] = data.pen
        data.polygon.poly[data.idx+1] = ctl
        data.polygon.types[data.typeIdx] = .Quadratic
        data.pen = end
        data.idx += 2
        data.nPolyLen += 2
        data.typeIdx += 1
        data.nTypesLen += 1
        return 0
    }
    FTCubicTo :: proc "c" (control0, control1, to: ^freetype.Vector, user: rawptr) -> c.int {
        data : ^FontUserData = auto_cast user
        ctl0 := PointF{f32(control0.x) / (64 * data.scale), f32(control0.y) / (64 * data.scale)}
        ctl1 := PointF{f32(control1.x) / (64 * data.scale), f32(control1.y) / (64 * data.scale)}
        end := PointF{f32(to.x) / (64 * data.scale), f32(to.y) / (64 * data.scale)}
    
        data.polygon.poly[data.idx] = data.pen
        data.polygon.poly[data.idx+1] = ctl0
        data.polygon.poly[data.idx+2] = ctl1
        data.polygon.types[data.typeIdx] = .Unknown
        data.pen = end
        data.idx += 3
        data.nPolyLen += 3
        data.typeIdx += 1
        data.nTypesLen += 1
        return 0
    }
    FontUserData :: struct {
        pen : PointF,
        polygon : ^Shapes,
        idx : u32,
        nPoly : u32,
        nPolyLen : u32,
        nTypes : u32,
        nTypesLen : u32,
        typeIdx : u32,
        scale : f32,
    }

    @static funcs : freetype.Outline_Funcs = {
        move_to = FTMoveTo,
        line_to = FTLineTo,
        conic_to = FTConicTo,
        cubic_to = FTCubicTo,
    }

    err : freetype.Error
    face : freetype.Face
    library:freetype.Library

    err = freetype.init_free_type(&library)
    if err != .Ok do panicLog(err)
    defer {
        err = freetype.done_free_type(library)
        if err != .Ok do panicLog(err)
    }

    err = freetype.new_memory_face(library, raw_data(_fontFmtData), auto_cast len(_fontFmtData), auto_cast _fontFmtFaceIdx, &face)
    if err != .Ok do return nil, err, .None
    defer freetype.done_face(face)

    err = freetype.set_char_size(face, 0, 16 * 256 * 64, 0, 0)
    if err != .Ok do return nil, err, .None

    outData := make_non_zeroed_dynamic_array([dynamic]byte, vkDefAllocator)
    defer if err != .Ok {
        delete(outData)
    }

    non_zero_append(&outData, 'v')
    non_zero_append(&outData, 'f')
    non_zero_append(&outData, 'f')
    non_zero_append(&outData, 0)

    non_zero_resize_dynamic_array(&outData, 4 + size_of(u32) + size_of(f32))
    //(transmute([^]u32)(&outData[4]))[0] = 0 ?갯수 알아내면 나중에 대입한다.
    (transmute([^]f32)(&outData[4 + size_of(f32)]))[0] = f32(face.size.metrics.height) / (64.0 * SCALE_DEFAULT)

    outDataIdx := len(outData)

    gIdx : c.uint
    charLen := 0
    charCode := freetype.get_first_char(face, &gIdx)
    for charCode != 0 {
        err = freetype.load_glyph(face, gIdx, {.No_Bitmap})
        if err != .Ok do panicLog(err)

        if face.glyph.outline.n_points == 0 {
            non_zero_resize_dynamic_array(&outData, len(outData) + size_of(CharNode))
            (transmute([^]CharNode)(&outData[len(outData) - size_of(CharNode)]))[0] = CharNode{
                size = 0,
                char = auto_cast charCode,
                advanceX = f32(face.glyph.advance.x) / (64.0 * SCALE_DEFAULT)
            }
            charCode = freetype.get_next_char(face, charCode, &gIdx)
            charLen += 1
            continue
        }
    
        if freetype.outline_get_orientation(&face.glyph.outline) == freetype.Orientation.FILL_RIGHT {
            freetype.outline_reverse(&face.glyph.outline)
        }
    
        poly : Shapes = {
            nPolys = make_non_zeroed([]u32, face.glyph.outline.n_points, context.temp_allocator),
            nTypes = make_non_zeroed([]u32, face.glyph.outline.n_points, context.temp_allocator),
            types = make_non_zeroed([]CurveType, face.glyph.outline.n_points, context.temp_allocator),
            poly = make_non_zeroed([]PointF, face.glyph.outline.n_points, context.temp_allocator),
        }
        defer {
            delete(poly.nPolys, context.temp_allocator)
            delete(poly.nTypes, context.temp_allocator)
            delete(poly.types, context.temp_allocator)
            delete(poly.poly, context.temp_allocator)
            delete(poly.colors, context.temp_allocator)
        }
        poly.nPolys[0] = 0
        data : FontUserData = {
            polygon = &poly,
            idx = 0,
            typeIdx = 0,
            nPoly = 0,
            nPolyLen = 0,
            nTypes = 0,
            nTypesLen = 0,
            scale = SCALE_DEFAULT,
        }
    
        err = freetype.outline_decompose(&face.glyph.outline, &funcs, &data)
        if err != .Ok do panicLog(err)

        if data.idx == 0 {
            non_zero_resize_dynamic_array(&outData, len(outData) + size_of(CharNode))
            (transmute([^]CharNode)(&outData[len(outData) - size_of(CharNode)]))[0] = CharNode{
                size = 0,
                char = auto_cast charCode,
                advanceX = f32(face.glyph.advance.x) / (64.0 * SCALE_DEFAULT)
            }
            charCode = freetype.get_next_char(face, charCode, &gIdx)
            charLen += 1
            continue
        } else {
            poly.nPolys[data.nPoly] = data.nPolyLen
            data.nPoly += 1
            poly.nTypes[data.nTypes] = data.nTypesLen
            data.nTypes += 1
            poly.poly = resize_non_zeroed_slice(poly.poly, data.idx, context.temp_allocator)
            poly.nPolys = resize_non_zeroed_slice(poly.nPolys, data.nPoly, context.temp_allocator)
            poly.nTypes = resize_non_zeroed_slice(poly.nTypes, data.nTypes, context.temp_allocator)
            poly.types = resize_non_zeroed_slice(poly.types, data.typeIdx, context.temp_allocator)
            poly.colors = make_non_zeroed([]Point3DwF, data.idx, context.temp_allocator)
            for &c in poly.colors {
                c = Point3DwF{0,0,0,1}//?no matter
            }
            poly.strokeColors = nil
            poly.thickness = nil

            rawP , shapeErr := Shapes_ComputePolygon(&poly, context.temp_allocator)
            if shapeErr != .None do return nil, .Ok, shapeErr
            defer RawShape_Free(rawP, context.temp_allocator)
            
            rawSize := auto_cast RawShape_BytesSize(rawP)
            len_ := len(outData)
            non_zero_resize_dynamic_array(&outData, len_ + size_of(CharNode) + rawSize)
            (transmute([^]CharNode)(&outData[len_]))[0] = CharNode{
                size = auto_cast rawSize,
                char = auto_cast charCode,
                advanceX = f32(face.glyph.advance.x) / (64.0 * SCALE_DEFAULT)
            }

            non_zero_resize_dynamic_array(&outData, len(outData) + rawSize)
            RawShape_ToCloneBytes(rawP, &outData[len_ + size_of(CharNode)])
        }
        charCode = freetype.get_next_char(face, charCode, &gIdx)
        charLen += 1
    }
    (transmute([^]u32)(&outData[4]))[0] = auto_cast charLen
    
    shrink(&outData)

    outSlice : []byte = outData[:] 
    return outSlice, err, .None
}

Font_Init :: proc(_vffData:[]byte) -> (^Font, FontError)  {
    //check VFF
    if !(_vffData[0] == 'v' && _vffData[1] == 'f' && _vffData[2] == 'f' && _vffData[3] == 0) {
        return nil, .InvalidHeader
    }

    err : FontError = .None

    font := new_non_zeroed(__Font)
    defer if err != .None do free(font)

    font.scale = 1.0

    font.charArray = make_map( map[rune]CharData)
    charLen := int((transmute([^]u32)(&_vffData[4]))[0])
    font.height = (transmute([^]f32)(&_vffData[4 + size_of(f32)]))[0]

    dataIdx := 4 + size_of(u32) + size_of(f32)
    for i in 0..<charLen {
        charNode := (transmute([^]CharNode)(&_vffData[dataIdx]))[0]
        dataIdx += size_of(CharNode)
        rawShape :^RawShape = charNode.size == 0 ? nil : RawShape_CloneFromBytes(_vffData[dataIdx:dataIdx + auto_cast charNode.size], vkDefAllocator)
        dataIdx += auto_cast charNode.size

        map_insert(&font.charArray, charNode.char, CharData{
            advanceX = charNode.advanceX,
            rawShape = rawShape,
        })
    }

    return cast(^Font)font, err
}

Font_Deinit :: proc(self:^Font) {
    self_:^__Font = auto_cast self
    sync.mutex_lock(&self_.mutex)
    for key,value in self_.charArray {
        RawShape_Free(value.rawShape, vkDefAllocator)
    }
    delete(self_.charArray)
    sync.mutex_unlock(&self_.mutex)
    free(self_)
}

Font_SetScale :: proc(self:^Font, scale:f32) {
    self_:^__Font = auto_cast self
    sync.mutex_lock(&self_.mutex)
    self_.scale = scale
    sync.mutex_unlock(&self_.mutex)
}

@(private="file") _Font_RenderString2 :: proc(_str:string,
_renderOpt:FontRenderOpt2,
vertList:^[dynamic]ShapeVertex2D,
indList:^[dynamic]u32,
allocator : runtime.Allocator) {
    i : int = 0
    opt := _renderOpt.opt

    for r in _renderOpt.ranges {
        opt.scale = _renderOpt.opt.scale * r.scale
        opt.color = r.color

        if r.len == 0 || i + auto_cast r.len >= len(_str) {
            _Font_RenderString(auto_cast r.font, _str[i:], opt, vertList, indList, allocator)
            break;
        } else {
            opt.offset = _Font_RenderString(auto_cast r.font, _str[i:i + auto_cast r.len], opt, vertList, indList, allocator)
            i += auto_cast r.len
        }
    }   
}

@(private="file") _Font_RenderString :: proc(self:^__Font, _str:string, _renderOpt:FontRenderOpt, _vertArr:^[dynamic]ShapeVertex2D,_indArr:^[dynamic]u32, allocator : runtime.Allocator) -> PointF {
    maxP : PointF = {min(f32), min(f32)}
    minP : PointF = {max(f32), max(f32)}

    offset : PointF = _renderOpt.offset

    for s in _str {
        if _renderOpt.area != nil && offset.y <= _renderOpt.area.?.y do break
        if s == '\n' {
            offset.y -= self.height
            offset.x = 0
            continue
        }
        minP = min_array(minP, offset)

        _Font_RenderChar(self, s, _vertArr, _indArr, &offset, _renderOpt.area, _renderOpt.scale, allocator)
        
        maxP = max_array(maxP, PointF{offset.x, offset.y + self.height})
    }

    size : PointF = _renderOpt.area != nil ? _renderOpt.area.? : (maxP - minP) * PointF{1,1}

    for &v in _vertArr^ {
        v.pos = _renderOpt.pivot * size * _renderOpt.scale
        v.color = _renderOpt.color
    }

    return offset * _renderOpt.scale
}

@(private="file") _Font_RenderChar :: proc(self:^__Font, _char:rune, _vertArr:^[dynamic]ShapeVertex2D, _indArr:^[dynamic]u32, offset:^PointF, area:Maybe(PointF), scale:PointF, allocator : runtime.Allocator) {
    ok := _char in self.charArray
    charD : ^CharData
    blk: if ok {
        charD = &self.charArray[_char]
    } else {
        ok = '□' in self.charArray
        if !ok do panicLog("not found □")
        charD = &self.charArray['□']
    }
    if area != nil && offset.x + charD.advanceX >= area.?.x {
        offset.y -= self.height
        offset.x = 0
        if offset.y <= -area.?.y do return
    }
    if charD.rawShape != nil {
        vlen := len(_vertArr^)

        non_zero_resize_dynamic_array(_vertArr, vlen + len(charD.rawShape.vertices))
        runtime.mem_copy_non_overlapping(&_vertArr^[vlen], &charD.rawShape.vertices[0], len(charD.rawShape.vertices) * size_of(ShapeVertex2D))

        i := vlen
        for ;i < len(_vertArr^);i += 1 {
            _vertArr^[i].pos += offset^
            _vertArr^[i].pos *= scale
        }

        ilen := len(_indArr^)
        non_zero_resize_dynamic_array(_indArr, ilen + len(charD.rawShape.indices))
        runtime.mem_copy_non_overlapping(&_indArr^[ilen], &charD.rawShape.indices[0], len(charD.rawShape.indices) * size_of(u32))

        i = ilen
        for ;i < len(_indArr^);i += 1 {
            _indArr^[i] += auto_cast vlen
        }
    }
    offset.x += charD.advanceX
}

Font_RenderString2 :: proc(_str:string, _renderOpt:FontRenderOpt2, allocator := context.allocator) -> RawShape {
    vertList := make_non_zeroed_dynamic_array([dynamic]ShapeVertex2D, allocator)
    indList := make_non_zeroed_dynamic_array([dynamic]u32, allocator)

    _Font_RenderString2(_str, _renderOpt, &vertList, &indList,  allocator)
    shrink(&vertList)
    shrink(&indList)
    raw : RawShape = {
        vertices = vertList[:],
        indices = indList[:],
    }
    return raw
}

Font_RenderString :: proc(self:^Font, _str:string, _renderOpt:FontRenderOpt, allocator := context.allocator) -> RawShape {
    vertList := make_non_zeroed_dynamic_array([dynamic]ShapeVertex2D, allocator)
    indList := make_non_zeroed_dynamic_array([dynamic]u32, allocator)

    _Font_RenderString(auto_cast self, _str, _renderOpt, &vertList, &indList, allocator)

    shrink(&vertList)
    shrink(&indList)
    raw : RawShape = {
        vertices = vertList[:],
        indices = indList[:],
    }
    return raw
}