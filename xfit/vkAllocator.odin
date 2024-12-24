#+private
package xfit

import vk "vendor:vulkan"
import "core:mem"
import "core:container/intrusive/list"
import "xmath"
import "core:math"
import "core:c"
import "xlist"

vkMemBlockLen :VkSize = mem.Megabyte * 256
vkMemSpcialBlockLen :VkSize = mem.Megabyte * 256
vkNonCoherentAtomSize :VkSize = 0
vkSupportCacheLocal := false
vkSupportNonCacheLocal := false
@(private="file") __arena:mem.Dynamic_Arena
@(private="file") __tempArena:mem.Dynamic_Arena
vkArenaAllocator:mem.Allocator
vkTempArenaAllocator:mem.Allocator

@(private="file") OpMapCopy :: struct {
    memBuf:^VkMemBuffer,
    buf:[]u8,

}

@(private="file") OpNode :: union {
    OpMapCopy
}

VkMemBufferNode :: struct {
    node : list.Node,
    size:VkSize,
    idx:VkSize,
    free:bool
}
VkMemBuffer :: struct {
    cellSize:VkSize,
    mapStart:VkSize,
    mapSize:VkSize,
    mapData:[^]u8,
    len:VkSize,
    deviceMem:vk.DeviceMemory,
    single:bool,
    cache:bool,
    cur:^list.Node,
    list:list.List,
    allocateInfo:vk.MemoryAllocateInfo,
}

@(private="file") cmdPool:vk.CommandPool
@(private="file") gCmd:vk.CommandBuffer
@(private="file") gFence:vk.Fence
@(private="file") opQueue:[dynamic]OpNode
@(private="file") opSaveQueue:[dynamic]OpNode
@(private="file") opMapQueue:[dynamic]OpNode
@(private="file") opAllocQueue:[dynamic]OpNode
@(private="file") opDestroyQueue:[dynamic]OpNode
@(private="file") gVkUpdateDesciptorSetList:[dynamic]vk.WriteDescriptorSet
@(private="file") gDesciptorPools:map[[^]VkDescriptorPoolSize][dynamic]VkDescriptorPoolMem


vkInitBlockLen :: proc  "contextless" () {
    for h,i in vkPhysicalMemProp.memoryHeaps[:vkPhysicalMemProp.memoryHeapCount] {

    }
}

vkAllocatorInit :: proc() {
    gVkMemIdxCnts = make([]uint, vkPhysicalMemProp.memoryTypeCount)
    mem.zero_slice(gVkMemIdxCnts)

    mem.dynamic_arena_init(&__arena, context.allocator, context.allocator, mem.Megabyte * 4)
    mem.dynamic_arena_init(&__tempArena, context.allocator, context.allocator, mem.Megabyte * 1)

    vkArenaAllocator :=  mem.dynamic_arena_allocator(&__arena)
    vkTempArenaAllocator :=  mem.dynamic_arena_allocator(&__tempArena)

    cmdPoolInfo := vk.CommandPoolCreateInfo{
        sType = vk.StructureType.COMMAND_POOL_CREATE_INFO,
        queueFamilyIndex = vkGraphicsFamilyIndex,
    }
    vk.CreateCommandPool(vkDevice, &cmdPoolInfo, nil, &cmdPool)

    cmdAllocInfo := vk.CommandBufferAllocateInfo{
        commandBufferCount = 1,
        level = .PRIMARY,
        commandPool = cmdPool,
    }
    vk.AllocateCommandBuffers(vkDevice, &cmdAllocInfo, &gCmd)

    fenceInfo := vk.FenceCreateInfo{
        sType = .FENCE_CREATE_INFO,
        flags = {.SIGNALED},
    }
    vk.CreateFence(vkDevice, &fenceInfo, nil, &gFence)

    opQueue = make([dynamic]OpNode, vkArenaAllocator)
    opSaveQueue = make([dynamic]OpNode, vkArenaAllocator)
    opMapQueue = make([dynamic]OpNode, vkArenaAllocator)
    opAllocQueue = make([dynamic]OpNode, vkArenaAllocator)
    opDestroyQueue = make([dynamic]OpNode, vkArenaAllocator)
    gVkUpdateDesciptorSetList = make([dynamic]vk.WriteDescriptorSet, vkArenaAllocator)
}

vkAllocatorDestroy :: proc() {
    vk.DestroyFence(vkDevice, gFence, nil)
    vk.DestroyCommandPool(vkDevice, cmdPool, nil)

    mem.dynamic_arena_destroy(&__arena)
    mem.dynamic_arena_destroy(&__tempArena)

    delete(gVkMemIdxCnts)
}


@(private="file") gVkMemBufs:[dynamic]^VkMemBuffer
@(private="file") gVkMemIdxCnts:[]uint

vkFindMemType :: proc "contextless" (typeFilter:u32, memProp:vk.MemoryPropertyFlags) -> (memType:u32, success:bool = true) {
    for i : u32 = 0;i < vkPhysicalMemProp.memoryTypeCount;i += 1 {
        if ((typeFilter & (1 << i)) != 0) && (memProp <= vkPhysicalMemProp.memoryTypes[i].propertyFlags) {
            memType = i
            return
        }
    }
    success = false
    return
}
// ! don't call vulkan_res.init separately
@(private="file") VkMemBuffer_Init :: proc(cellSize:VkSize, len:VkSize, typeFilter:u32, memProp:vk.MemoryPropertyFlags) -> Maybe(VkMemBuffer) {
    memBuf := VkMemBuffer {
        cellSize = cellSize,
        len = len,
        allocateInfo = {
            sType = .MEMORY_ALLOCATE_INFO,
            allocationSize = len * cellSize,
        },
        cache = vk.MemoryPropertyFlags{.HOST_VISIBLE, .HOST_CACHED} <= memProp
    }
    success:bool
    memBuf.allocateInfo.memoryTypeIndex, success = vkFindMemType(typeFilter, memProp)
    if !success do return nil


    if memBuf.cache {
        memBuf.allocateInfo.allocationSize = xmath.ceilUp(len * cellSize, vkNonCoherentAtomSize)
        memBuf.len = memBuf.allocateInfo.allocationSize / cellSize
    }

    res := vk.AllocateMemory(vkDevice, &memBuf.allocateInfo, nil, &memBuf.deviceMem)
    if res != .SUCCESS do return nil


    list.push_back(&memBuf.list, auto_cast new(VkMemBufferNode, vkArenaAllocator))
    ((^VkMemBufferNode)(memBuf.list.head)).free = true
    ((^VkMemBufferNode)(memBuf.list.head)).size = memBuf.len
    ((^VkMemBufferNode)(memBuf.list.head)).idx = 0

    return memBuf
}
@(private="file") VkMemBuffer_InitSingle :: proc(cellSize:VkSize, typeFilter:u32) -> Maybe(VkMemBuffer) {
    memBuf := VkMemBuffer {
        cellSize = cellSize,
        len = 1,
        allocateInfo = {
            sType = .MEMORY_ALLOCATE_INFO,
            allocationSize = 1 * cellSize,
        },
        single = true,
    }
    success:bool
    memBuf.allocateInfo.memoryTypeIndex, success = vkFindMemType(typeFilter, vk.MemoryPropertyFlags{.DEVICE_LOCAL})
    if !success do panicLog("memBuf.allocateInfo.memoryTypeIndex, success = vkFindMemType(typeFilter, vk.MemoryPropertyFlags{.DEVICE_LOCAL})")

    res := vk.AllocateMemory(vkDevice, &memBuf.allocateInfo, nil, &memBuf.deviceMem)
    if res != .SUCCESS do panicLog("res := vk.AllocateMemory(vkDevice, &memBuf.allocateInfo, nil, &memBuf.deviceMem)")
    
    return memBuf
}
@(private="file") VkMemBuffer_DeInit2 :: proc(self:^VkMemBuffer) {
    vk.FreeMemory(vkDevice, self.deviceMem, nil)
    if !self.single {
        for n:^list.Node;n.next != nil;n = n.next {
            free(n, vkArenaAllocator)
        }
    }
}
@(private="file") VkMemBuffer_DeInit :: proc(self:^VkMemBuffer) {
    for b,i in gVkMemBufs {
        if b == self {
            ordered_remove(&gVkMemBufs, i)
            break
        }
    }
    if !self.single do gVkMemIdxCnts[self.allocateInfo.memoryTypeIndex] -= 1
    VkMemBuffer_DeInit2(self)
    free(self, vkArenaAllocator)
}

VkAllocatorError :: enum {
    NONE,
    DEVICE_MEMORY_LIMIT
}


@(private="file") VkMemBuffer_BindBufferNode :: proc(self:^VkMemBuffer, vkResource:$T, cellCnt:VkSize) -> (VkResourceRange, VkAllocatorError) {
    VkMemBuffer_BindBufferNodeInside :: proc(self:^VkMemBuffer, vkResource:$T, idx:VkSize) {
        if(T == vk.Buffer) {
            res := vk.BindBufferMemory(vkDevice, vkResource, self.deviceMem, self.cellSize * idx)
            if res != .SUCCESS do panicLog("VkMemBuffer_BindBufferNodeInside BindBufferMemory : ", res)
        } else if(T == vk.Image) {
            res := vk.BindImageMemory(vkDevice, vkResource, self.deviceMem, self.cellSize * idx)
            if res != .SUCCESS do panicLog("VkMemBuffer_BindBufferNodeInside BindImageMemory : ", res)
        } else {
            #panic("VkMemBuffer_BindBufferNodeInside invaild resource type")
        }
    }
    if cellCnt == 0 do panicLog("if cellCnt == 0")
    if self.single {
        VkMemBuffer_BindBufferNodeInside(self, vkResource, 0)
        return nil, .NONE
    }

    cur : ^VkMemBufferNode = auto_cast self.cur
    for cur.free && cellCnt <= cur.size {
        cur = auto_cast (cur.node.next if cur.node.next != nil else self.list.head)
        if cur == self.cur do return nil, .DEVICE_MEMORY_LIMIT
    }
    VkMemBuffer_BindBufferNodeInside(self, vkResource, cur.idx)
    cur.free = false
    remain := cur.size - cellCnt
    self.cur = auto_cast cur

    range:VkResourceRange = auto_cast cur
    curNext :^VkMemBufferNode = auto_cast cur.node.next
    if cur == curNext {
        if remain > 0 {
            list.push_back(&self.list, auto_cast new(VkMemBufferNode))
            tail :^VkMemBufferNode = auto_cast self.list.tail
            tail.free = true
            tail.size = remain
            tail.idx = cellCnt
        }
    } else {
        if remain > 0 {
            if !curNext.free || curNext.idx < cur.idx  {
                xlist.insert_after(&self.list, cur, auto_cast new(VkMemBufferNode))
                next :^VkMemBufferNode = auto_cast cur.node.next
                next.free = true
                next.idx = cur.idx + cellCnt
                next.size = remain
            } else {
                curNext.idx -= remain
                curNext.size += remain
            }
        }
    }
    cur.size = cellCnt
    return range, .NONE
}
@(private="file") VkMemBuffer_UnBindBufferNode :: proc(self:^VkMemBuffer, vkResource:$T, range:VkResourceRange)  {
    
}

@(private="file") VkMemBuffer_CreateFromResource :: proc(vkResource:$T,
memProp:vk.MemoryPropertyFlags,
outIdx:^VkResourceRange,
maxSize:VkSize,
useGCPUMem:bool) -> (memBuf:^VkMemBuffer) {
    _BindBufferNode :: proc(b:^VkMemBuffer) -> bool {
        if b.allocateInfo.memoryTypeIndex != memType do return false
        outIdx_, err := VkMemBuffer_BindBufferNode(b, vkResource, cellCnt)
        if err != .NONE do return false
        if outIdx_ == nil do panicLog("")
        outIdx^ = outIdx_
        memBuf = b
        return true
    }
    _Init :: proc() -> Maybe(VkMemBuffer) {
        memBufTLen := max(BLKSize, maxSize_) / memRequire.alignment + 1
        if max(BLKSize, maxSize_) % memRequire.alignment == 0 do memBufTLen -= 1
        return VkMemBuffer_Init(memRequire.alignment, memBufTLen, memRequire.memoryTypeBits, memProp_)
    }
    memRequire:vk.MemoryRequirements
    if T == vk.Buffer {
        vk.GetBufferMemoryRequirements(vkDevice, vkResource, &memRequire)
    } else if T == vk.Image {
        vk.GetImageMemoryRequirements(vkDevice, vkResource, &memRequire)
    } else {
        #panic("VkMemBuffer_CreateFromResource invaild resource type")
    }
    
    maxSize_ := maxSize
    if maxSize_ < memRequire.size do maxSize_ = memRequire.size
    
    memProp_ := memProp
    if ((vkMemBlockLen == vkMemSpcialBlockLen) || ((T == vk.Buffer && maxSize_ <= 256) || useGCPUMem)) && (.HOST_VISIBLE in memProp_) {
        if vkSupportCacheLocal {
            memProp_ = {.HOST_VISIBLE, .HOST_CACHED, .DEVICE_LOCAL}
        } else if vkSupportNonCacheLocal {
            memProp_ = {.HOST_VISIBLE, .HOST_COHERENT, .DEVICE_LOCAL}
        }
    }

    cellCnt := maxSize_ / memRequire.alignment + 1
    if maxSize_ % memRequire.alignment == 0 do cellCnt -= 1

    memBuf = nil
    for b in gVkMemBufs {
        if b.cellSize != memRequire.alignment do continue
        memType, ok := vkFindMemType(memRequire.memoryTypeBits, memProp_)
        if !ok {
            memProp_ = memProp
            memType, ok = vkFindMemType(memRequire.memoryTypeBits, memProp_)
            if !ok do panicLog("vkFindMemType Failed")
        }
        if !_BindBufferNode(b) do continue
        break
    }

    if memBuf == nil {
        memBuf = new(VkMemBuffer, vkArenaAllocator)

        memFlag := vk.MemoryPropertyFlags{.HOST_VISIBLE, .DEVICE_LOCAL}
        BLKSize = vkMemSpcialBlockLen if memProp_ >= memFlag else vkMemBlockLen
        memBufT := _Init()

        if memBufT == nil {
            free(memBuf)
            memBuf = nil

            memProp_ = {.HOST_VISIBLE,.HOST_CACHED}
            for b in gVkMemBufs {
                if b.cellSize != memRequire.alignment do continue
                memType, ok = vkFindMemType(memRequire.memoryTypeBits, memProp_)
                if !ok do panicLog("")
                if !_BindBufferNode(b) do continue
                break
            }
            if memBuf == nil {
                BLKSize = vkMemBlockLen
                memBufT = _Init()
                if memBufT == nil do panicLog("")
                memBuf^ = memBufT.?
            }
        } else {
            memBuf^ = memBufT.?
        }

        if !_BindBufferNode(memBuf) do panicLog("")
        append(&gVkMemBufs, memBuf)
    }
    gVkMemIdxCnts[memBuf.allocateInfo.memoryTypeIndex] += 1
    return
}
