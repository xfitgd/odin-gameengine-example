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
    colorFlag:ResourceUsage,
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
Font_ConvertFontFmtToVFF :: proc(_fontFmtData:[]byte, _fontFmtFaceIdx:uint) -> ([]byte, freetype.Error) {
    FTMoveTo :: proc "c" (to: ^freetype.Vector, user: rawptr) -> c.int {
        data : ^FontUserData = auto_cast user
        data.pen = PointF{f32(to.x) / (64 * data.scale), f32(to.y) / (64 * data.scale)}
    
        //다각형 하나를 그리고 펜위치를 이동하므로 nPolyLen 다각형 갯수를 증가시키고 nPoly를 0으로 만든다.
        if data.nPoly > 0 {
            data.polygon.nodes[0].nPolygons[data.nPolyLen] = data.nPoly
            data.nPolyLen += 1
            data.nPoly = 0
        }
        return 0
    }
    FTLineTo :: proc "c" (to: ^freetype.Vector, user: rawptr) -> c.int {
        data : ^FontUserData = auto_cast user
        end := PointF{f32(to.x) / (64 * data.scale), f32(to.y) / (64 * data.scale)}
    
        data.polygon.nodes[0].lines[data.idx2] = Line_LineInit(data.pen)
        data.pen = end
        data.idx2 += 1
        data.nPoly += 1  
        return 0
    }
    FTConicTo :: proc "c" (control: ^freetype.Vector, to: ^freetype.Vector, user: rawptr) -> c.int {
        data : ^FontUserData = auto_cast user
        ctl := PointF{f32(control.x) / (64 * data.scale), f32(control.y) / (64 * data.scale)}
        end := PointF{f32(to.x) / (64 * data.scale), f32(to.y) / (64 * data.scale)}
    
        data.polygon.nodes[0].lines[data.idx2] = Line_QuadraticInit(data.pen, ctl)
        data.pen = end
        data.idx2 += 1
        data.nPoly += 1
        return 0
    }
    FTCubicTo :: proc "c" (control0, control1, to: ^freetype.Vector, user: rawptr) -> c.int {
        data : ^FontUserData = auto_cast user
        ctl0 := PointF{f32(control0.x) / (64 * data.scale), f32(control0.y) / (64 * data.scale)}
        ctl1 := PointF{f32(control1.x) / (64 * data.scale), f32(control1.y) / (64 * data.scale)}
        end := PointF{f32(to.x) / (64 * data.scale), f32(to.y) / (64 * data.scale)}
    
        data.polygon.nodes[0].lines[data.idx2] = {
            start = data.pen,
            control0 = ctl0,
            control1 = ctl1,
        }
        data.pen = end
        data.idx2 += 1
        data.nPoly += 1
        return 0
    }
    FontUserData :: struct {
        pen : PointF,
        polygon : ^Shapes,
        idx2 : u32,
        nPolyLen : u32,
        nPoly : u32,
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
    if err != .Ok do return nil, err
    defer freetype.done_face(face)

    err = freetype.set_char_size(face, 0, 16 * 256 * 64, 0, 0)
    if err != .Ok do return nil, err

    outData := make_non_zeroed_dynamic_array([dynamic]byte)
    defer if err != .Ok {
        delete(outData)
    }

    append(&outData, 'v')
    append(&outData, 'f')
    append(&outData, 'f')
    append(&outData, 0)

    non_zero_resize_dynamic_array(&outData, 4 + size_of(u32) + size_of(f32))
    //(transmute([^]u32)(&outData[4]))[0] = 0 갯수 알아내면 나중에 대입한다.
    (transmute([^]f32)(&outData[4 + size_of(f32)]))[0] = f32(face.size.metrics.height) / (64.0 * SCALE_DEFAULT)

    outDataIdx := len(outData)

    gIdx : c.uint
    charLen := 0
    charCode := freetype.get_first_char(face, &gIdx)
    for charCode != 0 {
        err = freetype.load_glyph(face, gIdx, {.No_Bitmap})
        if err != .Ok do panicLog(err)
    
        if freetype.outline_get_orientation(&face.glyph.outline) == freetype.Orientation.FILL_RIGHT {
            freetype.outline_reverse(&face.glyph.outline)
        }
    
        poly : Shapes = {
            nodes = make_non_zeroed([]ShapesNode, 1, context.temp_allocator)
        }
        defer {
            for v in poly.nodes {
                delete(v.lines, context.temp_allocator)
                delete(v.nPolygons, context.temp_allocator)
            }
            delete(poly.nodes)
        }
        poly.nodes[0].lines = make_non_zeroed([]Line, face.glyph.outline.n_points, context.temp_allocator) 
        poly.nodes[0].nPolygons = make_non_zeroed([]u32, face.glyph.outline.n_points, context.temp_allocator) 
    
        data : FontUserData = {
            polygon = &poly,
            idx2 = 0,
            nPoly = 0,
            nPolyLen = 0,
            scale = SCALE_DEFAULT,
        }
    
        err = freetype.outline_decompose(&face.glyph.outline, &funcs, &data)
        if err != .Ok do panicLog(err)

        if data.idx2 == 0 {
            non_zero_resize_dynamic_array(&outData, len(outData) + size_of(CharNode))
            (transmute([^]CharNode)(&outData[len(outData) - size_of(CharNode)]))[0] = CharNode{
                size = 0,
                char = auto_cast charCode,
                advanceX = f32(face.glyph.advance.x) / (64.0 * SCALE_DEFAULT)
            }
            continue;
        } else {
            if data.nPoly > 0 {
                data.polygon.nodes[0].nPolygons[data.nPolyLen] = data.nPoly
                data.nPolyLen += 1
            }
            poly.nodes[0].lines = resize_non_zeroed_slice( poly.nodes[0].lines, data.idx2, context.temp_allocator)
            poly.nodes[0].nPolygons = resize_non_zeroed_slice( poly.nodes[0].nPolygons, data.nPolyLen, context.temp_allocator)

            poly.nodes[0].color = Point3DwF{0,0,0,1}
            poly.nodes[0].strokeColor = nil
            poly.nodes[0].thickness = 0

            rawP : ^RawShape = Shapes_ComputePolygon(&poly, context.temp_allocator)
            defer RawShape_free(rawP, context.temp_allocator)
            
            rawSize := RawShape_BytesSize(rawP)
            len_ := len(outData)
            non_zero_resize_dynamic_array(&outData, len_ + size_of(CharNode) + rawSize)
            (transmute([^]CharNode)(&outData[len_]))[0] = CharNode{
                size = 0,
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
    return outSlice, err
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
        rawShape :^RawShape = charNode.size == 0 ? nil : RawShape_CloneFromBytes(_vffData[dataIdx:dataIdx + auto_cast charNode.size], context.allocator)
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
        RawShape_free(value.rawShape, context.allocator)
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
vertList:^[dynamic][]shapeVertex2D,
indList:^[dynamic][]u32,
colorList:^[dynamic]Point3DwF,
allocator : runtime.Allocator) {
    i,idx : int
    opt := _renderOpt.opt

    for r in _renderOpt.ranges {
        opt.scale = _renderOpt.opt.scale * r.scale
        same := false

        for t,i in colorList^ {
            if t == r.color {
                same = true
                idx = i
                break
            }
        }
        if !same {
            append(vertList, make_non_zeroed([]shapeVertex2D, 0, allocator))
            append(indList, make_non_zeroed([]u32, 0, allocator))
            append(colorList, r.color)
            idx = len(colorList) - 1
        }

        if r.len == 0 || i + auto_cast r.len >= len(_str) {
            _Font_RenderString(auto_cast r.font, _str[i:], opt, &vertList[idx], &indList[idx], allocator)
            break;
        } else {
            opt.offset = _Font_RenderString(auto_cast r.font, _str[i:i + auto_cast r.len], opt, &vertList[idx], &indList[idx], allocator)
            i += auto_cast r.len
        }
    }   
}

@(private="file") _Font_RenderString :: proc(self:^__Font, _str:string, _renderOpt:FontRenderOpt, _vertArr:^[]shapeVertex2D,_indArr:^[]u32, allocator : runtime.Allocator) -> PointF {
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
    }

    return offset * _renderOpt.scale
}

@(private="file") _Font_RenderChar :: proc(self:^__Font, _char:rune, _vertArr:^[]shapeVertex2D, _indArr:^[]u32, offset:^PointF, area:Maybe(PointF), scale:PointF, allocator : runtime.Allocator) {
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
        _vertArr^ = resize_non_zeroed_slice(_vertArr^, vlen + len(charD.rawShape.vertices[0]), allocator)
        runtime.mem_copy_non_overlapping(&_vertArr^[vlen], &charD.rawShape.vertices[0][0], len(charD.rawShape.vertices[0]) * size_of(shapeVertex2D))

        i := vlen
        for ;i < len(_vertArr^);i += 1 {
            _vertArr^[i].pos += offset^
            _vertArr^[i].pos *= scale
        }

        ilen := len(_indArr^)
        _indArr^ = resize_non_zeroed_slice(_indArr^, ilen + len(charD.rawShape.indices[0]), allocator)
        runtime.mem_copy_non_overlapping(&_indArr^[ilen], &charD.rawShape.indices[0][0], len(charD.rawShape.indices[0]) * size_of(type_of(_indArr^[0])))

        i = ilen
        for ;i < len(_indArr^);i += 1 {
            _indArr^[i] += auto_cast vlen
        }
    }
    offset.x += charD.advanceX
}

Font_RenderString2 :: proc(_str:string, _renderOpt:FontRenderOpt2, allocator := context.allocator) -> RawShape {
    vertList := make_non_zeroed_dynamic_array([dynamic][]shapeVertex2D, allocator)
    indList := make_non_zeroed_dynamic_array([dynamic][]u32, allocator)
    colorList := make_non_zeroed_dynamic_array([dynamic]Point3DwF, allocator)

    _Font_RenderString2(_str, _renderOpt, &vertList, &indList, &colorList, allocator)
    shrink(&vertList)
    shrink(&indList)
    shrink(&colorList)
    raw : RawShape = {
        vertices = vertList[:],
        indices = indList[:],
        colors = colorList[:],
    }
    return raw
}

Font_RenderString :: proc(self:^Font, _str:string, _renderOpt:FontRenderOpt, allocator := context.allocator) -> RawShape {
    vertList := make_non_zeroed_slice([][]shapeVertex2D, 1, allocator)
    indList := make_non_zeroed_slice([][]u32, 1, allocator)
    colorList := make_non_zeroed_slice([]Point3DwF, 1, allocator)

    vertArray :[]shapeVertex2D = make_non_zeroed_slice([]shapeVertex2D, 0, allocator)
    indArray :[]u32 = make_non_zeroed_slice([]u32, 0, allocator)
    _Font_RenderString(auto_cast self, _str, _renderOpt, &vertArray, &indArray, allocator)

    vertList[0] = vertArray
    indList[0] = indArray
    colorList[0] = _renderOpt.color
    raw : RawShape = {
        vertices = vertList,
        indices = indList,
        colors = colorList,
    }
    return raw
}