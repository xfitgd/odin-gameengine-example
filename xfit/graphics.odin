package xfit

import "core:math"
import "core:mem"
import "core:slice"
import "core:sync"
import "core:math/linalg"
import "base:intrinsics"
import "base:runtime"
import vk "vendor:vulkan"
import "xmem"

ShapeVertex2D :: struct #align(1) {
    pos: PointF,
    uvw: Point3DF,
    color: Point3DwF,
};

ResourceUsage :: enum {GPU,CPU}

ImageCenterPtPos :: enum {
    Center,
    Left,
    Right,
    TopLeft,
    Top,
    TopRight,
    BottomLeft,
    Bottom,
    BottomRight,
}

Camera :: struct {
    __in: __MatrixIn,
}

Projection :: struct {
    __in: __MatrixIn,
}

ColorTransform :: struct {
    __in: __ColorMatrixIn,
}

__ColorMatrixIn :: struct {
    mat: Matrix,
    matUniform:VkBufferResource,
    checkInit: ICheckInit,
}


__MatrixIn :: struct {
    mat: Matrix,
    matUniform:VkBufferResource,
    pos: Point3DF,
    rotation: f32,
    scale: PointF,
    checkInit: ICheckInit,
}

__IObjectIn :: struct {
    set:VkDescriptorSet,
    camera: ^Camera,
    projection: ^Projection,
    colorTransform: ^ColorTransform,
    __in: __MatrixIn,
    actualType: typeid,
    vtable: ^IObjectVTable,
}

IObjectVTable :: struct {
    Draw: proc (self:^IObject, cmd:vk.CommandBuffer),
    Deinit: proc (self:^IObject),
    Update: proc (self:^IObject),
    __in: __IObjectVTable,
}

__IObjectVTable :: struct {
    __GetUniformResources: proc (self:^IObject) -> []VkUnionResource,
}

IObject :: struct {
    __in: __IObjectIn,
}

__TextureIn :: struct {
    texture:VkTextureResource,
    set:VkDescriptorSet,
    sampler: vk.Sampler,
    checkInit: ICheckInit,
}

Texture :: struct {
    __in: __TextureIn,
}

TextureArray :: struct {
    __in: __TextureArrayIn,
}

__TextureArrayIn :: distinct __TextureIn

TileTextureArray :: struct {
    __in: __TileTextureArrayIn,
}

__TileTextureArrayIn :: struct {
    using _:__TextureArrayIn,
    allocPixels:[]byte,
}

Image :: struct {
    using _:IObject,
    __in2: __ImageIn,
}

__ImageIn :: struct {
    src: ^Texture,
}

AnimateImage :: struct {
    using _:IObject,
    __in2: __AnimateImageIn,
}

__AnimateImageIn :: struct {
    frameUniform:VkBufferResource,
    frame:u32,
    src: ^TextureArray,
}

TileImage :: struct {
    using _:IObject,
    __in2: __TileImageIn,
}

__TileImageIn :: struct {
    tileUniform:VkBufferResource,
    tileIdx:u32,
    src: ^TileTextureArray,
}

@private __VertexBuf :: struct($NodeType:typeid) {
    buf:VkBufferResource,
    checkInit: ICheckInit,
}

@private __IndexBuf :: distinct __VertexBuf(u32)
@private __StorageBuf :: struct($NodeType:typeid) {
    buf:VkBufferResource,
    checkInit: ICheckInit,
}


__ShapeSrcIn :: struct {
    //?vertexBuf, indexBuf에 checkInit: ICheckInit 있으므로 따로 필요없음
    vertexBuf:__VertexBuf(ShapeVertex2D),
    indexBuf:__IndexBuf,
}       

ShapeSrc :: struct {
    __in:__ShapeSrcIn,
}

Shape :: struct {
    using _:IObject,
    __in2:__ShapeIn,
}

__ShapeIn :: struct {
    src: ^ShapeSrc,
}

@private __defColorTransform : ColorTransform

@private Graphics_Create :: proc() {
    ColorTransform_InitMatrixRaw(&__defColorTransform)
}

@private Graphics_Clean :: proc() {
    ColorTransform_Deinit(&__defColorTransform)
}

IsAnyImageType :: #force_inline proc "contextless" ($ANY_IMAGE:typeid) -> bool {
    return intrinsics.type_is_subtype_of(ANY_IMAGE, IObject) && intrinsics.type_has_field(ANY_IMAGE, "src") && 
    (intrinsics.type_field_type(ANY_IMAGE, "src") == Texture ||
    intrinsics.type_field_type(ANY_IMAGE, "src") == TextureArray ||
    intrinsics.type_field_type(ANY_IMAGE, "src") == TileTextureArray)
}

ImagePixelPerfectPoint :: proc "contextless" (img:^$ANY_IMAGE, p:PointF, canvasW:f32, canvasH:f32, center:ImageCenterPtPos) -> PointF where IsAnyImageType(ANY_IMAGE) {
    width := __windowWidth
    height := __windowHeight
    widthF := f32(width)
    heightF := f32(height)
    if widthF / heightF > canvasW / canvasH {
        if canvasH != heightF do return p
    } else {
        if canvasW != width do return p
    }
    p = linalg.floor(p)
    if width % 2 == 0 do p.x -= 0.5
    if height % 2 == 0 do p.y += 0.5

    #partial switch center {
        case .Center:
            if img.src.__in.texture.option.width % 2 != 0 do p.x += 0.5
            if img.src.__in.texture.option.height % 2 != 0 do p.y -= 0.5
        case .Left, .Right:
            if img.src.__in.texture.option.height % 2 != 0 do p.y -= 0.5
        case .Top, .Bottom:
            if img.src.__in.texture.option.width % 2 != 0 do p.x += 0.5
    }
    return p
}

SetRenderClearColor :: proc "contextless" (color:Point3DwF) {
    gClearColor = color
}

//AUTO DELETE USE vkDefAllocator
@private __VertexBuf_Init :: proc (self:^__VertexBuf($NodeType), array:[]NodeType, _flag:ResourceUsage, _useGPUMem := false) {
    xmem.ICheckInit_Init(&self.checkInit)
    if len(array) == 0 do panicLog("VertexBuf_Init: array is empty")
    VkBufferResource_CreateBuffer(&self.buf, {
        len = vk.DeviceSize(len(array) * size_of(NodeType)),
        type = .VERTEX,
        resourceUsage = _flag,
        single = false,
        useGCPUMem = _useGPUMem,
    }, mem.slice_to_bytes(array), false, vkDefAllocator)
}

@private __VertexBuf_Deinit :: proc (self:^__VertexBuf($NodeType)) {
    xmem.ICheckInit_Deinit(&self.checkInit)

    VkBufferResource_Deinit(&self.buf)
}

@private __VertexBuf_Update :: proc (self:^__VertexBuf($NodeType), array:[]NodeType) {
    VkBufferResource_MapUpdateSlice(&self.buf, array, vkDefAllocator)
}

//AUTO DELETE USE vkDefAllocator
@private __StorageBuf_Init :: proc (self:^__StorageBuf($NodeType), array:[]NodeType, _flag:ResourceUsage, _useGPUMem := false) {
    xmem.ICheckInit_Init(&self.checkInit)
    if len(array) == 0 do panicLog("StorageBuf_Init: array is empty")
    VkBufferResource_CreateBuffer(&self.buf, {
        len = vk.DeviceSize(len(array) * size_of(NodeType)),
        type = .STORAGE,
        resourceUsage = _flag,
        single = false,
        useGCPUMem = _useGPUMem,
    }, mem.slice_to_bytes(array), false, vkDefAllocator)
}

@private __StorageBuf_Deinit :: proc (self:^__StorageBuf($NodeType)) {
    xmem.ICheckInit_Deinit(&self.checkInit)

    VkBufferResource_Deinit(&self.buf)
}

@private __StorageBuf_Update :: proc (self:^__StorageBuf($NodeType), array:[]NodeType) {
    VkBufferResource_MapUpdateSlice(&self.buf, array, vkDefAllocator)
}

//AUTO DELETE USE vkDefAllocator
@private __IndexBuf_Init :: proc (self:^__IndexBuf, array:[]u32, _flag:ResourceUsage, _useGPUMem := false) {
    xmem.ICheckInit_Init(&self.checkInit)
    if len(array) == 0 do panicLog("IndexBuf_Init: array is empty")
    VkBufferResource_CreateBuffer(&self.buf, {
        len = vk.DeviceSize(len(array) * size_of(u32)),
        type = .INDEX,
        resourceUsage = _flag,
        useGCPUMem = _useGPUMem,
    }, mem.slice_to_bytes(array), false, vkDefAllocator)
}


@private __IndexBuf_Deinit :: proc (self:^__IndexBuf) {
    xmem.ICheckInit_Deinit(&self.checkInit)

    VkBufferResource_Deinit(&self.buf)
}

@private __IndexBuf_Update :: #force_inline proc (self:^__IndexBuf, array:[]u32) {
    VkBufferResource_MapUpdateSlice(&self.buf, array, vkDefAllocator)
}

Projection_InitMatrixOrtho :: proc (self:^Projection, left:f32, right:f32, bottom:f32, top:f32, near:f32 = 0.1, far:f32 = 100, flipZAxisForVulkan := true) {
    __Projection_UpdateOrtho(self, left, right, bottom, top, near, far, flipZAxisForVulkan)
    __Projection_Init(self)
}

Projection_InitMatrixOrthoWindow :: proc (self:^Projection, width:f32, height:f32, near:f32 = 0.1, far:f32 = 100, flipZAxisForVulkan := true) {
    __Projection_UpdateOrthoWindow(self, width, height, near, far, flipZAxisForVulkan)
    __Projection_Init(self)
}

@private __Projection_UpdateOrtho :: #force_inline proc(self:^Projection, left:f32, right:f32, bottom:f32, top:f32, near:f32 = 0.1, far:f32 = 100, flipZAxisForVulkan := true) {
    //TODO self.__in.mat = linalg.matrix_ortho3d_f32(left, right, bottom, top, near, far, flipZAxisForVulkan)
}

Projection_UpdateOrtho :: #force_inline proc(self:^Projection,  left:f32, right:f32, bottom:f32, top:f32, near:f32 = 0.1, far:f32 = 100, flipZAxisForVulkan := true) {
    __Projection_UpdateOrtho(self, left, right, bottom, top, near, far, flipZAxisForVulkan)
    Projection_UpdateMatrixRaw(self, self.__in.mat)
}

@private __Projection_UpdateOrthoWindow :: #force_inline proc(self:^Projection, width:f32, height:f32, near:f32 = 0.1, far:f32 = 100, flipZAxisForVulkan := true) {
    windowWidthF := f32(__windowWidth.?)
    windowHeightF := f32(__windowHeight.?)
    ratio := windowWidthF / windowHeightF > width / height ? height / windowHeightF : width / windowWidthF

    windowWidthF *= ratio
    windowHeightF *= ratio

    r := 1.0 / (far - near)
    self.__in.mat = {
        -2.0 / windowWidthF, 0, 0, 0,
        0, 2.0 / windowHeightF, 0, 0,
        0, 0, r, 0,
        0, 0, -r * near, 1,
    }
    if flipZAxisForVulkan {
        self.__in.mat[1,1] = -self.__in.mat[1,1]
    }
}

Projection_UpdateOrthoWindow :: #force_inline proc(self:^Projection, width:f32, height:f32, near:f32 = 0.1, far:f32 = 100, flipZAxisForVulkan := true) {
    __Projection_UpdateOrthoWindow(self, width, height, near, far, flipZAxisForVulkan)
    Projection_UpdateMatrixRaw(self, self.__in.mat)
}

Projection_InitMatrixRaw :: proc (self:^Projection, mat:Matrix) {
    self.__in.mat = mat

    __Projection_Init(self)
}


//! aspect is 0 means use window aspect
Projection_InitMatrixPerspective :: proc (self:^Projection, fov:f32, aspect:f32 = 0, near:f32 = 0.1, far:f32 = 100, flipZAxisForVulkan := true) {
    __Projection_UpdatePerspective(self, fov, aspect, near, far, flipZAxisForVulkan)
    __Projection_Init(self)
}

@private __Projection_UpdatePerspective :: #force_inline proc(self:^Projection, fov:f32, aspect:f32 = 0, near:f32 = 0.1, far:f32 = 100, flipZAxisForVulkan := true) {
    aspectF := aspect
    if aspectF == 0 do aspectF = f32(__windowWidth.? / __windowHeight.?)
    //TODO self.__in.mat = linalg.matrix4_perspective_f32(fov, aspectF, near, far, flipZAxisForVulkan)
}

Projection_UpdatePerspective :: #force_inline proc(self:^Projection, fov:f32, aspect:f32 = 0, near:f32 = 0.1, far:f32 = 100, flipZAxisForVulkan := true) {
    __Projection_UpdatePerspective(self, fov, aspect, near, far, flipZAxisForVulkan)
    Projection_UpdateMatrixRaw(self, self.__in.mat)
}

//? uniform object is all small, so use_gcpu_mem is true by default
@private __Projection_Init :: #force_inline proc(self:^Projection) {
    xmem.ICheckInit_Init(&self.__in.checkInit)
    mat : Matrix
    when is_mobile {
        mat = linalg.matrix_mul(self.__in.mat, vkRotationMatrix)
    } else {
        mat = self.__in.mat
    }
    VkBufferResource_CreateBuffer(&self.__in.matUniform, {
        len = size_of(Matrix),
        type = .UNIFORM,
        resourceUsage = .CPU,
        single = false,
    }, mem.ptr_to_bytes(&mat), true)
}

Projection_Deinit :: proc(self:^Projection) {
    xmem.ICheckInit_Deinit(&self.__in.checkInit)
    VkBufferResource_Deinit(&self.__in.matUniform)
}

Projection_UpdateMatrixRaw :: proc(self:^Projection, _mat:Matrix) {
    xmem.ICheckInit_Check(&self.__in.checkInit)
    mat : Matrix
    when is_mobile {
        mat = linalg.matrix_mul(_mat, vkRotationMatrix)
    } else {
        mat = _mat
    }
    self.__in.mat = _mat
    VkBufferResource_CopyUpdate(&self.__in.matUniform, &mat)
}

Camera_InitMatrixRaw :: proc (self:^Camera, mat:Matrix) {
    xmem.ICheckInit_Init(&self.__in.checkInit)
    self.__in.mat = mat
    __Camera_Init(self)
}

@private __Camera_Init :: #force_inline proc(self:^Camera) {
    xmem.ICheckInit_Init(&self.__in.checkInit)
    VkBufferResource_CreateBuffer(&self.__in.matUniform, {
        len = size_of(Matrix),
        type = .UNIFORM,
    }, mem.ptr_to_bytes(&self.__in.mat), true)
}

Camera_Deinit :: proc(self:^Camera) {
    xmem.ICheckInit_Deinit(&self.__in.checkInit)
    VkBufferResource_Deinit(&self.__in.matUniform)
}

Camera_UpdateMatrixRaw :: proc(self:^Camera, _mat:Matrix) {
    xmem.ICheckInit_Check(&self.__in.checkInit)
    self.__in.mat = _mat
    VkBufferResource_CopyUpdate(&self.__in.matUniform, &self.__in.mat)
}

@private __Camera_Update :: #force_inline proc(self:^Camera, eyeVec:Point3DF, focusVec:Point3DF, upVec:Point3DF = {0,0,1}) {
    self.__in.mat = linalg.matrix4_look_at_f32(eyeVec, focusVec, upVec, false)
}

Camera_Init :: proc (self:^Camera, eyeVec:Point3DF = {0,0,-1}, focusVec:Point3DF = {0,0,0}, upVec:Point3DF = {0,1,0}) {
    __Camera_Update(self, eyeVec, focusVec, upVec)
    __Camera_Init(self)
}

Camera_Update :: proc(self:^Camera, eyeVec:Point3DF = {0,0,-1}, focusVec:Point3DF = {0,0,0}, upVec:Point3DF = {0,0,1}) {
    __Camera_Update(self, eyeVec, focusVec, upVec)
    Camera_UpdateMatrixRaw(self, self.__in.mat)
}

ColorTransform_InitMatrixRaw :: proc(self:^ColorTransform, mat:Matrix = {1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1}) {
    self.__in.mat = mat
    __ColorTransform_Init(self)
}

@private __ColorTransform_Init :: #force_inline proc(self:^ColorTransform) {
    xmem.ICheckInit_Init(&self.__in.checkInit)
    VkBufferResource_CreateBuffer(&self.__in.matUniform, {
        len = size_of(Matrix),
        type = .UNIFORM,
    }, mem.ptr_to_bytes(&self.__in.mat), true)
}

ColorTransform_Deinit :: proc(self:^ColorTransform) {
    xmem.ICheckInit_Deinit(&self.__in.checkInit)
    VkBufferResource_Deinit(&self.__in.matUniform)
}

ColorTransform_UpdateMatrixRaw :: proc(self:^ColorTransform, _mat:Matrix) {
    xmem.ICheckInit_Check(&self.__in.checkInit)
    self.__in.mat = _mat
    VkBufferResource_CopyUpdate(&self.__in.matUniform, &self.__in.mat)
}

//IObject


@private IObject_Init :: proc(self:^IObject, $actualType:typeid,
    pos:Point3DF, rotation:f32, scale:PointF = {1,1}, 
    camera:^Camera, projection:^Projection, colorTransform:^ColorTransform = nil)
    where actualType != IObject && intrinsics.type_is_subtype_of(actualType, IObject) {

    xmem.ICheckInit_Init(&self.__in.__in.checkInit)
    self.__in.camera = camera
    self.__in.projection = projection
    self.__in.colorTransform = colorTransform == nil ? &__defColorTransform : colorTransform
    
    self.__in.__in.mat = linalg.matrix4_from_trs_f32(pos, linalg.quaternion_angle_axis_f32(rotation, {0,0,1}), {scale.x, scale.y, 1})
    self.__in.__in.pos = pos
    self.__in.__in.rotation = rotation
    self.__in.__in.scale = scale

    self.__in.set.__set = 0

    VkBufferResource_CreateBuffer(&self.__in.__in.matUniform, {
        len = size_of(Matrix),
        type = .UNIFORM,
    }, mem.ptr_to_bytes(&self.__in.__in.mat), true)

    resources := __GetUniformResources(self)
    defer delete(resources, context.temp_allocator)
    __IObject_UpdateUniform(self, resources)

    self.__in.actualType = actualType
}

//!alloc result array in temp_allocator
@private __GetUniformResources :: proc(self:^IObject) -> []VkUnionResource {
    if self.__in.vtable != nil && self.__in.vtable.__in.__GetUniformResources != nil {
        return self.__in.vtable.__in.__GetUniformResources(self)
    } else {
        panicLog("__GetUniformResources is not implemented")
    }
}

@private __GetUniformResources_AnimateImage :: #force_inline proc(self:^IObject) -> []VkUnionResource {
    res := make_non_zeroed([]VkUnionResource, 5, context.temp_allocator)
    res[0] = &self.__in.__in.matUniform
    res[1] = &self.__in.camera.__in.matUniform
    res[2] = &self.__in.projection.__in.matUniform
    res[3] = &self.__in.colorTransform.__in.matUniform

    animateImage : ^AnimateImage= auto_cast self
    res[4] = &animateImage.__in2.frameUniform
    return res[:]
}

@private __GetUniformResources_TileImage :: #force_inline proc(self:^IObject) -> []VkUnionResource {
    res := make_non_zeroed([]VkUnionResource, 5, context.temp_allocator)
    res[0] = &self.__in.__in.matUniform
    res[1] = &self.__in.camera.__in.matUniform
    res[2] = &self.__in.projection.__in.matUniform
    res[3] = &self.__in.colorTransform.__in.matUniform

    tileImage : ^TileImage = auto_cast self
    res[4] = &tileImage.__in2.tileUniform
    return res[:]
}

@private __GetUniformResources_Default :: #force_inline proc(self:^IObject) -> []VkUnionResource {
    res := make_non_zeroed([]VkUnionResource, 4, context.temp_allocator)
    res[0] = &self.__in.__in.matUniform
    res[1] = &self.__in.camera.__in.matUniform
    res[2] = &self.__in.projection.__in.matUniform
    res[3] = &self.__in.colorTransform.__in.matUniform

    return res[:]
}

@private __IObject_UpdateUniform :: #force_inline proc(self:^IObject, resources:[]VkUnionResource) {
    xmem.ICheckInit_Check(&self.__in.__in.checkInit)
    mem.copy_non_overlapping(&self.__in.set.__resources[0], &resources[0], len(resources) * size_of(VkUnionResource))
    VkUpdateDescriptorSets(mem.slice_ptr(&self.__in.set, 1))
}

IObject_UpdateTransform :: proc(self:^IObject, pos:Point3DF, rotation:f32 = 0, scale:PointF = {1,1}) {
    xmem.ICheckInit_Check(&self.__in.__in.checkInit)
    self.__in.__in.mat = linalg.matrix4_from_trs_f32(pos, linalg.quaternion_angle_axis_f32(rotation, {0,0,1}), {scale.x, scale.y, 1})
    self.__in.__in.pos = pos
    self.__in.__in.rotation = rotation
    self.__in.__in.scale = scale
    VkBufferResource_CopyUpdate(&self.__in.__in.matUniform, &self.__in.__in.mat)
}
IObject_UpdateTransformMatrixRaw :: proc(self:^IObject, _mat:Matrix) {
    xmem.ICheckInit_Check(&self.__in.__in.checkInit)
    self.__in.__in.mat = _mat
    VkBufferResource_CopyUpdate(&self.__in.__in.matUniform, &self.__in.__in.mat)
}
IObject_UpdateColorTransform :: proc(self:^IObject, colorTransform:^ColorTransform) {
    xmem.ICheckInit_Check(&self.__in.__in.checkInit)
    self.__in.colorTransform = colorTransform
    __IObject_UpdateUniform(self, __GetUniformResources(self))
}
IObject_UpdateCamera :: proc(self:^IObject, camera:^Camera) {
    xmem.ICheckInit_Check(&self.__in.__in.checkInit)
    self.__in.camera = camera
    __IObject_UpdateUniform(self, __GetUniformResources(self))
}
IObject_UpdateProjection :: proc(self:^IObject, projection:^Projection) {
    xmem.ICheckInit_Check(&self.__in.__in.checkInit)
    self.__in.projection = projection
    __IObject_UpdateUniform(self, __GetUniformResources(self))
}
IObject_GetColorTransform :: #force_inline proc "contextless" (self:^IObject) -> ^ColorTransform {
    xmem.ICheckInit_Check(&self.__in.__in.checkInit)
    return self.__in.colorTransform
}
IObject_GetCamera :: #force_inline proc "contextless" (self:^IObject) -> ^Camera {
    xmem.ICheckInit_Check(&self.__in.__in.checkInit)
    return self.__in.camera
}
IObject_GetProjection :: #force_inline proc "contextless" (self:^IObject) -> ^Projection {
    xmem.ICheckInit_Check(&self.__in.__in.checkInit)
    return self.__in.projection
}

IObject_GetPos :: #force_inline proc "contextless" (self:^IObject) -> Point3DF {
    xmem.ICheckInit_Check(&self.__in.__in.checkInit)
    return self.__in.__in.pos
}
IObject_GetX :: #force_inline proc "contextless" (self:^IObject) -> f32 {
    xmem.ICheckInit_Check(&self.__in.__in.checkInit)
    return self.__in.__in.pos.x
}
IObject_GetY :: #force_inline proc "contextless" (self:^IObject) -> f32 {
    xmem.ICheckInit_Check(&self.__in.__in.checkInit)
    return self.__in.__in.pos.y
}
IObject_GetZ :: #force_inline proc "contextless" (self:^IObject) -> f32 {
    xmem.ICheckInit_Check(&self.__in.__in.checkInit)
    return self.__in.__in.pos.z
}
IObject_GetRotation :: #force_inline proc "contextless" (self:^IObject) -> f32 {
    xmem.ICheckInit_Check(&self.__in.__in.checkInit)
    return self.__in.__in.rotation
}
IObject_GetScale :: #force_inline proc "contextless" (self:^IObject) -> PointF {
    xmem.ICheckInit_Check(&self.__in.__in.checkInit)
    return self.__in.__in.scale
}
IObject_GetScaleX :: #force_inline proc "contextless" (self:^IObject) -> f32 {
    xmem.ICheckInit_Check(&self.__in.__in.checkInit)
    return self.__in.__in.scale.x
}
IObject_GetScaleY :: #force_inline proc "contextless" (self:^IObject) -> f32 {
    xmem.ICheckInit_Check(&self.__in.__in.checkInit)
    return self.__in.__in.scale.y
}
IObject_SetPos :: #force_inline proc (self:^IObject, pos:Point3DF) {
    IObject_UpdateTransform(self, pos, self.__in.__in.rotation, self.__in.__in.scale)
}
IObject_SetX :: #force_inline proc (self:^IObject, x:f32) {
    IObject_UpdateTransform(self, {x, self.__in.__in.pos.y, self.__in.__in.pos.z}, self.__in.__in.rotation, self.__in.__in.scale)
}
IObject_SetY :: #force_inline proc (self:^IObject, y:f32) {
    IObject_UpdateTransform(self, {self.__in.__in.pos.x, y, self.__in.__in.pos.z}, self.__in.__in.rotation, self.__in.__in.scale)
}
IObject_SetZ :: #force_inline proc (self:^IObject, z:f32) {
    IObject_UpdateTransform(self, {self.__in.__in.pos.x, self.__in.__in.pos.y, z}, self.__in.__in.rotation, self.__in.__in.scale)
}
IObject_SetRotation :: #force_inline proc (self:^IObject, rotation:f32) {
    IObject_UpdateTransform(self, self.__in.__in.pos, rotation, self.__in.__in.scale)
}
IObject_SetScale :: #force_inline proc (self:^IObject, scale:PointF) {
    IObject_UpdateTransform(self, self.__in.__in.pos, self.__in.__in.rotation, scale)
}
IObject_SetScaleX :: #force_inline proc (self:^IObject, x:f32) {
    IObject_UpdateTransform(self, self.__in.__in.pos, self.__in.__in.rotation, {x, self.__in.__in.scale.y})
}
IObject_SetScaleY :: #force_inline proc (self:^IObject, y:f32) {
    IObject_UpdateTransform(self, self.__in.__in.pos, self.__in.__in.rotation, {self.__in.__in.scale.x, y})
}

IObject_GetActualType :: #force_inline proc "contextless" (self:^IObject) -> typeid {
    return self.__in.actualType
}

IObject_Draw :: proc (self:^IObject, cmd:vk.CommandBuffer) {
    if self.__in.vtable != nil && self.__in.vtable.Draw != nil {
        self.__in.vtable.Draw(self, cmd)
    } else {
        panicLog("IObjectType_Draw: unknown object type")
    }
}

IObject_Deinit :: proc(self:^IObject) {
    if self.__in.vtable != nil && self.__in.vtable.Deinit != nil {
        self.__in.vtable.Deinit(self)
    } else {
        panicLog("IObjectType_Deinit: unknown object type")
    }
}

IObject_Update :: proc(self:^IObject) {
    if self.__in.vtable != nil && self.__in.vtable.Update != nil {
        self.__in.vtable.Update(self)
    }
    //Update Not Required Default
}


//IObject End

//Shape


@private ShapeVTable := IObjectVTable {
    Draw = auto_cast _Super_Shape_Draw,
    Deinit = auto_cast _Super_Shape_Deinit,
}

Shape_Init :: proc(self:^Shape, $actualType:typeid, src:^ShapeSrc, pos:Point3DF, rotation:f32, scale:PointF = {1,1}, 
camera:^Camera, projection:^Projection, colorTransform:^ColorTransform = nil, vtable:^IObjectVTable = nil) where intrinsics.type_is_subtype_of(actualType, Shape) {
    self.__in2.src = src

    self.__in.set.bindings = __transformUniformPoolBinding[:]
    self.__in.set.size = __transformUniformPoolSizes[:]
    self.__in.set.layout = vkShapeDescriptorSetLayout

    self.__in.vtable = vtable == nil ? &ShapeVTable : vtable
    if self.__in.vtable.Draw == nil do self.__in.vtable.Draw = auto_cast _Super_Shape_Draw
    if self.__in.vtable.Deinit == nil do self.__in.vtable.Deinit = auto_cast _Super_Shape_Deinit

    self.__in.vtable.__in.__GetUniformResources = auto_cast __GetUniformResources_Default

    IObject_Init(self, actualType, pos, rotation, scale, camera, projection, colorTransform)
}

_Super_Shape_Deinit :: proc(self:^Shape) {
    xmem.ICheckInit_Deinit(&self.__in.__in.checkInit)
    VkBufferResource_Deinit(&self.__in.__in.matUniform)
}

Shape_UpdateSrc :: #force_inline proc "contextless" (self:^Shape, src:^ShapeSrc) {
    xmem.ICheckInit_Check(&self.__in.__in.checkInit)
    self.__in2.src = src
}
Shape_GetSrc :: #force_inline proc "contextless" (self:^Shape) -> ^ShapeSrc {
    xmem.ICheckInit_Check(&self.__in.__in.checkInit)
    return self.__in2.src
}
Shape_GetCamera :: #force_inline proc "contextless" (self:^Shape) -> ^Camera {
    return IObject_GetCamera(self)
}
Shape_GetProjection :: #force_inline proc "contextless" (self:^Shape) -> ^Projection {
    return IObject_GetProjection(self)
}
Shape_GetColorTransform :: #force_inline proc "contextless" (self:^Shape) -> ^ColorTransform {
    return IObject_GetColorTransform(self)
}
Shape_UpdateTransform :: #force_inline proc(self:^Shape, pos:Point3DF, rotation:f32, scale:PointF = {1,1}) {
    IObject_UpdateTransform(self, pos, rotation, scale)
}
Shape_UpdateTransformMatrixRaw :: #force_inline proc(self:^Shape, _mat:Matrix) {
    IObject_UpdateTransformMatrixRaw(self, _mat)
}
Shape_UpdateColorTransform :: #force_inline proc(self:^Shape, colorTransform:^ColorTransform) {
    IObject_UpdateColorTransform(self, colorTransform)
}
Shape_UpdateCamera :: #force_inline proc(self:^Shape, camera:^Camera) {
    IObject_UpdateCamera(self, camera)
}
Shape_UpdateProjection :: #force_inline proc(self:^Shape, projection:^Projection) {
    IObject_UpdateProjection(self, projection)
}

_Super_Shape_Draw :: proc (self:^Shape, cmd:vk.CommandBuffer) {
    xmem.ICheckInit_Check(&self.__in.__in.checkInit)

    vk.CmdBindPipeline(cmd, .GRAPHICS, vkShapePipeline)
    vk.CmdBindDescriptorSets(cmd, .GRAPHICS, vkShapePipelineLayout, 0, 1, 
        &([]vk.DescriptorSet{self.__in.set.__set})[0], 0, nil)


    offsets: vk.DeviceSize = 0
    vk.CmdBindVertexBuffers(cmd, 0, 1, &self.__in2.src.__in.vertexBuf.buf.__resource, &offsets)
    vk.CmdBindIndexBuffer(cmd, self.__in2.src.__in.indexBuf.buf.__resource, 0, .UINT32)

    vk.CmdDrawIndexed(cmd, auto_cast (self.__in2.src.__in.indexBuf.buf.option.len / size_of(u32)), 1, 0, 0, 0)
}

Shape_GetPos :: #force_inline proc "contextless" (self:^Shape) -> Point3DF {
    return IObject_GetPos(self)
}
Shape_GetX :: #force_inline proc "contextless" (self:^Shape) -> f32 {
    return IObject_GetX(self)
}
Shape_GetY :: #force_inline proc "contextless" (self:^Shape) -> f32 {
    return IObject_GetY(self)
}
Shape_GetZ :: #force_inline proc "contextless" (self:^Shape) -> f32 {
    return IObject_GetZ(self)
}
Shape_GetRotation :: #force_inline proc "contextless" (self:^Shape) -> f32 {
    return IObject_GetRotation(self)
}
Shape_GetScale :: #force_inline proc "contextless" (self:^Shape) -> PointF {
    return IObject_GetScale(self)
}
Shape_GetScaleX :: #force_inline proc "contextless" (self:^Shape) -> f32 {
    return IObject_GetScaleX(self)
}
Shape_GetScaleY :: #force_inline proc "contextless" (self:^Shape) -> f32 {
    return IObject_GetScaleY(self)
}
Shape_SetPos :: #force_inline proc (self:^Shape, pos:Point3DF) {
    IObject_SetPos(self, pos)
}
Shape_SetX :: #force_inline proc (self:^Shape, x:f32) {
    IObject_SetX(self, x)
}
Shape_SetY :: #force_inline proc (self:^Shape, y:f32) {
    IObject_SetY(self, y)
}
Shape_SetZ :: #force_inline proc (self:^Shape, z:f32) {
    IObject_SetZ(self, z)
}
Shape_SetRotation :: #force_inline proc (self:^Shape, rotation:f32) {
    IObject_SetRotation(self, rotation)
}
Shape_SetScale :: #force_inline proc (self:^Shape, scale:PointF) {
    IObject_SetScale(self, scale)
}
Shape_SetScaleX :: #force_inline proc (self:^Shape, x:f32) {
    IObject_SetScaleX(self, x)
}
Shape_SetScaleY :: #force_inline proc (self:^Shape, y:f32) {
    IObject_SetScaleY(self, y)
}



//Shape End

//Image


@private ImageVTable := IObjectVTable {
    Draw = auto_cast _Super_Image_Draw,
    Deinit = auto_cast _Super_Image_Deinit,
}

Image_Init :: proc(self:^Image, $actualType:typeid, src:^Texture, pos:Point3DF, rotation:f32, scale:PointF = {1,1}, 
camera:^Camera, projection:^Projection, colorTransform:^ColorTransform = nil, vtable:^IObjectVTable = nil) where intrinsics.type_is_subtype_of(actualType, Image) {
    self.__in2.src = src
        
    self.__in.set.bindings = __transformUniformPoolBinding[:]
    self.__in.set.size = __transformUniformPoolSizes[:]
    self.__in.set.layout = vkTexDescriptorSetLayout

    IObject_Init(self, actualType, pos, rotation, scale, camera, projection, colorTransform)
    self.__in.vtable = vtable == nil ? &ImageVTable : vtable
    if self.__in.vtable.Draw == nil do self.__in.vtable.Draw = auto_cast Image_Draw
    if self.__in.vtable.Deinit == nil do self.__in.vtable.Deinit = auto_cast Image_Deinit

    self.__in.vtable.__in.__GetUniformResources = auto_cast __GetUniformResources_Default
}

_Super_Image_Deinit :: proc(self:^Image) {
    xmem.ICheckInit_Deinit(&self.__in.__in.checkInit)
    VkBufferResource_Deinit(&self.__in.__in.matUniform)
}

Image_GetTexture :: #force_inline proc "contextless" (self:^Image) -> ^Texture {
    return self.__in2.src
}
Image_GetCamera :: proc "contextless" (self:^Image) -> ^Camera {
    return IObject_GetCamera(self)
}
Image_GetProjection :: proc "contextless" (self:^Image) -> ^Projection {
    return IObject_GetProjection(self)
}
Image_GetColorTransform :: proc "contextless" (self:^Image) -> ^ColorTransform {
    return IObject_GetColorTransform(self)
}
Image_UpdateTransform :: #force_inline proc(self:^Image, pos:Point3DF, rotation:f32, scale:PointF = {1,1}) {
    IObject_UpdateTransform(self, pos, rotation, scale)
}
Image_UpdateTransformMatrixRaw :: #force_inline proc(self:^Image, _mat:Matrix) {
    IObject_UpdateTransformMatrixRaw(self, _mat)
}
Image_UpdateCamera :: #force_inline proc(self:^Image, camera:^Camera) {
    IObject_UpdateCamera(self, camera)
}
Image_UpdateProjection :: #force_inline proc(self:^Image, projection:^Projection) {
    IObject_UpdateProjection(self, projection)
}
Image_UpdateTexture :: #force_inline proc "contextless" (self:^Image, src:^Texture) {
    self.__in2.src = src
}
Image_UpdateColorTransform :: #force_inline proc(self:^Image, colorTransform:^ColorTransform) {
    IObject_UpdateColorTransform(self, colorTransform)
}
Image_GetPos :: #force_inline proc "contextless" (self:^Image) -> Point3DF {
    return IObject_GetPos(self)
}
Image_GetX :: #force_inline proc "contextless" (self:^Image) -> f32 {
    return IObject_GetX(self)
}
Image_GetY :: #force_inline proc "contextless" (self:^Image) -> f32 {
    return IObject_GetY(self)
}
Image_GetZ :: #force_inline proc "contextless" (self:^Image) -> f32 {
    return IObject_GetZ(self)
}
Image_GetRotation :: #force_inline proc "contextless" (self:^Image) -> f32 {
    return IObject_GetRotation(self)
}
Image_GetScale :: #force_inline proc "contextless" (self:^Image) -> PointF {
    return IObject_GetScale(self)
}
Image_GetScaleX :: #force_inline proc "contextless" (self:^Image) -> f32 {
    return IObject_GetScaleX(self)
}
Image_GetScaleY :: #force_inline proc "contextless" (self:^Image) -> f32 {
    return IObject_GetScaleY(self)
}
Image_SetPos :: #force_inline proc (self:^Image, pos:Point3DF) {
    IObject_SetPos(self, pos)
}
Image_SetX :: #force_inline proc (self:^Image, x:f32) {
    IObject_SetX(self, x)
}
Image_SetY :: #force_inline proc (self:^Image, y:f32) {
    IObject_SetY(self, y)
}
Image_SetZ :: #force_inline proc (self:^Image, z:f32) {
    IObject_SetZ(self, z)
}
Image_SetRotation :: #force_inline proc (self:^Image, rotation:f32) {
    IObject_SetRotation(self, rotation)
}
Image_SetScale :: #force_inline proc (self:^Image, scale:PointF) {
    IObject_SetScale(self, scale)
}
Image_SetScaleX :: #force_inline proc (self:^Image, x:f32) {
    IObject_SetScaleX(self, x)
}
Image_SetScaleY :: #force_inline proc (self:^Image, y:f32) {
    IObject_SetScaleY(self, y)
}

_Super_Image_Draw :: proc (self:^Image, cmd:vk.CommandBuffer) {
    xmem.ICheckInit_Check(&self.__in.__in.checkInit)
    xmem.ICheckInit_Check(&self.__in2.src.__in.checkInit)

    vk.CmdBindPipeline(cmd, .GRAPHICS, vkTexPipeline)
    vk.CmdBindDescriptorSets(cmd, .GRAPHICS, vkTexPipelineLayout, 0, 2, 
        &([]vk.DescriptorSet{self.__in.set.__set, self.__in2.src.__in.set.__set})[0], 0, nil)

    vk.CmdDraw(cmd, 6, 1, 0, 0)
}


//Image End

//AnimateImage


@private AnimateImageVTable := IObjectVTable {
    Draw = auto_cast _Super_AnimateImage_Draw,
    Deinit = auto_cast _Super_AnimateImage_Deinit,
}

AnimateImage_Init :: proc(self:^AnimateImage, $actualType:typeid, src:^TextureArray, pos:Point3DF, rotation:f32, scale:PointF = {1,1}, 
camera:^Camera, projection:^Projection, colorTransform:^ColorTransform = nil, vtable:^IObjectVTable = nil) where intrinsics.type_is_subtype_of(actualType, AnimateImage) {
    self.__in2.src = src
    
    self.__in.set.bindings = __animateImageUniformPoolBinding[:]
    self.__in.set.size = __animateImageUniformPoolSizes[:]
    self.__in.set.layout = vkAnimateTexDescriptorSetLayout

    IObject_Init(self, actualType, pos, rotation, scale, camera, projection, colorTransform)
    self.__in.vtable = vtable == nil ? &AnimateImageVTable : vtable
    if self.__in.vtable.Draw == nil do self.__in.vtable.Draw = auto_cast AnimateImage_Draw
    if self.__in.vtable.Deinit == nil do self.__in.vtable.Deinit = auto_cast AnimateImage_Deinit

    self.__in.vtable.__in.__GetUniformResources = auto_cast __GetUniformResources_AnimateImage
}   

_Super_AnimateImage_Deinit :: proc(self:^AnimateImage) {
    xmem.ICheckInit_Deinit(&self.__in.__in.checkInit)
    VkBufferResource_Deinit(&self.__in.__in.matUniform)
}

AnimateImage_GetTextureArray :: #force_inline proc "contextless" (self:^AnimateImage) -> ^TextureArray {
    return self.__in2.src
}
AnimateImage_GetCamera :: proc "contextless" (self:^AnimateImage) -> ^Camera {
    return self.__in.camera
}
AnimateImage_GetProjection :: proc "contextless" (self:^AnimateImage) -> ^Projection {
    return self.__in.projection
}
AnimateImage_GetColorTransform :: proc "contextless" (self:^AnimateImage) -> ^ColorTransform {
    return self.__in.colorTransform
}
AnimateImage_UpdateTransform :: #force_inline proc(self:^AnimateImage, pos:Point3DF, rotation:f32, scale:PointF = {1,1}) {
    IObject_UpdateTransform(self, pos, rotation, scale)
}
AnimateImage_UpdateTransformMatrixRaw :: #force_inline proc(self:^AnimateImage, _mat:Matrix) {
    IObject_UpdateTransformMatrixRaw(self, _mat)
}
AnimateImage_UpdateColorTransform :: #force_inline proc(self:^AnimateImage, colorTransform:^ColorTransform) {
    IObject_UpdateColorTransform(self, colorTransform)
}
AnimateImage_UpdateCamera :: #force_inline proc(self:^AnimateImage, camera:^Camera) {
    IObject_UpdateCamera(self, camera)
}
AnimateImage_UpdateTextureArray :: #force_inline proc "contextless" (self:^AnimateImage, src:^TextureArray) {
    self.__in2.src = src
}
AnimateImage_UpdateProjection :: #force_inline proc(self:^AnimateImage, projection:^Projection) {
    IObject_UpdateProjection(self, projection)
}
AnimateImage_GetPos :: #force_inline proc "contextless" (self:^AnimateImage) -> Point3DF {
    return IObject_GetPos(self)
}
AnimateImage_GetX :: #force_inline proc "contextless" (self:^AnimateImage) -> f32 {
    return IObject_GetX(self)
}
AnimateImage_GetY :: #force_inline proc "contextless" (self:^AnimateImage) -> f32 {
    return IObject_GetY(self)
}
AnimateImage_GetZ :: #force_inline proc "contextless" (self:^AnimateImage) -> f32 {
    return IObject_GetZ(self)
}
AnimateImage_GetRotation :: #force_inline proc "contextless" (self:^AnimateImage) -> f32 {
    return IObject_GetRotation(self)
}
AnimateImage_GetScale :: #force_inline proc "contextless" (self:^AnimateImage) -> PointF {
    return IObject_GetScale(self)
}
AnimateImage_GetScaleX :: #force_inline proc "contextless" (self:^AnimateImage) -> f32 {
    return IObject_GetScaleX(self)
}
AnimateImage_GetScaleY :: #force_inline proc "contextless" (self:^AnimateImage) -> f32 {
    return IObject_GetScaleY(self)
}
AnimateImage_SetPos :: #force_inline proc (self:^AnimateImage, pos:Point3DF) {
    IObject_SetPos(self, pos)
}
AnimateImage_SetX :: #force_inline proc (self:^AnimateImage, x:f32) {
    IObject_SetX(self, x)
}
AnimateImage_SetY :: #force_inline proc (self:^AnimateImage, y:f32) {
    IObject_SetY(self, y)
}
AnimateImage_SetZ :: #force_inline proc (self:^AnimateImage, z:f32) {
    IObject_SetZ(self, z)
}
AnimateImage_SetRotation :: #force_inline proc (self:^AnimateImage, rotation:f32) {
    IObject_SetRotation(self, rotation)
}
AnimateImage_SetScale :: #force_inline proc (self:^AnimateImage, scale:PointF) {
    IObject_SetScale(self, scale)
}
AnimateImage_SetScaleX :: #force_inline proc (self:^AnimateImage, x:f32) {
    IObject_SetScaleX(self, x)
}
AnimateImage_SetScaleY :: #force_inline proc (self:^AnimateImage, y:f32) {
    IObject_SetScaleY(self, y)
}
_Super_AnimateImage_Draw :: proc (self:^AnimateImage, cmd:vk.CommandBuffer) {
    xmem.ICheckInit_Check(&self.__in.__in.checkInit)
    xmem.ICheckInit_Check(&self.__in2.src.__in.checkInit)

    vk.CmdBindPipeline(cmd, .GRAPHICS, vkAnimateTexPipeline)
    vk.CmdBindDescriptorSets(cmd, .GRAPHICS, vkAnimateTexPipelineLayout, 0, 2, 
        &([]vk.DescriptorSet{self.__in.set.__set, self.__in2.src.__in.set.__set})[0], 0, nil)

    vk.CmdDraw(cmd, 6, 1, 0, 0)
}


//AnimateImage End

//TileImage


@private TileImageVTable := IObjectVTable {
    Draw = auto_cast _Super_TileImage_Draw,
    Deinit = auto_cast _Super_TileImage_Deinit,
}

TileImage_Init :: proc(self:^TileImage, $actualType:typeid, src:^TileTextureArray, pos:Point3DF, rotation:f32, scale:PointF = {1,1}, 
camera:^Camera, projection:^Projection, colorTransform:^ColorTransform = nil, vtable:^IObjectVTable = nil) where intrinsics.type_is_subtype_of(actualType, TileImage) {
    self.__in2.src = src

    self.__in.set.bindings = __tileImageUniformPoolBinding[:]
    self.__in.set.size = __tileImageUniformPoolSizes[:]
    self.__in.set.layout = vkAnimateTexDescriptorSetLayout

    IObject_Init(self, actualType, pos, rotation, scale, camera, projection, colorTransform)
    self.__in.vtable = vtable == nil ? &TileImageVTable : vtable
    if self.__in.vtable.Draw == nil do self.__in.vtable.Draw = auto_cast TileImage_Draw
    if self.__in.vtable.Deinit == nil do self.__in.vtable.Deinit = auto_cast TileImage_Deinit

    self.__in.vtable.__GetUniformResources = auto_cast __GetUniformResources_TileImage
}   

_Super_TileImage_Deinit :: proc(self:^TileImage) {
    xmem.ICheckInit_Deinit(&self.__in.__in.checkInit)
    VkBufferResource_Deinit(&self.__in.__in.matUniform)
}

TileImage_GetTileTextureArray :: #force_inline proc "contextless" (self:^TileImage) -> ^TileTextureArray {
    return self.__in2.src
}
TileImage_UpdateTileTextureArray :: #force_inline proc "contextless" (self:^TileImage, src:^TileTextureArray) {
    self.__in2.src = src
}
TileImage_UpdateTransform :: #force_inline proc(self:^TileImage, pos:Point3DF, rotation:f32, scale:PointF = {1,1}) {
    IObject_UpdateTransform(self, pos, rotation, scale)
}
TileImage_UpdateColorTransform :: #force_inline proc(self:^TileImage, colorTransform:^ColorTransform) {
    IObject_UpdateColorTransform(self, colorTransform)
}
TileImage_UpdateCamera :: #force_inline proc(self:^TileImage, camera:^Camera) {
    IObject_UpdateCamera(self, camera)
}
TileImage_UpdateProjection :: #force_inline proc(self:^TileImage, projection:^Projection) {
    IObject_UpdateProjection(self, projection)
}
TileImage_GetCamera :: proc "contextless" (self:^TileImage) -> ^Camera {
    return IObject_GetCamera(self)
}
TileImage_GetProjection :: proc "contextless" (self:^TileImage) -> ^Projection {
    return IObject_GetProjection(self)
}
TileImage_GetColorTransform :: proc "contextless" (self:^TileImage) -> ^ColorTransform {
    return IObject_GetColorTransform(self)
}
TileImage_UpdateTransformMatrixRaw :: #force_inline proc(self:^TileImage, _mat:Matrix) {
    IObject_UpdateTransformMatrixRaw(self, _mat)
}
TileImage_GetPos :: #force_inline proc "contextless" (self:^TileImage) -> Point3DF {
    return IObject_GetPos(self)
}
TileImage_GetX :: #force_inline proc "contextless" (self:^TileImage) -> f32 {
    return IObject_GetX(self)
}
TileImage_GetY :: #force_inline proc "contextless" (self:^TileImage) -> f32 {
    return IObject_GetY(self)
}
TileImage_GetZ :: #force_inline proc "contextless" (self:^TileImage) -> f32 {
    return IObject_GetZ(self)
}
TileImage_GetRotation :: #force_inline proc "contextless" (self:^TileImage) -> f32 {
    return IObject_GetRotation(self)
}
TileImage_GetScale :: #force_inline proc "contextless" (self:^TileImage) -> PointF {
    return IObject_GetScale(self)
}
TileImage_GetScaleX :: #force_inline proc "contextless" (self:^TileImage) -> f32 {
    return IObject_GetScaleX(self)
}
TileImage_GetScaleY :: #force_inline proc "contextless" (self:^TileImage) -> f32 {
    return IObject_GetScaleY(self)
}
TileImage_SetPos :: #force_inline proc (self:^TileImage, pos:Point3DF) {
    IObject_SetPos(self, pos)
}
TileImage_SetX :: #force_inline proc (self:^TileImage, x:f32) {
    IObject_SetX(self, x)
}
TileImage_SetY :: #force_inline proc (self:^TileImage, y:f32) {
    IObject_SetY(self, y)
}
TileImage_SetZ :: #force_inline proc (self:^TileImage, z:f32) {
    IObject_SetZ(self, z)
}
TileImage_SetRotation :: #force_inline proc (self:^TileImage, rotation:f32) {
    IObject_SetRotation(self, rotation)
}
TileImage_SetScale :: #force_inline proc (self:^TileImage, scale:PointF) {
    IObject_SetScale(self, scale)
}
TileImage_SetScaleX :: #force_inline proc (self:^TileImage, x:f32) {
    IObject_SetScaleX(self, x)
}
TileImage_SetScaleY :: #force_inline proc (self:^TileImage, y:f32) {
    IObject_SetScaleY(self, y)
}

_Super_TileImage_Draw :: proc (self:^TileImage, cmd:vk.CommandBuffer) {
    xmem.ICheckInit_Check(&self.__in.__in.checkInit)
    xmem.ICheckInit_Check(&self.__in2.src.__in.checkInit)

    vk.CmdBindPipeline(cmd, .GRAPHICS, vkAnimateTexPipeline)
    vk.CmdBindDescriptorSets(cmd, .GRAPHICS, vkAnimateTexPipelineLayout, 0, 2, 
        &([]vk.DescriptorSet{self.__in.set.__set, self.__in2.src.__in.set.__set})[0], 0, nil)

    vk.CmdDraw(cmd, 6, 1, 0, 0)
}


//TileImage End


Texture_Init :: proc(self:^Texture, #any_int width:int, #any_int height:int, pixels:Maybe([]byte), sampler:vk.Sampler = 0, resourceUsage:ResourceUsage = .GPU) {
    xmem.ICheckInit_Init(&self.__in.checkInit)
    self.__in.sampler = sampler == 0 ? vkLinearSampler : sampler
    self.__in.set.bindings = __singlePoolBinding[:]
    self.__in.set.size = __singleSamplerPoolSizes[:]
    self.__in.set.layout = vkTexDescriptorSetLayout2
    self.__in.set.__set = 0
   
    VkBufferResource_CreateTexture(&self.__in.texture, {
        width = auto_cast width,
        height = auto_cast height,
        useGCPUMem = false,
        format = .DefaultColor,
        samples = 1,
        len = 1,
        textureUsage = {.IMAGE_RESOURCE},
        type = .TEX2D,
        resourceUsage = resourceUsage,
        single = false,
    }, self.__in.sampler, pixels, true)

    self.__in.set.__resources[0] = &self.__in.texture
    VkUpdateDescriptorSets(mem.slice_ptr(&self.__in.set, 1))
}

//sampler nil default //TODO
// Texture_InitR8 :: proc(self:^Texture, #any_int width:int, #any_int height:int) {
//     xmem.ICheckInit_Init(&self.__in.checkInit)
//     self.__in.sampler = 0
//     self.__in.set.bindings = nil
//     self.__in.set.size = nil
//     self.__in.set.layout = 0
//     self.__in.set.__set = 0

//     VkBufferResource_CreateTexture(&self.__in.texture, {
//         width = auto_cast width,
//         height = auto_cast height,
//         useGCPUMem = false,
//         format = .R8Unorm,
//         samples = 1,
//         len = 1,
//         textureUsage = {.FRAME_BUFFER, .__INPUT_ATTACHMENT},
//         type = .TEX2D,
//         resourceUsage = .GPU,
//         single = true,
//     }, self.__in.sampler, nil)
// }


Texture_InitDepthStencil :: proc(self:^Texture, #any_int width:int, #any_int height:int) {
    xmem.ICheckInit_Init(&self.__in.checkInit)
    self.__in.sampler = 0
    self.__in.set.bindings = nil
    self.__in.set.size = nil
    self.__in.set.layout = 0
    self.__in.set.__set = 0

    VkBufferResource_CreateTexture(&self.__in.texture, {
        width = auto_cast width,
        height = auto_cast height,
        useGCPUMem = false,
        format = .DefaultDepth,
        samples = auto_cast vkMSAACount,
        len = 1,
        textureUsage = {.FRAME_BUFFER},
        type = .TEX2D,
        single = true,
        resourceUsage = .GPU
    }, self.__in.sampler, nil)
}

Texture_InitMSAA :: proc(self:^Texture, #any_int width:int, #any_int height:int) {
    xmem.ICheckInit_Init(&self.__in.checkInit)
    self.__in.sampler = 0
    self.__in.set.bindings = nil
    self.__in.set.size = nil
    self.__in.set.layout = 0
    self.__in.set.__set = 0

    VkBufferResource_CreateTexture(&self.__in.texture, {
        width = auto_cast width,
        height = auto_cast height,
        useGCPUMem = false,
        format = .DefaultColor,
        samples = auto_cast vkMSAACount,
        len = 1,
        textureUsage = {.FRAME_BUFFER,.__TRANSIENT_ATTACHMENT},
        type = .TEX2D,
        single = true,
        resourceUsage = .GPU
    }, self.__in.sampler, nil)
}

Texture_InitFile :: proc(self:^Texture, file:string, sampler:vk.Sampler = 0) {
    //TODO
}
Texture_InitFileData :: proc(self:^Texture, fileData:[]byte, sampler:vk.Sampler = 0) {
    //TODO
}



Texture_Deinit :: proc(self:^Texture) {
    xmem.ICheckInit_Deinit(&self.__in.checkInit)
    VkBufferResource_Deinit(&self.__in.texture)
}

Texture_Width :: #force_inline proc "contextless" (self:^Texture) -> int {
    return auto_cast self.__in.texture.option.width
}
Texture_Height :: #force_inline proc "contextless" (self:^Texture) -> int {
    return auto_cast self.__in.texture.option.height
}

GetDefaultLinearSampler :: #force_inline proc "contextless" () -> vk.Sampler {
    return vkLinearSampler
}
GetDefaultNearestSampler :: #force_inline proc "contextless" () -> vk.Sampler {
    return vkNearestSampler
}

Texture_UpdateSampler :: #force_inline proc "contextless" (self:^Texture, sampler:vk.Sampler) {
    self.__in.sampler = sampler
}
Texture_GetSampler :: #force_inline proc "contextless" (self:^Texture) -> vk.Sampler {
    return self.__in.sampler
}

TextureArray_Init :: proc(self:^TextureArray, #any_int width:int, #any_int height:int, #any_int count:int, pixels:Maybe([]byte), sampler:vk.Sampler = 0) {
    xmem.ICheckInit_Init(&self.__in.checkInit)
    self.__in.sampler = sampler == 0 ? vkLinearSampler : sampler
    self.__in.set.bindings = __singlePoolBinding[:]
    self.__in.set.size = __singleSamplerPoolSizes[:]
    self.__in.set.layout = vkTexDescriptorSetLayout2
    self.__in.set.__set = 0

    VkBufferResource_CreateTexture(&self.__in.texture, {
        width = auto_cast width,
        height = auto_cast height,
        useGCPUMem = false,
        format = .DefaultColor,
        samples = 1,
        len = auto_cast count,
        textureUsage = {.IMAGE_RESOURCE},
        type = .TEX2D,  
    }, self.__in.sampler, pixels, true)
}

//? one animate webp Image file or multiple other image files
//! must same image file width and height
TextureArray_InitFile :: proc(self:^TextureArray, #any_int width:int, #any_int height:int, files:[]string, sampler:vk.Sampler = 0) {
    //TODO
}
//? one animate webp Image file or multiple other image files
//! must same image file width and height
TextureArray_InitFileData :: proc(self:^TextureArray, #any_int width:int, #any_int height:int, fileDatas:[]byte, sampler:vk.Sampler = 0) {
    //TODO
}

TextureArray_Deinit :: #force_inline proc(self:^TextureArray) {
    xmem.ICheckInit_Deinit(&self.__in.checkInit)
    VkBufferResource_Deinit(&self.__in.texture)
}
TextureArray_Width :: #force_inline proc "contextless" (self:^TextureArray) -> int {
    return auto_cast self.__in.texture.option.width
}
TextureArray_Height :: #force_inline proc "contextless" (self:^TextureArray) -> int {
    return auto_cast self.__in.texture.option.height
}
TextureArray_Count :: #force_inline proc "contextless" (self:^TextureArray) -> int {
    return auto_cast self.__in.texture.option.len
}

TileTextureArray_Init :: proc(self:^TileTextureArray, #any_int tile_width:int, #any_int tile_height:int, #any_int width:int, #any_int count:int, pixels:[]byte, sampler:vk.Sampler = 0) {
    xmem.ICheckInit_Init(&self.__in.checkInit)
    self.__in.sampler = sampler == 0 ? vkLinearSampler : sampler
    self.__in.set.bindings = __singlePoolBinding[:]
    self.__in.set.size = __singleSamplerPoolSizes[:]
    self.__in.set.layout = vkTexDescriptorSetLayout2
    self.__in.set.__set = 0
    self.__in.allocPixels = make_non_zeroed_slice([]byte, count * tile_width * tile_height, vkDefAllocator)

    //convert tilemap pixel data format to tile image data format arranged sequentially
    cnt:int
    row := math.floor_div(width, tile_width)
    col := math.floor_div(count, row)
    bit := TextureFmt_BitSize(.DefaultColor)
    for y in 0..<col {
        for x in 0..<row {
            for h in 0..<tile_height {
                start := cnt * (tile_width * tile_height * bit) + h * tile_width * bit
                startP := (y * tile_height + h) * (width * bit) + x * tile_width * bit
                mem.copy_non_overlapping(&self.__in.allocPixels[start], &pixels[startP], tile_width * bit)
            }
            cnt += 1
        }
    }
    VkBufferResource_CreateTexture(&self.__in.texture, {
        width = auto_cast tile_width,
        height = auto_cast tile_height,
        useGCPUMem = false,
        format = .DefaultColor,
        samples = 1,
        len = auto_cast count,
        textureUsage = {.IMAGE_RESOURCE},
        type = .TEX2D,
    }, self.__in.sampler, self.__in.allocPixels, false, vkDefAllocator)
}
TileTextureArray_InitFile :: proc(self:^TileTextureArray, #any_int tile_width:int, #any_int tile_height:int, #any_int width:int, #any_int count:int, files:[]string, sampler:vk.Sampler = 0) {
   //TODO
}
TileTextureArray_InitFileData :: proc(self:^TileTextureArray, #any_int tile_width:int, #any_int tile_height:int, #any_int width:int, #any_int count:int, fileData:[]byte, sampler:vk.Sampler = 0) {
   //TODO
}
TileTextureArray_Deinit :: #force_inline proc(self:^TileTextureArray) {
    xmem.ICheckInit_Deinit(&self.__in.checkInit)
    VkBufferResource_Deinit(&self.__in.texture)
}
TileTextureArray_Width :: #force_inline proc "contextless" (self:^TileTextureArray) -> int {
    return auto_cast self.__in.texture.option.width
}   
TileTextureArray_Height :: #force_inline proc "contextless" (self:^TileTextureArray) -> int {
    return auto_cast self.__in.texture.option.height
}
TileTextureArray_Count :: #force_inline proc "contextless" (self:^TileTextureArray) -> int {
    return auto_cast self.__in.texture.option.len
}

ShapeSrc_InitRaw :: proc(self:^ShapeSrc, raw:^RawShape, flag:ResourceUsage = .GPU, colorFlag:ResourceUsage = .CPU) {
    rawC := RawShape_Clone(raw, vkDefAllocator)
    __VertexBuf_Init(&self.__in.vertexBuf, rawC.vertices, flag)
    __IndexBuf_Init(&self.__in.indexBuf, rawC.indices, flag)
}

@require_results ShapeSrc_Init :: proc(self:^ShapeSrc, shapes:^Shapes, flag:ResourceUsage = .GPU, colorFlag:ResourceUsage = .CPU) -> (err:ShapesError = .None) {
    raw : ^RawShape
    raw, err = Shapes_ComputePolygon(shapes, vkDefAllocator)
    if err != .None do return

    __VertexBuf_Init(&self.__in.vertexBuf, raw.vertices, flag)
    __IndexBuf_Init(&self.__in.indexBuf, raw.indices, flag)
    return
}

ShapeSrc_UpdateRaw :: proc(self:^ShapeSrc, raw:^RawShape) {
    rawC := RawShape_Clone(raw, vkDefAllocator)
    __VertexBuf_Update(&self.__in.vertexBuf, rawC.vertices)
    __IndexBuf_Update(&self.__in.indexBuf, rawC.indices)
}

@require_results ShapeSrc_Update :: proc(self:^ShapeSrc, shapes:^Shapes) -> (err:ShapesError = .None) {
    raw : ^RawShape
    raw, err = Shapes_ComputePolygon(shapes, vkDefAllocator)
    if err != .None do return

    __VertexBuf_Update(&self.__in.vertexBuf, raw.vertices)
    __IndexBuf_Update(&self.__in.indexBuf, raw.indices)
    return
}

ShapeSrc_Deinit :: proc(self:^ShapeSrc) {
    __VertexBuf_Deinit(&self.__in.vertexBuf)
    __IndexBuf_Deinit(&self.__in.indexBuf)
}

//! Non Zeroed Alloc
AllocObject :: #force_inline proc($T:typeid) -> (^T, runtime.Allocator_Error) where intrinsics.type_is_subtype_of(T, IObject) #optional_allocator_error {
    obj, err := mem.alloc_bytes_non_zeroed(size_of(T),align_of(T), vkDefAllocator)
    if err != .None do return nil, err
	return transmute(^T)raw_data(obj), .None
}

//! Non Zeroed Alloc
AllocObjectSlice :: #force_inline proc($T:typeid, #any_int count:int) -> ([]T, runtime.Allocator_Error) where intrinsics.type_is_subtype_of(T, IObject) #optional_allocator_error {
    arr, err := mem.alloc_bytes_non_zeroed(count * size_of(T), align_of(T), vkDefAllocator)
    if err != .None do return nil, err
    s := runtime.Raw_Slice{raw_data(arr), count}
    return transmute([]T)s, .None
}

//! Non Zeroed Alloc
AllocObjectDynamic :: #force_inline proc($T:typeid) -> ([dynamic]T, runtime.Allocator_Error) where intrinsics.type_is_subtype_of(T, IObject) #optional_allocator_error {
    res, err := make_non_zeroed_dynamic_array([dynamic]T, vkDefAllocator)
    if err != .None do return nil, err
    return res, .None
}

FreeObject :: #force_inline proc(obj:^$T) where intrinsics.type_is_subtype_of(T, IObject) {
    aObj := ALLOC_OBJ{
        typeSize = size_of(T),
        len = 1,
        deinit = obj.__in.vtable.Deinit,
        obj = rawptr(obj),
    }
    sync.mutex_lock(&gAllocObjectMtx)
    append(&gAllocObjects, aObj)
    sync.mutex_unlock(&gAllocObjectMtx)
}

FreeObjectSlice :: #force_inline proc(arr:$T/[]$E) where intrinsics.type_is_subtype_of(E, IObject) {
    aObj := ALLOC_OBJ{
        typeSize = size_of(E),
        len = len(arr),
        deinit = len(arr) > 0 ? arr[0].__in.vtable.Deinit : nil,
        obj = rawptr(raw_data(arr)),
    }
    sync.mutex_lock(&gAllocObjectMtx)
    append(&gAllocObjects, aObj)
    sync.mutex_unlock(&gAllocObjectMtx)
}

FreeObjectDynamic :: #force_inline proc(arr:$T/[dynamic]$E) where intrinsics.type_is_subtype_of(E, IObject) {
    aObj := ALLOC_OBJ{
        typeSize = size_of(E),
        len = cap(arr),
        deinit = len(arr) > 0 ? arr[0].__in.vtable.Deinit : nil,
        obj = rawptr(raw_data(arr)),
    }
    sync.mutex_lock(&gAllocObjectMtx)
    append(&gAllocObjects, aObj)
    sync.mutex_unlock(&gAllocObjectMtx)
}