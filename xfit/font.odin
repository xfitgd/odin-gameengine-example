package xfit


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
    face:freetype.Face,
    charArray : map[rune]CharData,
    scale:f32,//default 256

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

@(private="file") freetypeLib:freetype.Library = nil

@(private="file") _Init_FreeType :: proc "contextless" () {
    err := freetype.init_free_type(&freetypeLib)
    if err != .Ok do panicLog(err)
}

@(private) _Deinit_FreeType :: proc "contextless" () {
    err := freetype.done_free_type(freetypeLib)
    if err != .Ok do panicLog(err)
    freetypeLib = nil
}

FreetypeErr :: freetype.Error

Font_Init :: proc(_fontData:[]byte, #any_int _faceIdx:int = 0) -> (font : ^Font = nil, err : FreetypeErr = .Ok)  {
    font_ := new_non_zeroed(__Font)
    defer if err != .Ok do free(font_)

    font_.scale = SCALE_DEFAULT
    font_.mutex = {}

    font_.charArray = make_map( map[rune]CharData)

    if freetypeLib == nil do _Init_FreeType()

    err = freetype.new_memory_face(freetypeLib, raw_data(_fontData), auto_cast len(_fontData), auto_cast _faceIdx, &font_.face)
    defer if err != .Ok {
        err = freetype.done_face(font_.face)
    }
    if err != .Ok do return

    err = freetype.set_char_size(font_.face, 0, 16 * 256 * 64, 0, 0)
    if err != .Ok do return

    font = auto_cast font_
    return
}

Font_Deinit :: proc(self:^Font) -> (err : freetype.Error = .Ok) {
    self_:^__Font = auto_cast self
    sync.mutex_lock(&self_.mutex)

    err = freetype.done_face(self_.face)
    if err != .Ok do panicLog(err)

    for key,value in self_.charArray {
        RawShape_Free(value.rawShape, vkDefAllocator)
    }
    delete(self_.charArray)
    sync.mutex_unlock(&self_.mutex)
    free(self_)

    return
}

Font_SetScale :: proc(self:^Font, scale:f32) {
    self_:^__Font = auto_cast self
    sync.mutex_lock(&self_.mutex)
    self_.scale = SCALE_DEFAULT / scale
    sync.mutex_unlock(&self_.mutex)
}

@(private="file") _Font_RenderString2 :: proc(_str:string,
_renderOpt:FontRenderOpt2,
vertList:^[dynamic]ShapeVertex2D,
indList:^[dynamic]u32,
allocator : runtime.Allocator) -> (rect:RectF, err:ShapesError = .None) {
    i : int = 0
    opt := _renderOpt.opt
    rectT : RectF
    rect = Rect_Init(f32(0.0), 0.0, 0.0, 0.0)

    for r in _renderOpt.ranges {
        opt.scale = _renderOpt.opt.scale * r.scale
        opt.color = r.color

        if r.len == 0 || i + auto_cast r.len >= len(_str) {
            _, rectT = _Font_RenderString(auto_cast r.font, _str[i:], opt, vertList, indList, allocator) or_return
            rect = Rect_Or(rect, rectT)
            break;
        } else {
            opt.offset, rectT = _Font_RenderString(auto_cast r.font, _str[i:i + auto_cast r.len], opt, vertList, indList, allocator) or_return
            rect = Rect_Or(rect, rectT)
            i += auto_cast r.len
        }
    }
    return
}

@(private="file") _Font_RenderString :: proc(self:^__Font,
    _str:string,
    _renderOpt:FontRenderOpt,
    _vertArr:^[dynamic]ShapeVertex2D,
    _indArr:^[dynamic]u32,
    allocator : runtime.Allocator) -> (pt:PointF, rect:RectF, err:ShapesError = .None) {

    maxP : PointF = {min(f32), min(f32)}
    minP : PointF = {max(f32), max(f32)}

    offset : PointF = {}

    sync.mutex_lock(&self.mutex)
    for s in _str {
        if _renderOpt.area != nil && offset.y <= _renderOpt.area.?.y do break
        if s == '\n' {
            offset.y -= f32(self.face.size.metrics.height) / (64.0 * self.scale) 
            offset.x = 0
            continue
        }
        minP = min_array(minP, offset)

        _Font_RenderChar(self, s, _vertArr, _indArr, &offset, _renderOpt.area, _renderOpt.scale, _renderOpt.color, allocator) or_return
        
        maxP = max_array(maxP, PointF{offset.x, offset.y + f32(self.face.size.metrics.height) / (64.0 * self.scale) })
    }
    sync.mutex_unlock(&self.mutex)

    size : PointF = _renderOpt.area != nil ? _renderOpt.area.? : (maxP - minP) * PointF{1,1}

    maxP = {min(f32), min(f32)}
    minP = {max(f32), max(f32)}

    for &v in _vertArr^ {
        v.pos -= _renderOpt.pivot * size * _renderOpt.scale
        v.pos += _renderOpt.offset

        minP = min_array(minP, v.pos)
        maxP = max_array(maxP, v.pos)
    }
    rect = Rect_Init_LTRB(minP.x, maxP.x, minP.y, maxP.y)

    pt = offset * _renderOpt.scale + _renderOpt.offset
    return
}

@(private="file") _Font_RenderChar :: proc(self:^__Font,
    _char:rune,
    _vertArr:^[dynamic]ShapeVertex2D,
    _indArr:^[dynamic]u32,
    offset:^PointF,
    area:Maybe(PointF),
    scale:PointF,
    color:Point3DwF,
    allocator : runtime.Allocator) -> (shapeErr:ShapesError = .None) {
    ok := _char in self.charArray
    charD : ^CharData

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

    if ok {
        charD = &self.charArray[_char]
    } else {
        ch := _char
        for {
            fIdx := freetype.get_char_index(self.face, auto_cast ch)
            if fIdx == 0 {
                if ch == '□' do panicLog("not found □")
                ok = '□' in self.charArray
                if ok {
                    charD = &self.charArray['□']
                    break
                }
                ch = '□'

                continue
            }
            err := freetype.load_glyph(self.face, fIdx, {.No_Bitmap})
            if err != .Ok do panicLog(err)

            if self.face.glyph.outline.n_points == 0 {
                charData : CharData = {
                    advanceX = f32(self.face.glyph.advance.x) / (64.0 * SCALE_DEFAULT),
                    rawShape = nil
                }
                self.charArray[ch] = charData

                charD = &self.charArray[ch]
                break
            }
    
            //TODO FT_Outline_New FT_Outline_Copy FT_Outline_Done로 임시객체로 복제하여 Lock Free 구현
            if freetype.outline_get_orientation(&self.face.glyph.outline) == freetype.Orientation.FILL_RIGHT {
                freetype.outline_reverse(&self.face.glyph.outline)
            }
        
            poly : Shapes = {
                nPolys = make_non_zeroed([]u32, self.face.glyph.outline.n_contours),
                nTypes = make_non_zeroed([]u32, self.face.glyph.outline.n_contours),
                types = make_non_zeroed([]CurveType, self.face.glyph.outline.n_points*3),
                poly = make_non_zeroed([]PointF, self.face.glyph.outline.n_points*3),
                colors = make_non_zeroed([]Point3DwF, self.face.glyph.outline.n_contours),
            }
            for &c in poly.colors {
                c = Point3DwF{0,0,0,1}//?no matter
            }
            defer {
                delete(poly.nPolys, )
                delete(poly.nTypes, )
                delete(poly.types, )
                delete(poly.poly, )
                delete(poly.colors, )
            }
            data : FontUserData = {
                polygon = &poly,
                idx = 0,
                typeIdx = 0,
                nPolyLen = 0,
                nTypesLen = 0,
                scale = self.scale,
            }
        
            err = freetype.outline_decompose(&self.face.glyph.outline, &funcs, &data)
            if err != .Ok do panicLog(err)

            charData : CharData
            if data.idx == 0 {
                charData = {
                    advanceX = f32(self.face.glyph.advance.x) / (64.0 * self.scale),
                    rawShape = nil
                }
                self.charArray[ch] = charData
            
                charD = &self.charArray[ch]
                break
            } else {
                sync.mutex_unlock(&self.mutex)
                defer sync.mutex_lock(&self.mutex)

                poly.nPolys[data.nPoly] = data.nPolyLen
                poly.nTypes[data.nTypes] = data.nTypesLen
                poly.poly = resize_non_zeroed_slice(poly.poly, data.idx, )
                poly.types = resize_non_zeroed_slice(poly.types, data.typeIdx, )
               
                poly.strokeColors = nil
                poly.thickness = nil

                rawP : ^RawShape
                rawP , shapeErr = Shapes_ComputePolygon(&poly, vkDefAllocator)//높은 부하 작업 High load operations
                if shapeErr != .None do return

                defer if shapeErr != .None {
                    RawShape_Free(rawP, vkDefAllocator)
                }

                charData = {
                    advanceX = f32(self.face.glyph.advance.x) / (64.0 * self.scale),
                    rawShape = rawP
                }
            }
            self.charArray[ch] = charData
            
            charD = &self.charArray[ch]
            break
        }
    }
    if area != nil && offset.x + charD.advanceX >= area.?.x {
        offset.y -= f32(self.face.size.metrics.height) / (64.0 * self.scale) 
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
            if _vertArr^[i].color.a > 0.0 {
                _vertArr^[i].color = color
            }
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

    return
}

Font_RenderString2 :: proc(_str:string, _renderOpt:FontRenderOpt2, allocator := context.allocator) -> (res:^RawShape, err:ShapesError = .None)  {
    vertList := make_non_zeroed_dynamic_array([dynamic]ShapeVertex2D, allocator)
    indList := make_non_zeroed_dynamic_array([dynamic]u32, allocator)

    _Font_RenderString2(_str, _renderOpt, &vertList, &indList, allocator) or_return
    shrink(&vertList)
    shrink(&indList)
    res = new (RawShape, allocator)
    res^ = {
        vertices = vertList[:],
        indices = indList[:],
    }
    return
}

Font_RenderString :: proc(self:^Font, _str:string, _renderOpt:FontRenderOpt, allocator := context.allocator) -> (res:^RawShape, err:ShapesError = .None) {
    vertList := make_non_zeroed_dynamic_array([dynamic]ShapeVertex2D, allocator)
    indList := make_non_zeroed_dynamic_array([dynamic]u32, allocator)

    _, rect := _Font_RenderString(auto_cast self, _str, _renderOpt, &vertList, &indList, allocator) or_return

    shrink(&vertList)
    shrink(&indList)
    res = new (RawShape, allocator)
    res^ = {
        vertices = vertList[:],
        indices = indList[:],
        rect = rect,
    }
    return
}