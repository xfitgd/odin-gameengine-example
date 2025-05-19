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
    using textureArrayIn:__TextureArrayIn,
    allocPixels:[]byte,
}

Image :: struct {
    using object:IObject,
    __in2: __ImageIn,
}

__ImageIn :: struct {
    src: ^Texture,
}

AnimateImage :: struct {
    using object:IObject,
    __in2: __AnimateImageIn,
}

__AnimateImageIn :: struct {
    frameUniform:VkBufferResource,
    frame:u32,
    src: ^TextureArray,
}

TileImage :: struct {
    using object:IObject,
    __in2: __TileImageIn,
}

__TileImageIn :: struct {
    tileUniform:VkBufferResource,
    tileIdx:u32,
    src: ^TileTextureArray,
}

IsAnyImageType :: #force_inline proc "contextless" ($ANY_IMAGE:typeid) -> bool {
    return intrinsics.type_is_subtype_of(ANY_IMAGE, IObject) && intrinsics.type_has_field(ANY_IMAGE, "src") && 
    (intrinsics.type_field_type(ANY_IMAGE, "src") == Texture ||
    intrinsics.type_field_type(ANY_IMAGE, "src") == TextureArray ||
    intrinsics.type_field_type(ANY_IMAGE, "src") == TileTextureArray)
}

@private ImageVTable :IObjectVTable = IObjectVTable {
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
Image_UpdateTransform :: #force_inline proc(self:^Image, pos:Point3DF, rotation:f32, scale:PointF = {1,1}, pivot:PointF = {0.0,0.0}) {
    IObject_UpdateTransform(self, pos, rotation, scale, pivot)
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

_Super_Image_Draw :: proc (self:^Image, cmd:vk.CommandBuffer) {
    xmem.ICheckInit_Check(&self.__in.__in.checkInit)
    xmem.ICheckInit_Check(&self.__in2.src.__in.checkInit)

    vk.CmdBindPipeline(cmd, .GRAPHICS, vkTexPipeline)
    vk.CmdBindDescriptorSets(cmd, .GRAPHICS, vkTexPipelineLayout, 0, 2, 
        &([]vk.DescriptorSet{self.__in.set.__set, self.__in2.src.__in.set.__set})[0], 0, nil)

    vk.CmdDraw(cmd, 6, 1, 0, 0)
}


@private AnimateImageVTable :IObjectVTable = IObjectVTable {
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
AnimateImage_UpdateTransform :: #force_inline proc(self:^AnimateImage, pos:Point3DF, rotation:f32, scale:PointF = {1,1}, pivot:PointF = {0.0,0.0}) {
    IObject_UpdateTransform(self, pos, rotation, scale, pivot)
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
_Super_AnimateImage_Draw :: proc (self:^AnimateImage, cmd:vk.CommandBuffer) {
    xmem.ICheckInit_Check(&self.__in.__in.checkInit)
    xmem.ICheckInit_Check(&self.__in2.src.__in.checkInit)

    vk.CmdBindPipeline(cmd, .GRAPHICS, vkAnimateTexPipeline)
    vk.CmdBindDescriptorSets(cmd, .GRAPHICS, vkAnimateTexPipelineLayout, 0, 2, 
        &([]vk.DescriptorSet{self.__in.set.__set, self.__in2.src.__in.set.__set})[0], 0, nil)

    vk.CmdDraw(cmd, 6, 1, 0, 0)
}

@private TileImageVTable :IObjectVTable = IObjectVTable {
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
TileImage_UpdateTransform :: #force_inline proc(self:^TileImage, pos:Point3DF, rotation:f32, scale:PointF = {1,1}, pivot:PointF = {0.0, 0.0}) {
    IObject_UpdateTransform(self, pos, rotation, scale, pivot)
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

_Super_TileImage_Draw :: proc (self:^TileImage, cmd:vk.CommandBuffer) {
    xmem.ICheckInit_Check(&self.__in.__in.checkInit)
    xmem.ICheckInit_Check(&self.__in2.src.__in.checkInit)

    vk.CmdBindPipeline(cmd, .GRAPHICS, vkAnimateTexPipeline)
    vk.CmdBindDescriptorSets(cmd, .GRAPHICS, vkAnimateTexPipelineLayout, 0, 2, 
        &([]vk.DescriptorSet{self.__in.set.__set, self.__in2.src.__in.set.__set})[0], 0, nil)

    vk.CmdDraw(cmd, 6, 1, 0, 0)
}


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


ImagePixelPerfectPoint :: proc "contextless" (img:^$ANY_IMAGE, p:PointF, canvasW:f32, canvasH:f32, pivot:ImageCenterPtPos) -> PointF where IsAnyImageType(ANY_IMAGE) {
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

    #partial switch pivot {
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
