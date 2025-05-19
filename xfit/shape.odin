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

__ShapeSrcIn :: struct {
    //?vertexBuf, indexBuf에 checkInit: ICheckInit 있으므로 따로 필요없음
    vertexBuf:__VertexBuf(ShapeVertex2D),
    indexBuf:__IndexBuf,
}       

ShapeSrc :: struct {
    rect:RectF,
    __in:__ShapeSrcIn,
}

Shape :: struct {
    using object:IObject,
    __in2:__ShapeIn,
}

__ShapeIn :: struct {
    src: ^ShapeSrc,
}

@private ShapeVTable :IObjectVTable = IObjectVTable{
    Draw = auto_cast _Super_Shape_Draw,
    Deinit = auto_cast _Super_Shape_Deinit,
}

ShapeVertex2D :: struct #align(1) {
    pos: PointF,
    uvw: Point3DF,
    color: Point3DwF,
};

Shape_Init :: proc(self:^Shape, $actualType:typeid, src:^ShapeSrc, pos:Point3DF, rotation:f32, scale:PointF = {1,1},
camera:^Camera, projection:^Projection, colorTransform:^ColorTransform = nil, pivot:PointF = {0.0, 0.0}, vtable:^IObjectVTable = nil)
 where intrinsics.type_is_subtype_of(actualType, Shape) {
    self.__in2.src = src

    self.__in.set.bindings = __transformUniformPoolBinding[:]
    self.__in.set.size = __transformUniformPoolSizes[:]
    self.__in.set.layout = vkShapeDescriptorSetLayout

    self.__in.vtable = vtable == nil ? &ShapeVTable : vtable
    if self.__in.vtable.Draw == nil do self.__in.vtable.Draw = auto_cast _Super_Shape_Draw
    if self.__in.vtable.Deinit == nil do self.__in.vtable.Deinit = auto_cast _Super_Shape_Deinit

    self.__in.vtable.__in.__GetUniformResources = auto_cast __GetUniformResources_Default

    IObject_Init(self, actualType, pos, rotation, scale, camera, projection, colorTransform, pivot)
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
Shape_UpdateTransform :: #force_inline proc(self:^Shape, pos:Point3DF, rotation:f32, scale:PointF = {1,1}, pivot:PointF = {0.0,0.0}) {
    IObject_UpdateTransform(self, pos, rotation, scale, pivot)
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

ShapeSrc_InitRaw :: proc(self:^ShapeSrc, raw:^RawShape, flag:ResourceUsage = .GPU, colorFlag:ResourceUsage = .CPU) {
    rawC := RawShape_Clone(raw, vkDefAllocator)
    __VertexBuf_Init(&self.__in.vertexBuf, rawC.vertices, flag)
    __IndexBuf_Init(&self.__in.indexBuf, rawC.indices, flag)
    self.rect = rawC.rect
}

@require_results ShapeSrc_Init :: proc(self:^ShapeSrc, shapes:^Shapes, flag:ResourceUsage = .GPU, colorFlag:ResourceUsage = .CPU) -> (err:ShapesError = .None) {
    raw : ^RawShape
    raw, err = Shapes_ComputePolygon(shapes, vkDefAllocator)
    if err != .None do return

    __VertexBuf_Init(&self.__in.vertexBuf, raw.vertices, flag)
    __IndexBuf_Init(&self.__in.indexBuf, raw.indices, flag)

    self.rect = raw.rect
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


