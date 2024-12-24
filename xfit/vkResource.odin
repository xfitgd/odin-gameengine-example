#+private
package xfit

import vk "vendor:vulkan"
import "core:mem"
import "core:container/intrusive/list"
import "xmath"
import "core:math"
import "core:c"
import "xlist"

VkSize :: vk.DeviceSize

VkResourceRange :: rawptr

TextureType :: enum {
    TEX2D,
    TEX2DARRAY,
    TEX3D,
}
TextureUsage :: enum {
    IMAGE_RESOURCE,
    FRAME_BUFFER,
    __INPUT_ATTACHMENT,
    __TRANSIENT_ATTACHMENT,
}
TextureUsages :: bit_set[TextureUsage]
ResourceUsage :: enum {GPU,CPU}

TextureCreateOption :: struct {
    len:VkSize,
    width:u32,
    height:u32,
    type:TextureType,
    textureUsage:TextureUsages,
    resourceUsage:ResourceUsage,
    format:TextureFmt,
    samples:u8,
    single:bool,
    useGCPUMem:bool,
}

BufferType :: enum {
    VERTEX,
    INDEX,
    UNIFORM,
    __STAGING
}

BufferCreateOption :: struct {
    len:VkSize,
    type:BufferType,
    resourceUsage:ResourceUsage,
    single:bool,
    useGCPUMem:bool,
}


VkUnionResource :: union #no_nil {
    VkBufferResource,
    VkTextureResource
}
VkBaseResource :: struct {
    idx:VkResourceRange,
    vkMemBuffer:^VkMemBuffer,
}
VkBufferResource :: struct {
    using _:VkBaseResource,
    option:BufferCreateOption,
}
VkTextureResource :: struct {
    using _:VkBaseResource,
    imgView:vk.ImageView,
    sampler:vk.Sampler,
    option:TextureCreateOption,
}

VkDescriptorType :: enum {
    SAMPLER,  //vk.DescriptorType.SAMPLER
    UNIFORM,  //vk.DescriptorType.UNIFORM_BUFFER
}
VkDescriptorPoolSize :: struct {type:VkDescriptorType, cnt:u32}
VkDescriptorPoolMem :: struct {pool:vk.DescriptorPool, cnt:u32}