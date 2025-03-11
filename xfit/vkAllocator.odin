#+private
package xfit

import "base:runtime"
import "core:container/intrusive/list"
import "core:math"
import "core:mem"
import "base:intrinsics"
import "core:slice"
import "core:sync"
import "core:fmt"
import "core:thread"
import vk "vendor:vulkan"
import "xlist"


vkMemBlockLen: VkSize = mem.Megabyte * 256
vkMemSpcialBlockLen: VkSize = mem.Megabyte * 256
vkNonCoherentAtomSize: VkSize = 0
vkPoolBlock: u32 = 256
vkSupportCacheLocal := false
vkSupportNonCacheLocal := false
@(private = "file") __arena: mem.Dynamic_Arena
@(private = "file") __tempArena: mem.Dynamic_Arena
@(private = "file") __bufTempArena: mem.Dynamic_Arena
@(private = "file") __allocArena: mem.Dynamic_Arena
@(private = "file") __allocArenaMtx: mem.Mutex_Allocator
@(private = "file") gQueueMtx: sync.Atomic_Mutex
@(private = "file") gDestroyQueueMtx: sync.Atomic_Mutex
vkArenaAllocator: mem.Allocator
vkTempArenaAllocator: mem.Allocator
vkBufTempArenaAllocator: mem.Allocator

@(private = "file") OpMapCopy :: struct {
	data:      []byte,
	resource:  ^VkBaseResource,
	allocator: Maybe(runtime.Allocator),
}
@(private = "file") OpCopyBuffer :: struct {
	src:    ^VkBufferResource,
	target: ^VkBufferResource,
}
@(private = "file") OpCopyBufferToTexture :: struct {
	src:    ^VkBufferResource,
	target: ^VkTextureResource,
}
@(private = "file") OpCreateBuffer :: struct {
	src:       ^VkBufferResource,
	data:      Maybe([]byte),
	allocator: Maybe(runtime.Allocator),
}
@(private = "file") OpCreateTexture :: struct {
	src:       ^VkTextureResource,
	data:      Maybe([]byte),
	allocator: Maybe(runtime.Allocator),
}
@(private = "file") OpDestroyBuffer :: struct {
	src: ^VkBufferResource,
}
@(private = "file") OpDestroyTexture :: struct {
	src: ^VkTextureResource,
}
@(private = "file") Op__UpdateDescriptorSets :: struct {
	sets: []VkDescriptorSet,
}
//doesn't need to call outside
@(private = "file") Op__RegisterDescriptorPool :: struct {
	size: []VkDescriptorPoolSize,
}

@(private = "file") OpNode :: union {
	OpMapCopy,
	OpCopyBuffer,
	OpCopyBufferToTexture,
	OpCreateBuffer,
	OpCreateTexture,
	OpDestroyBuffer,
	OpDestroyTexture,
	Op__UpdateDescriptorSets,
	Op__RegisterDescriptorPool,
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
    mapData:[^]byte,
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
@(private="file") gFenceNeedWait := false
@(private="file") opQueue:[dynamic]OpNode
@(private="file") opSaveQueue:[dynamic]OpNode
@(private="file") opMapQueue:[dynamic]OpNode
@(private="file") opAllocQueue:[dynamic]OpNode
@(private="file") opDestroyQueue:[dynamic]OpNode
@(private="file") gVkUpdateDesciptorSetList:[dynamic]vk.WriteDescriptorSet
@(private="file") gDesciptorPools:map[[^]VkDescriptorPoolSize][dynamic]VkDescriptorPoolMem

ALLOC_OBJ :: struct {
	typeSize:uint,
	len:uint,
	deinit:proc(obj:^IObject),
	obj:rawptr,
}
gAllocObjects:[dynamic]ALLOC_OBJ
gAllocObjectMtx:sync.Mutex

vkInitBlockLen :: proc() {
	_ChangeSize :: #force_inline proc(heapSize: vk.DeviceSize) {
		if heapSize < mem.Gigabyte {
			vkMemBlockLen /= 16
			vkMemSpcialBlockLen /= 16
		} else if heapSize < 2 * mem.Gigabyte {
			vkMemBlockLen /= 8
			vkMemSpcialBlockLen /= 8
		} else if heapSize < 4 * mem.Gigabyte {
			vkMemBlockLen /= 4
			vkMemSpcialBlockLen /= 4
		} else if heapSize < 8 * mem.Gigabyte {
			vkMemBlockLen /= 2
			vkMemSpcialBlockLen /= 2
		}
	}

	change := false
	mainHeapIdx: u32 = max(u32)
	for h, i in vkPhysicalMemProp.memoryHeaps[:vkPhysicalMemProp.memoryHeapCount] {
		if .DEVICE_LOCAL in h.flags {
			_ChangeSize(h.size)
			change = true
			when is_log {
				printfln(
					"XFIT SYSLOG : Vulkan Graphic Card Dedicated Memory Block %d MB\nDedicated Memory : %d MB",
					vkMemBlockLen / mem.Megabyte,
					h.size / mem.Megabyte,
				)
			}
			mainHeapIdx = auto_cast i
			break
		}
	}
	if !change {
		_ChangeSize(vkPhysicalMemProp.memoryHeaps[0].size)
		when is_log {
			printfln(
				"XFIT SYSLOG : Vulkan No Graphic Card System Memory Block %d MB\nSystem Memory : %d MB",
				vkMemBlockLen / mem.Megabyte,
				vkPhysicalMemProp.memoryHeaps[0].size / mem.Megabyte,
			)
		}
		mainHeapIdx = 0
	}

	reduced := false
	for t, i in vkPhysicalMemProp.memoryTypes[:vkPhysicalMemProp.memoryTypeCount] {
		if t.propertyFlags >= {.DEVICE_LOCAL, .HOST_CACHED, .HOST_VISIBLE} {
			vkSupportCacheLocal = true
			when is_log do printfln("XFIT SYSLOG : Vulkan Device Supported Cache Local Memory")
		} else if t.propertyFlags >= {.DEVICE_LOCAL, .HOST_COHERENT, .HOST_VISIBLE} {
			vkSupportNonCacheLocal = true
			when is_log do printfln("XFIT SYSLOG : Vulkan Device Supported Non Cache Local Memory")
		} else {
			continue
		}
		if mainHeapIdx != t.heapIndex && !reduced {
			vkMemSpcialBlockLen /= min(
				16,
				max(
					1,
					vkPhysicalMemProp.memoryHeaps[mainHeapIdx].size /
					vkPhysicalMemProp.memoryHeaps[t.heapIndex].size,
				),
			)
			reduced = true
		}
	}
}

vkDefAllocator : runtime.Allocator

vkAllocatorInit :: proc() {
	vkDefAllocator = runtime.default_allocator()

	gVkMemBufs = make_non_zeroed([dynamic]^VkMemBuffer, vkDefAllocator)

	gVkMemIdxCnts = make_non_zeroed([]uint, vkPhysicalMemProp.memoryTypeCount, vkDefAllocator)
	mem.zero_slice(gVkMemIdxCnts)

	mem.dynamic_arena_init(&__arena, vkDefAllocator, vkDefAllocator, mem.Megabyte * 4, 0)
	mem.dynamic_arena_init(&__tempArena, vkDefAllocator, vkDefAllocator, mem.Megabyte * 1, 0)
	mem.dynamic_arena_init(&__bufTempArena, vkDefAllocator, vkDefAllocator, mem.Megabyte * 1, 0)
	vkArenaAllocator = mem.dynamic_arena_allocator(&__arena)
	vkTempArenaAllocator = mem.dynamic_arena_allocator(&__tempArena)
	vkBufTempArenaAllocator = mem.dynamic_arena_allocator(&__bufTempArena)

	cmdPoolInfo := vk.CommandPoolCreateInfo {
		sType            = vk.StructureType.COMMAND_POOL_CREATE_INFO,
		queueFamilyIndex = vkGraphicsFamilyIndex,
	}
	vk.CreateCommandPool(vkDevice, &cmdPoolInfo, nil, &cmdPool)

	cmdAllocInfo := vk.CommandBufferAllocateInfo {
		sType = vk.StructureType.COMMAND_BUFFER_ALLOCATE_INFO,
		commandBufferCount = 1,
		level              = .PRIMARY,
		commandPool        = cmdPool,
	}
	vk.AllocateCommandBuffers(vkDevice, &cmdAllocInfo, &gCmd)


	fenceInfo := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
		flags = {.SIGNALED},
	}
	vk.CreateFence(vkDevice, &fenceInfo, nil, &gFence)

	opQueue = make_non_zeroed([dynamic]OpNode, vkArenaAllocator)
	opSaveQueue = make_non_zeroed([dynamic]OpNode, vkArenaAllocator)
	opMapQueue = make_non_zeroed([dynamic]OpNode, vkArenaAllocator)
	opAllocQueue = make_non_zeroed([dynamic]OpNode, vkArenaAllocator)
	opDestroyQueue = make_non_zeroed([dynamic]OpNode, vkArenaAllocator)
	gVkUpdateDesciptorSetList = make_non_zeroed([dynamic]vk.WriteDescriptorSet, vkArenaAllocator)

	gAllocObjects = make_non_zeroed([dynamic]ALLOC_OBJ, vkDefAllocator)
}

vkAllocatorDestroy :: proc() {
	OpAllocQueueFree()

	for b in gVkMemBufs {
		VkMemBuffer_Deinit2(b)
	}
	delete(gVkMemBufs)

	vk.DestroyFence(vkDevice, gFence, nil)
	vk.DestroyCommandPool(vkDevice, cmdPool, nil)

	for _, &value in gDesciptorPools {
		for i in value {
			vk.DestroyDescriptorPool(vkDevice, i.pool, nil)
		}
	}

	mem.dynamic_arena_destroy(&__arena)
	mem.dynamic_arena_destroy(&__tempArena)
	mem.dynamic_arena_destroy(&__bufTempArena)
	mem.dynamic_arena_destroy(&__allocArena)

	delete(gAllocObjects)
	delete(gVkMemIdxCnts, vkDefAllocator)
}

@(private = "file") gVkMemBufs: [dynamic]^VkMemBuffer
@(private = "file") VkMaxMemIdxCnt : uint : 4
@(private = "file") gVkMemIdxCnts: []uint

vkFindMemType :: proc "contextless" (
	typeFilter: u32,
	memProp: vk.MemoryPropertyFlags,
) -> (
	memType: u32,
	success: bool = true,
) {
	for i: u32 = 0; i < vkPhysicalMemProp.memoryTypeCount; i += 1 {
		if ((typeFilter & (1 << i)) != 0) &&
		   (memProp <= vkPhysicalMemProp.memoryTypes[i].propertyFlags) {
			memType = i
			return
		}
	}
	success = false
	return
}
// ! don't call vulkan_res.init separately
@(private = "file") VkMemBuffer_Init :: proc(
	cellSize: VkSize,
	len: VkSize,
	typeFilter: u32,
	memProp: vk.MemoryPropertyFlags,
) -> Maybe(VkMemBuffer) {
	memBuf := VkMemBuffer {
		cellSize = cellSize,
		len = len,
		allocateInfo = {sType = .MEMORY_ALLOCATE_INFO, allocationSize = len * cellSize},
		cache = vk.MemoryPropertyFlags{.HOST_VISIBLE, .HOST_CACHED} <= memProp,
	}
	success: bool
	memBuf.allocateInfo.memoryTypeIndex, success = vkFindMemType(typeFilter, memProp)
	if !success do return nil


	if memBuf.cache {
		memBuf.allocateInfo.allocationSize = ceilUp(len * cellSize, vkNonCoherentAtomSize)
		memBuf.len = memBuf.allocateInfo.allocationSize / cellSize
	}

	res := vk.AllocateMemory(vkDevice, &memBuf.allocateInfo, nil, &memBuf.deviceMem)
	if res != .SUCCESS do return nil


	list.push_back(&memBuf.list, auto_cast new(VkMemBufferNode, vkArenaAllocator))
	((^VkMemBufferNode)(memBuf.list.head)).free = true
	((^VkMemBufferNode)(memBuf.list.head)).size = memBuf.len
	((^VkMemBufferNode)(memBuf.list.head)).idx = 0
	memBuf.cur = memBuf.list.head

	return memBuf
}
@(private = "file") VkMemBuffer_InitSingle :: proc(cellSize: VkSize, typeFilter: u32) -> Maybe(VkMemBuffer) {
	memBuf := VkMemBuffer {
		cellSize = cellSize,
		len = 1,
		allocateInfo = {sType = .MEMORY_ALLOCATE_INFO, allocationSize = 1 * cellSize},
		single = true,
	}
	success: bool
	memBuf.allocateInfo.memoryTypeIndex, success = vkFindMemType(
		typeFilter,
		vk.MemoryPropertyFlags{.DEVICE_LOCAL},
	)
	if !success do panicLog("memBuf.allocateInfo.memoryTypeIndex, success = vkFindMemType(typeFilter, vk.MemoryPropertyFlags{.DEVICE_LOCAL})")

	res := vk.AllocateMemory(vkDevice, &memBuf.allocateInfo, nil, &memBuf.deviceMem)
	if res != .SUCCESS do panicLog("res := vk.AllocateMemory(vkDevice, &memBuf.allocateInfo, nil, &memBuf.deviceMem)")

	return memBuf
}
@(private = "file") VkMemBuffer_Deinit2 :: proc(self: ^VkMemBuffer) {
	vk.FreeMemory(vkDevice, self.deviceMem, nil)
	if !self.single {
		for n: ^list.Node = self.list.head; n.next != nil; n = n.next {
			free(n, vkArenaAllocator)
		}
	}
}
@(private = "file") VkMemBuffer_Deinit :: proc(self: ^VkMemBuffer) {
	for b, i in gVkMemBufs {
		if b == self {
			ordered_remove(&gVkMemBufs, i) //!no unordered
			break
		}
	}
	if !self.single do gVkMemIdxCnts[self.allocateInfo.memoryTypeIndex] -= 1
	VkMemBuffer_Deinit2(self)
	free(self, vkArenaAllocator)
}

VkAllocatorError :: enum {
	NONE,
	DEVICE_MEMORY_LIMIT,
}

@(private = "file") VkMemBuffer_BindBufferNode :: proc(
	self: ^VkMemBuffer,
	vkResource: $T,
	cellCnt: VkSize,
) -> (VkResourceRange, VkAllocatorError) where T == vk.Buffer || T == vk.Image {
	VkMemBuffer_BindBufferNodeInside :: proc(self: ^VkMemBuffer, vkResource: $T, idx: VkSize) where T == vk.Buffer || T == vk.Image {
		when (T == vk.Buffer) {
			res := vk.BindBufferMemory(vkDevice, vkResource, self.deviceMem, self.cellSize * idx)
			if res != .SUCCESS do panicLog("VkMemBuffer_BindBufferNodeInside BindBufferMemory : ", res)
		} else when (T == vk.Image) {
			res := vk.BindImageMemory(vkDevice, vkResource, self.deviceMem, self.cellSize * idx)
			if res != .SUCCESS do panicLog("VkMemBuffer_BindBufferNodeInside BindImageMemory : ", res)
		}
	}
	if cellCnt == 0 do panicLog("if cellCnt == 0")
	if self.single {
		VkMemBuffer_BindBufferNodeInside(self, vkResource, 0)
		return nil, .NONE
	}

	cur: ^VkMemBufferNode = auto_cast self.cur
	for !(cur.free && cellCnt <= cur.size) {
		cur = auto_cast (cur.node.next if cur.node.next != nil else self.list.head)
		if cur == auto_cast self.cur {
			return nil, .DEVICE_MEMORY_LIMIT
		}
	}
	VkMemBuffer_BindBufferNodeInside(self, vkResource, cur.idx)
	cur.free = false
	remain := cur.size - cellCnt
	self.cur = auto_cast cur

	range: VkResourceRange = auto_cast cur
	curNext: ^VkMemBufferNode = auto_cast  (cur.node.next if cur.node.next != nil else self.list.head)
	if cur == curNext {
		if remain > 0 {
			list.push_back(&self.list, auto_cast new(VkMemBufferNode))
			tail: ^VkMemBufferNode = auto_cast self.list.tail
			tail.free = true
			tail.size = remain
			tail.idx = cellCnt
		}
	} else {
		if remain > 0 {
			if !curNext.free || curNext.idx < cur.idx {
				xlist.insert_after(&self.list, auto_cast cur, auto_cast new(VkMemBufferNode))
				next: ^VkMemBufferNode = auto_cast cur.node.next
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
@(private = "file") VkMemBuffer_UnBindBufferNode :: proc(
	self: ^VkMemBuffer,
	vkResource: $T,
	range: VkResourceRange,
) where T == vk.Buffer ||
	T == vk.Image {
		
	when T == vk.Buffer {
		vk.DestroyBuffer(vkDevice, vkResource, nil)
	} else when T == vk.Image {
		vk.DestroyImage(vkDevice, vkResource, nil)
	}

	if self.single {
		VkMemBuffer_Deinit(self)
		return
	}
	range_: ^VkMemBufferNode = auto_cast range
	range_.free = true

	next: ^VkMemBufferNode = auto_cast (range_.node.next if range_.node.next != nil else self.list.head)
	if next.free && range_ != next && range_.idx < next.idx {
		range_.size += next.size
		list.remove(&self.list, auto_cast next)
		free(next, vkArenaAllocator)
	}

	prev: ^VkMemBufferNode = auto_cast (range_.node.prev if range_.node.prev != nil else self.list.tail)
	if prev.free && range_ != prev && range_.idx > prev.idx {
		range_.size += prev.size
		range_.idx -= prev.size
		list.remove(&self.list, auto_cast prev)
		free(prev, vkArenaAllocator)
	}
	if self.len == 1 || gVkMemIdxCnts[self.allocateInfo.memoryTypeIndex] > VkMaxMemIdxCnt {
		for b in gVkMemBufs {
			if self != b && self.allocateInfo.memoryTypeIndex == b.allocateInfo.memoryTypeIndex && VkMemBuffer_IsEmpty(b) {
				gVkMemIdxCnts[b.allocateInfo.memoryTypeIndex] -= 1
				VkMemBuffer_Deinit(b)
			}
		}
		if VkMemBuffer_IsEmpty(self) {
			gVkMemIdxCnts[self.allocateInfo.memoryTypeIndex] -= 1
			VkMemBuffer_Deinit(self)
		}
	}

}

@(private = "file") VkMemBuffer_CreateFromResource :: proc(
	vkResource: $T,
	memProp: vk.MemoryPropertyFlags,
	outIdx: ^VkResourceRange,
	maxSize: VkSize,
) -> (memBuf: ^VkMemBuffer) where T == vk.Buffer || T == vk.Image {
	memType:u32
	ok:bool

	_BindBufferNode :: proc(b: ^VkMemBuffer, memType: u32, vkResource: $T, cellCnt:VkSize, outIdx: ^VkResourceRange, memBuf: ^^VkMemBuffer) -> bool {
		if b.allocateInfo.memoryTypeIndex != memType {
			return false
		}
		outIdx_, err := VkMemBuffer_BindBufferNode(b, vkResource, cellCnt)
		if err != .NONE {
			return false
		}
		if outIdx_ == nil {
			panicLog("")
		}
		outIdx^ = outIdx_
		memBuf^ = b
		return true
	}
	_Init :: proc(BLKSize:VkSize, maxSize_:VkSize, memRequire: vk.MemoryRequirements, memProp_:vk.MemoryPropertyFlags) -> Maybe(VkMemBuffer) {
		memBufTLen := max(BLKSize, maxSize_) / memRequire.alignment + 1
		if max(BLKSize, maxSize_) % memRequire.alignment == 0 do memBufTLen -= 1
		return VkMemBuffer_Init(
			memRequire.alignment,
			memBufTLen,
			memRequire.memoryTypeBits,
			memProp_,
		)
	}
	memRequire: vk.MemoryRequirements
	when T == vk.Buffer {
		vk.GetBufferMemoryRequirements(vkDevice, vkResource, &memRequire)
	} else when T == vk.Image {
		vk.GetImageMemoryRequirements(vkDevice, vkResource, &memRequire)
	}

	maxSize_ := maxSize
	if maxSize_ < memRequire.size do maxSize_ = memRequire.size

	memProp_ := memProp
	if ((vkMemBlockLen == vkMemSpcialBlockLen) ||
		   ((T == vk.Buffer && maxSize_ <= 256))) &&
	   (.HOST_VISIBLE in memProp_) {
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
		memType, ok = vkFindMemType(memRequire.memoryTypeBits, memProp_)
		if !ok {
			memProp_ = memProp
			memType, ok = vkFindMemType(memRequire.memoryTypeBits, memProp_)
			if !ok do panicLog("vkFindMemType Failed")
		}
		if !_BindBufferNode(b, memType, vkResource, cellCnt, outIdx, &memBuf) do continue
		break
	}

	if memBuf == nil {
		memBuf = new(VkMemBuffer, vkArenaAllocator)

		memFlag := vk.MemoryPropertyFlags{.HOST_VISIBLE, .DEVICE_LOCAL}
		BLKSize := vkMemSpcialBlockLen if memProp_ >= memFlag else vkMemBlockLen
		memBufT := _Init(BLKSize, maxSize_, memRequire, memProp_)

		if memBufT == nil {
			free(memBuf)
			memBuf = nil

			memProp_ = {.HOST_VISIBLE, .HOST_CACHED}
			for b in gVkMemBufs {
				if b.cellSize != memRequire.alignment do continue
				memType, ok := vkFindMemType(memRequire.memoryTypeBits, memProp_)
				if !ok do panicLog("")
				if !_BindBufferNode(b, memType, vkResource, cellCnt, outIdx, &memBuf) do continue
				break
			}
			if memBuf == nil {
				BLKSize = vkMemBlockLen
				memBufT = _Init(BLKSize, maxSize_, memRequire, memProp_)
				if memBufT == nil do panicLog("")
				memBuf^ = memBufT.?
			}
		} else {
			memBuf^ = memBufT.?
		}

		if !_BindBufferNode(memBuf, memBuf.allocateInfo.memoryTypeIndex, vkResource, cellCnt, outIdx, &memBuf) do panicLog("")
		non_zero_append(&gVkMemBufs, memBuf)
	}
	gVkMemIdxCnts[memBuf.allocateInfo.memoryTypeIndex] += 1
	return
}

@(private = "file") VkMemBuffer_CreateFromResourceSingle :: proc(vkResource: $T) -> (memBuf: ^VkMemBuffer) 
where T == vk.Buffer || T == vk.Image {
	memBuf = nil
	memRequire: vk.MemoryRequirements

	when T == vk.Buffer {
		vk.GetBufferMemoryRequirements(vkDevice, vkResource, &memRequire)
	} else when T == vk.Image {
		vk.GetImageMemoryRequirements(vkDevice, vkResource, &memRequire)
	}

	memBuf = new(VkMemBuffer, vkArenaAllocator)
	outMemBuf :=  VkMemBuffer_InitSingle(memRequire.size, memRequire.memoryTypeBits)
	memBuf^ = outMemBuf.?

	VkMemBuffer_BindBufferNode(memBuf, vkResource, 1) //can't (must no) error

	non_zero_append(&gVkMemBufs, memBuf)
	return
}

@(private = "file") AppendOp :: proc(node: OpNode) {
	if exiting {
		#partial switch n in node {
		case OpMapCopy:
			if n.allocator != nil do delete(n.data, n.allocator.?)
			return
		case OpCreateBuffer:
			if n.allocator != nil && n.data != nil do delete(n.data.?, n.allocator.?)
			return
		case OpCreateTexture:
			if n.allocator != nil && n.data != nil do delete(n.data.?, n.allocator.?)
			return
		}
	} else {
		_Handle :: #force_inline proc(n: $T, node: OpNode) -> bool {
			if n.allocator != nil {
				sync.atomic_mutex_lock(&gQueueMtx)
				non_zero_append(&opAllocQueue, node)
				non_zero_append(&opQueue, node)
				sync.atomic_mutex_unlock(&gQueueMtx)
				return true
			}
			return false
		}
		#partial switch n in node {
		case OpMapCopy:
			if _Handle(n, node) do return
		case OpCreateBuffer:
			if _Handle(n, node) do return
		case OpCreateTexture:
			if _Handle(n, node) do return
		}
	}
	sync.atomic_mutex_lock(&gQueueMtx)
	non_zero_append(&opQueue, node)
	sync.atomic_mutex_unlock(&gQueueMtx)
}

@(private = "file") AppendOpSave :: proc(node: OpNode) {
	#partial switch n in node {
	case OpMapCopy, OpCreateBuffer, OpCreateTexture:
		sync.atomic_mutex_lock(&gQueueMtx)
		non_zero_append(&opAllocQueue, node)
		sync.atomic_mutex_unlock(&gQueueMtx)
	}
	non_zero_append(&opSaveQueue, node)
}


VkBufferResource_CreateBuffer :: proc(
	self: ^VkBufferResource,
	option: BufferCreateOption,
	data: Maybe([]byte),
	isCopy: bool = false,
	allocator: Maybe(runtime.Allocator) = nil,
) {
	self.option = option
	if isCopy {
		copyData:[]byte
		if allocator == nil {
			copyData = make_non_zeroed([]byte, len(data.?), vkDefAllocator)
		} else {
			copyData = make_non_zeroed([]byte, len(data.?), allocator.?)
		}
		mem.copy(raw_data(copyData), raw_data(data.?), len(data.?))
		AppendOp(OpCreateBuffer{src = self, data = copyData, allocator = allocator == nil ? vkDefAllocator : allocator.?})
	} else {
		AppendOp(OpCreateBuffer{src = self, data = data, allocator = allocator})
	}
}
VkBufferResource_CreateTexture :: proc(
	self: ^VkTextureResource,
	option: TextureCreateOption,
	sampler: vk.Sampler,
	data: Maybe([]byte),
	isCopy: bool = false,
	allocator: Maybe(runtime.Allocator) = nil,
) {
	self.sampler = sampler
	self.option = option
	if isCopy {
		copyData:[]byte
		if allocator == nil {
			copyData = make_non_zeroed([]byte, len(data.?), vkDefAllocator)
		} else {
			copyData = make_non_zeroed([]byte, len(data.?), allocator.?)
		}
		mem.copy(raw_data(copyData), raw_data(data.?), len(data.?))
		AppendOp(OpCreateTexture{src = self, data = copyData, allocator = allocator == nil ? vkDefAllocator : allocator.?})
	} else {
		AppendOp(OpCreateTexture{src = self, data = data, allocator = allocator})
	}
}

@(private = "file") VkBufferResource_CreateBufferNoAsync :: #force_inline proc(
	self: ^VkBufferResource,
	option: BufferCreateOption,
	data: Maybe([]byte),
	allocator: Maybe(runtime.Allocator) = nil,
) {
	self.option = option
	ExecuteCreateBuffer(self, data, allocator)
}

@(private = "file") VkBufferResource_DestroyBufferNoAsync :: proc(self: ^VkBufferResource) {
	VkMemBuffer_UnBindBufferNode(self.vkMemBuffer, self.__resource, self.idx)
	self.__resource = 0
}

@(private = "file") VkBufferResource_DestroyTextureNoAsync :: proc(self: ^VkTextureResource) {
	vk.DestroyImageView(vkDevice, self.imgView, nil)
	VkMemBuffer_UnBindBufferNode(self.vkMemBuffer, self.__resource, self.idx)
	self.__resource = 0
}

@(private = "file") VkBufferResource_MapCopy :: #force_inline proc(
	self: ^VkBaseResource,
	data: []byte,
	allocator: Maybe(runtime.Allocator) = nil,
) {
	AppendOp(OpMapCopy{allocator = allocator, data = data, resource = self})
}

//! unlike CopyUpdate, data cannot be a temporary variable.
VkBufferResource_MapUpdateSlice :: #force_inline proc(
	self: ^VkBaseResource,
	data: $T/[]$E,
	allocator: Maybe(runtime.Allocator) = nil,
) {
	VkBufferResource_MapCopy(self, mem.slice_to_bytes(data), allocator)
}
//! unlike CopyUpdate, data cannot be a temporary variable.
VkBufferResource_MapUpdate :: #force_inline proc(
	self: ^VkBaseResource,
	data: ^$T,
	allocator: Maybe(runtime.Allocator) = nil,
) {
	VkBufferResource_MapCopy(self, mem.ptr_to_bytes(data), allocator)
}

VkBufferResource_CopyUpdateSlice :: #force_inline proc(
	self: ^VkBaseResource,
	data: $T/[]$E,
	allocator: Maybe(runtime.Allocator) = nil,
) {
	bytes := mem.slice_to_bytes(data)
	copyData:[]byte
	if allocator == nil {
		copyData = make_non_zeroed([]byte, len(bytes), vkDefAllocator)
	} else {
		copyData = make_non_zeroed([]byte, len(bytes), allocator.?)
	}
	intrinsics.mem_copy_non_overlapping(raw_data(copyData), raw_data(bytes), len(bytes))

	VkBufferResource_MapCopy(self, copyData, allocator == nil ? vkDefAllocator : allocator.?)
}
VkBufferResource_CopyUpdate :: #force_inline proc(
	self: ^VkBaseResource,
	data: ^$T,
	allocator: Maybe(runtime.Allocator) = nil,
) {
	copyData:[]byte
	bytes := mem.ptr_to_bytes(data)
	if allocator == nil {
		copyData = make_non_zeroed([]byte, len(bytes), vkDefAllocator)
	} else {
		copyData = make_non_zeroed([]byte, len(bytes), allocator.?)
	}
	intrinsics.mem_copy_non_overlapping(raw_data(copyData), raw_data(bytes), len(bytes))
	VkBufferResource_MapCopy(self, copyData, allocator == nil ? vkDefAllocator : allocator.?)
}

VkBufferResource_Deinit :: proc(self: ^$T) where T == VkBufferResource || T == VkTextureResource {
	when T == VkBufferResource {
		buffer: ^VkBufferResource = auto_cast self
		buffer.option.len = 0
		AppendOp(OpDestroyBuffer{src = buffer})
	} else when T == VkTextureResource {
		texture: ^VkTextureResource = auto_cast self
		texture.option.len = 0
		if self.vkMemBuffer == nil {
			vk.DestroyImageView(vkDevice, texture.imgView, nil)
		} else {
			AppendOp(OpDestroyTexture{src = texture})
		}
	}
}
//no need @(private="file") VkBufferResource_CreateTextureNoAsync


//not mul cellsize
@(private = "file") VkMemBuffer_Map :: #force_inline proc "contextless" (
	self: ^VkMemBuffer,
	start: VkSize,
	size: VkSize,
) -> [^]byte {
	outData: rawptr
	vk.MapMemory(vkDevice, self.deviceMem, start, size, {}, &outData)
	return auto_cast outData
}
@(private = "file") VkMemBuffer_UnMap :: #force_inline proc "contextless" (self: ^VkMemBuffer) {
	self.mapSize = 0
	vk.UnmapMemory(vkDevice, self.deviceMem)
}

@(private = "file") ExecuteCreateBuffer :: proc(
	self: ^VkBufferResource,
	data: Maybe([]byte),
	allocator: Maybe(runtime.Allocator) = nil,
) {
	if self.option.type == .__STAGING {
		self.option.resourceUsage = .CPU
		self.option.single = false
	}

	memProp : vk.MemoryPropertyFlags;
	switch self.option.resourceUsage {
		case .GPU:memProp = {.DEVICE_LOCAL}
		case .CPU:memProp = {.HOST_CACHED, .HOST_VISIBLE}
	}
	bufUsage:vk.BufferUsageFlags
	switch self.option.type {
		case .VERTEX: bufUsage = {.VERTEX_BUFFER}
		case .INDEX: bufUsage = {.INDEX_BUFFER}
		case .UNIFORM: bufUsage = {.UNIFORM_BUFFER}
		case .__STAGING: bufUsage = {.TRANSFER_SRC}
	}

	//fmt.println(self.option.type, bufUsage)

	bufInfo := vk.BufferCreateInfo{
		sType = .BUFFER_CREATE_INFO,
		size = self.option.len,
		usage = bufUsage,
		sharingMode = .EXCLUSIVE
	}

	last:^VkBufferResource
	if data != nil && self.option.resourceUsage == .GPU {
		bufInfo.usage |= {.TRANSFER_DST}
		if self.option.len > auto_cast len(data.?) do panicLog("create_buffer _data not enough size. ", self.option.len, ", ", len(data.?))
		
		last = new(VkBufferResource, vkBufTempArenaAllocator)
		last^ = {}
		VkBufferResource_CreateBufferNoAsync(last, {
			len = self.option.len,
			resourceUsage = .CPU,
			single = false,
			type = .__STAGING,
		}, data, allocator)
	} else if self.option.type == .__STAGING {
		if data == nil do panicLog("staging buffer data can't nil")
	}

	res := vk.CreateBuffer(vkDevice, &bufInfo, nil, &self.__resource)
	if res != .SUCCESS do panicLog("res := vk.CreateBuffer(vkDevice, &bufInfo, nil, &self.__resource) : ", res)

	self.vkMemBuffer = VkMemBuffer_CreateFromResourceSingle(self.__resource) if self.option.single else
	VkMemBuffer_CreateFromResource(self.__resource, memProp, &self.idx, 0)

	if data != nil {
		if self.option.resourceUsage != .GPU {
			AppendOpSave(OpMapCopy{
				resource = auto_cast self,
				data = data.?,
				allocator = allocator
			})
		} else {
			 //above VkBufferResource_CreateBufferNoAsync call, staging buffer is added and map_copy command is added.
			AppendOpSave(OpCopyBuffer{src = last, target = self})
			AppendOpSave(OpDestroyBuffer{src = last})
		}
	}
}
@(private = "file") ExecuteCreateTexture :: proc(
	self: ^VkTextureResource,
	data: Maybe([]byte),
	allocator: Maybe(runtime.Allocator) = nil,
) {
	memProp : vk.MemoryPropertyFlags;
	switch self.option.resourceUsage {
		case .GPU:memProp = {.DEVICE_LOCAL}
		case .CPU:memProp = {.HOST_CACHED, .HOST_VISIBLE}
	}
	texUsage:vk.ImageUsageFlags = {}
	isDepth := TextureFmt_IsDepth(self.option.format)

	if .IMAGE_RESOURCE in self.option.textureUsage do texUsage |= {.SAMPLED}
	if .FRAME_BUFFER in self.option.textureUsage {
		if isDepth {
			texUsage |= {.DEPTH_STENCIL_ATTACHMENT}
		} else {
			texUsage |= {.COLOR_ATTACHMENT}
		}
	}
	if .__INPUT_ATTACHMENT in self.option.textureUsage do texUsage |= {.INPUT_ATTACHMENT}
	if .__TRANSIENT_ATTACHMENT in self.option.textureUsage do texUsage |= {.TRANSIENT_ATTACHMENT}

	tiling :vk.ImageTiling = .OPTIMAL

	if isDepth {
		if (.DEPTH_STENCIL_ATTACHMENT in texUsage && !vkDepthHasOptimal) ||
			(.SAMPLED in texUsage && !vkDepthHasSampleOptimal) ||
			(.TRANSFER_SRC in texUsage && !vkDepthHasTransferSrcOptimal) ||
			(.TRANSFER_DST in texUsage && !vkDepthHasTransferDstOptimal) {
			tiling = .LINEAR
		}
	} else {
		if (.COLOR_ATTACHMENT in texUsage && !vkColorHasAttachOptimal) ||
			(.SAMPLED in texUsage && !vkColorHasSampleOptimal) ||
			(.TRANSFER_SRC in texUsage && !vkColorHasTransferSrcOptimal) ||
			(.TRANSFER_DST in texUsage && !vkColorHasTransferDstOptimal) {
			tiling = .LINEAR
		}
	}
	bit : u32 = auto_cast TextureFmt_BitSize(self.option.format)

	imgInfo := vk.ImageCreateInfo{
		sType = .IMAGE_CREATE_INFO,
		arrayLayers = self.option.len,
		usage = texUsage,
		sharingMode = .EXCLUSIVE,
		extent = {width = self.option.width, height = self.option.height, depth = 1},
		samples = samplesToVkSampleCountFlags(self.option.samples),
		tiling = tiling,
		mipLevels = 1,
		format = TextureFmtToVkFmt(self.option.format),
		imageType = TextureTypeToVkImageType(self.option.type),
		initialLayout = .UNDEFINED,
	}

	last:^VkBufferResource
	if data != nil && self.option.resourceUsage == .GPU {
		imgInfo.usage |= {.TRANSFER_DST}
		
		last = new(VkBufferResource, vkBufTempArenaAllocator)
		last^ = {}
		VkBufferResource_CreateBufferNoAsync(last, {
			len = auto_cast(imgInfo.extent.width * imgInfo.extent.height * imgInfo.extent.depth * imgInfo.arrayLayers * bit),
			resourceUsage = .CPU,
			single = false,
			type = .__STAGING,
		}, data, allocator)
	}

	res := vk.CreateImage(vkDevice, &imgInfo, nil, &self.__resource)
	if res != .SUCCESS do panicLog("res := vk.CreateImage(vkDevice, &bufInfo, nil, &self.__resource) : ", res)

	self.vkMemBuffer = VkMemBuffer_CreateFromResourceSingle(self.__resource) if self.option.single else
	VkMemBuffer_CreateFromResource(self.__resource, memProp, &self.idx, 0)

	imgViewInfo := vk.ImageViewCreateInfo{
		sType = .IMAGE_VIEW_CREATE_INFO,
		format = imgInfo.format,
		components = {r = .IDENTITY, g = .IDENTITY, b = .IDENTITY, a = .IDENTITY},
		image = self.__resource,
		subresourceRange = {
			aspectMask = isDepth ? {.DEPTH, .STENCIL} : {.COLOR},
			baseMipLevel = 0,
			levelCount = 1,
			baseArrayLayer = 0,
			layerCount = imgInfo.arrayLayers,
		},
	}
	switch self.option.type {
		case .TEX2D: imgViewInfo.viewType = imgInfo.arrayLayers > 1 ? .D2_ARRAY : .D2
	}
	
	res = vk.CreateImageView(vkDevice, &imgViewInfo, nil, &self.imgView)
	if res != .SUCCESS do panicLog("res = vk.CreateImageView(vkDevice, &imgViewInfo, nil, &self.imgView) : ", res)

	if data != nil {
		if self.option.resourceUsage != .GPU {
			AppendOpSave(OpMapCopy{
				resource = auto_cast self,
				data = data.?,
				allocator = allocator
			})
		} else {
			 //above VkBufferResource_CreateBufferNoAsync call, staging buffer is added and map_copy command is added.
			AppendOpSave(OpCopyBufferToTexture{src = last, target = self})
			AppendOpSave(OpDestroyBuffer{src = last})
		}
	}
}
@(private = "file") ExecuteRegisterDescriptorPool :: #force_inline proc(size: []VkDescriptorPoolSize) {
	//?? no need? execute_register_descriptor_pool
}
@(private = "file") __CreateDescriptorPool :: proc(size:[]VkDescriptorPoolSize, out:^VkDescriptorPoolMem) {
	poolSize :[]vk.DescriptorPoolSize = make_non_zeroed([]vk.DescriptorPoolSize, len(size), context.temp_allocator)
	defer delete(poolSize, context.temp_allocator)

	for _, i in size {
		poolSize[i].descriptorCount = size[i].cnt * vkPoolBlock
		poolSize[i].type = DescriptorTypeToVkDescriptorType(size[i].type)
	}
	poolInfo := vk.DescriptorPoolCreateInfo{
		sType = .DESCRIPTOR_POOL_CREATE_INFO,
		poolSizeCount = auto_cast len(poolSize),
		pPoolSizes = raw_data(poolSize),
		maxSets = vkPoolBlock,
	}
	res := vk.CreateDescriptorPool(vkDevice, &poolInfo, nil, &out.pool)
	if res != .SUCCESS do panicLog("res := vk.CreateDescriptorPool(vkDevice, &poolInfo, nil, &out.pool) : ", res)
}

VkUpdateDescriptorSets :: proc(sets: []VkDescriptorSet) {
	AppendOp(Op__UpdateDescriptorSets{sets = sets})
}

@(private = "file") ExecuteUpdateDescriptorSets :: proc(sets: []VkDescriptorSet) {
	for &s in sets {
		if s.__set == 0 {
			if raw_data(s.size) in gDesciptorPools {
			} else {
				gDesciptorPools[raw_data(s.size)] = make_non_zeroed([dynamic]VkDescriptorPoolMem, vkArenaAllocator)
				non_zero_append(&gDesciptorPools[raw_data(s.size)], VkDescriptorPoolMem{cnt = 0})
				__CreateDescriptorPool(s.size, &gDesciptorPools[raw_data(s.size)][0])
			}

			last := &gDesciptorPools[raw_data(s.size)][len(gDesciptorPools[raw_data(s.size)]) - 1]
			if last.cnt >= vkPoolBlock {
				non_zero_append(&gDesciptorPools[raw_data(s.size)], VkDescriptorPoolMem{cnt = 0})
				last = &gDesciptorPools[raw_data(s.size)][len(gDesciptorPools[raw_data(s.size)]) - 1]
				__CreateDescriptorPool(s.size, last)
			}

			last.cnt += 1
			allocInfo := vk.DescriptorSetAllocateInfo{
				sType = .DESCRIPTOR_SET_ALLOCATE_INFO,
				descriptorPool = last.pool,
				descriptorSetCount = 1,
				pSetLayouts = &s.layout,
			}
			res := vk.AllocateDescriptorSets(vkDevice, &allocInfo, &s.__set)
			if res != .SUCCESS do panicLog("res := vk.AllocateDescriptorSets(vkDevice, &allocInfo, &s.__set) : ", res)
		}

		cnt:u32 = 0
		bufCnt:u32 = 0
		texCnt:u32 = 0

		//sets[i].__resources array must match v.size configuration.
		for s in s.size {
			cnt += s.cnt
		}
		
		for r in s.__resources[0:cnt] {
			switch v in r {
				case ^VkBufferResource:
					bufCnt += 1
				case ^VkTextureResource:
					texCnt += 1
				case:
					panicLog("invaild type s.__resources[0:cnt] r")
			}
		}

		bufs := make_non_zeroed([]vk.DescriptorBufferInfo, bufCnt, vkTempArenaAllocator)
		texs := make_non_zeroed([]vk.DescriptorImageInfo, texCnt, vkTempArenaAllocator)
		bufCnt = 0
		texCnt = 0

		for r in s.__resources[0:cnt] {
			switch v in r {
				case ^VkBufferResource:
					bufs[bufCnt] = vk.DescriptorBufferInfo{
						buffer = ((^VkBufferResource)(v)).__resource,
						offset = 0,
						range = ((^VkBufferResource)(v)).option.len
					}
					bufCnt += 1
				case ^VkTextureResource:
					texs[texCnt] = vk.DescriptorImageInfo{
						imageLayout = .SHADER_READ_ONLY_OPTIMAL,
						imageView = ((^VkTextureResource)(v)).imgView,
						sampler = ((^VkTextureResource)(v)).sampler,
					}
					texCnt += 1
			}
		}

		bufCnt = 0
		texCnt = 0
		for n, i in s.size {	
			switch n.type {
				case .SAMPLER:
					non_zero_append(&gVkUpdateDesciptorSetList, vk.WriteDescriptorSet{
						dstSet = s.__set,
						dstBinding = s.bindings[i],
						dstArrayElement = 0,
						descriptorCount = n.cnt,
						descriptorType = DescriptorTypeToVkDescriptorType(n.type),
						pBufferInfo = nil,
						pImageInfo = &texs[texCnt],
						pTexelBufferView = nil,
						sType = .WRITE_DESCRIPTOR_SET,
						pNext = nil,
					})
					texCnt += n.cnt
				case .UNIFORM:
					non_zero_append(&gVkUpdateDesciptorSetList, vk.WriteDescriptorSet{
						dstSet = s.__set,
						dstBinding = s.bindings[i],
						dstArrayElement = 0,
						descriptorCount = n.cnt,
						descriptorType = DescriptorTypeToVkDescriptorType(n.type),
						pBufferInfo = &bufs[bufCnt],
						pImageInfo = nil,
						pTexelBufferView = nil,
						sType = .WRITE_DESCRIPTOR_SET,
						pNext = nil,
					})
					bufCnt += n.cnt
			}
		}
	}
}
@(private = "file") ExecuteCopyBuffer :: proc(src: ^VkBufferResource, target: ^VkBufferResource) {
	copyRegion := vk.BufferCopy{
		size = target.option.len,
		srcOffset = 0,
		dstOffset = 0
	}
	vk.CmdCopyBuffer(gCmd, src.__resource, target.__resource, 1, &copyRegion)
}
@(private = "file") ExecuteCopyBufferToTexture :: proc(src: ^VkBufferResource, target: ^VkTextureResource) {
	vkTransitionImageLayout(gCmd, target.__resource, 1, 0, target.option.len, .UNDEFINED, .TRANSFER_DST_OPTIMAL)
	region := vk.BufferImageCopy{
		bufferOffset = 0,
		bufferRowLength = 0,
		bufferImageHeight = 0,
		imageOffset = {x = 0,y = 0,z = 0},
		imageExtent = {width = target.option.width, height = target.option.height, depth = 1},
		imageSubresource = {
			aspectMask = {.COLOR},
			baseArrayLayer = 0,
			mipLevel = 0,
			layerCount = target.option.len
		}
	}
	vk.CmdCopyBufferToImage(gCmd, src.__resource, target.__resource, .TRANSFER_DST_OPTIMAL, 1, &region)
	vkTransitionImageLayout(gCmd, target.__resource, 1, 0, target.option.len, .TRANSFER_DST_OPTIMAL, .SHADER_READ_ONLY_OPTIMAL)
}
@(private = "file") OpAllocQueueFree :: proc() {
	sync.atomic_mutex_lock(&gQueueMtx)
	defer sync.atomic_mutex_unlock(&gQueueMtx)

	for node in opAllocQueue {
		#partial switch n in node {
		case OpMapCopy:
			if n.allocator != nil do delete(n.data, n.allocator.?)
		}
	}
	clear(&opAllocQueue)
}
@(private = "file") SaveToMapQueue :: proc(inoutMemBuf: ^^VkMemBuffer) {
	for &node in opSaveQueue {
		#partial switch n in node {
		case OpMapCopy:
			if inoutMemBuf^ == nil {
				non_zero_append(&opMapQueue, n)
				inoutMemBuf^ = n.resource.vkMemBuffer
				node = nil
			} else if n.resource.vkMemBuffer == inoutMemBuf^ {
				non_zero_append(&opMapQueue, n)
				node = nil
			}
		}
	}
}
@(private = "file") VkMemBuffer_MapCopyExecute :: proc(self: ^VkMemBuffer, nodes: []OpNode) {
	startIdx: VkSize = max(VkSize)
	endIdx: VkSize = max(VkSize)
	offIdx: u32 = 0

	ranges: []vk.MappedMemoryRange
	if self.cache {
		ranges = make_non_zeroed([]vk.MappedMemoryRange, len(nodes))

		for i in 0 ..< len(nodes) {
			idx: ^VkMemBufferNode = auto_cast (nodes[i].(OpMapCopy)).resource.idx
			ranges[i].memory = self.deviceMem
			ranges[i].size = idx.size * self.cellSize
			ranges[i].offset = idx.idx * self.cellSize

			tmp := ranges[i].offset
			ranges[i].offset = floorUp(ranges[i].offset, vkNonCoherentAtomSize)
			ranges[i].size += tmp - ranges[i].offset
			ranges[i].size = ceilUp(ranges[i].size, vkNonCoherentAtomSize)

			startIdx = min(startIdx, ranges[i].offset)
			endIdx = max(endIdx, ranges[i].offset + ranges[i].size)

			//when range overlaps. merge them.
			for &r in ranges[:offIdx] {
				if r.offset < ranges[i].offset + ranges[i].size && r.offset + r.size > ranges[i].offset {
					end_ := max(ranges[i].offset + ranges[i].size, r.offset + r.size)
					r.offset = min(ranges[i].offset, r.offset)
					r.size = end_ - r.offset

					for &r2 in ranges[:offIdx] {
						if r.offset != r2.offset && r2.offset < r.offset + r.size && r2.offset + r2.size > r.offset { 	//both sides overlap
							end_2 := max(r2.offset + r.size, r.offset + r.size)
							r.offset = min(r2.offset, r.offset)
							r.size = end_2 - r.offset
							if r2.offset != ranges[offIdx - 1].offset {
								slice.ptr_swap_non_overlapping(
									&ranges[offIdx - 1].offset,
									&r2.offset,
									size_of(r2.offset),
								)
								slice.ptr_swap_non_overlapping(
									&ranges[offIdx - 1].size,
									&r2.size,
									size_of(r2.size),
								)
							}
							offIdx -= 1
							break
						}
					}
					offIdx -= 1
					break
				}
			}

			ranges[i].pNext = nil
			ranges[i].sType = vk.StructureType.MAPPED_MEMORY_RANGE
			offIdx += 1
		}
	} else {
		for node in nodes {
			idx: ^VkMemBufferNode = auto_cast (node.(OpMapCopy)).resource.idx
			startIdx = min(startIdx, idx.idx * self.cellSize)
			endIdx = max(endIdx, (idx.idx + idx.size) * self.cellSize)
		}
	}

	size := endIdx - startIdx

	if self.mapStart > startIdx || self.mapSize + self.mapStart < endIdx || self.mapSize < endIdx - startIdx {
		if self.mapSize > 0 do VkMemBuffer_UnMap(self)
		outData: [^]byte = VkMemBuffer_Map(self, startIdx, size)
		self.mapData = outData
		self.mapSize = size
		self.mapStart = startIdx
	} else {
		if self.cache {
			res := vk.InvalidateMappedMemoryRanges(vkDevice, offIdx, raw_data(ranges))
			if res != .SUCCESS do panicLog("res := vk.InvalidateMappedMemoryRanges(vkDevice, offIdx, raw_data(ranges)) : ", res)
		}
	}

	for &node in nodes {
		mapCopy := &node.(OpMapCopy)
		idx: ^VkMemBufferNode = auto_cast mapCopy.resource.idx
		start_ := idx.idx * self.cellSize - self.mapStart
		mem.copy_non_overlapping(&self.mapData[start_], raw_data(mapCopy.data), len(mapCopy.data))
	}

	if self.cache {
		res := vk.FlushMappedMemoryRanges(vkDevice, auto_cast len(ranges), raw_data(ranges))
		if res != .SUCCESS do panicLog("res := vk.FlushMappedMemoryRanges(vkDevice, auto_cast len(ranges), raw_data(ranges)) : ", res)
	}
}

@(private = "file") ExecuteDestroyBuffer :: proc(buf:^VkBufferResource) {
	VkBufferResource_DestroyBufferNoAsync(buf)
}
@(private = "file") ExecuteDestroyTexture :: proc(tex:^VkTextureResource) {
	VkBufferResource_DestroyTextureNoAsync(tex)
}

//? delete private when need
@(private = "file") VkMemBuffer_IsEmpty :: proc(self: ^VkMemBuffer) -> bool {
	return !self.single && ((self.list.head != nil &&
		self.list.head.next == nil &&
		((^VkMemBufferNode)(self.list.head)).free) || 
		(self.list.head == nil))
}

vkOpExecuteDestroy :: proc() {
	sync.atomic_mutex_lock(&gDestroyQueueMtx)
	if len(opDestroyQueue) == 0 {
		sync.atomic_mutex_unlock(&gDestroyQueueMtx)
		return
	}
	for node in opDestroyQueue {
		#partial switch n in node {
			case OpDestroyBuffer : 
				ExecuteDestroyBuffer(n.src)
			case OpDestroyTexture : 
				ExecuteDestroyTexture(n.src)
		}
	}
	sync.mutex_lock(&gAllocObjectMtx)
	for &o in gAllocObjects {
		for i in 0 ..< o.len {
			o.deinit(  auto_cast &(([^]byte)(o.obj))[i * o.typeSize] )
		}
		mem.free_with_size(o.obj, int(o.len * o.typeSize), vkDefAllocator)
	}
	clear(&gAllocObjects)
	sync.mutex_unlock(&gAllocObjectMtx)
	
	clear(&opDestroyQueue)

	sync.atomic_mutex_unlock(&gDestroyQueueMtx)
	mem.dynamic_arena_reset(&__bufTempArena)
}
vkWaitAllocatorCmdFence :: #force_inline proc  "contextless" () {
	if gFenceNeedWait {
		res := vk.WaitForFences(vkDevice, 1, &gFence, true, max(u64))
		if res != .SUCCESS do panicLog("res := vk.WaitForFences(vkDevice, 1, &gFence, true, max(u64)) : ", res)
		gFenceNeedWait = false
	}
}
vkOpExecute :: proc(waitAndDestroy: bool) {
	sync.atomic_mutex_lock(&gQueueMtx)
	if len(opQueue) == 0 {
		sync.atomic_mutex_unlock(&gQueueMtx)
		if waitAndDestroy {
			vkWaitAllocatorCmdFence()
			vkOpExecuteDestroy()
		}
		return
	}
	resize(&opSaveQueue, len(opQueue))
	mem.copy_non_overlapping(raw_data(opSaveQueue), raw_data(opQueue), len(opQueue) * size_of(OpNode))
	clear(&opQueue)
	sync.atomic_mutex_unlock(&gQueueMtx)

	clear(&opMapQueue)
	for &node in opSaveQueue {
		#partial switch n in node {
		case OpCreateBuffer:
			ExecuteCreateBuffer(n.src, n.data, n.allocator)
		case OpCreateTexture:
			ExecuteCreateTexture(n.src, n.data, n.allocator)
		case Op__RegisterDescriptorPool:
			ExecuteRegisterDescriptorPool(n.size)
		case:
			continue
		}
		node = nil
	}

	sync.atomic_mutex_lock(&gDestroyQueueMtx)
	for &node in opSaveQueue {
		#partial switch n in node {
		case OpDestroyBuffer:
			non_zero_append(&opDestroyQueue, n)
		case OpDestroyTexture:
			non_zero_append(&opDestroyQueue, n)
		case:
			continue
		}
		node = nil
	}
	sync.atomic_mutex_unlock(&gDestroyQueueMtx)
	// for &node in opSaveQueue {
	// 	#partial switch n in node {
	// 	case OpDestroyBuffer:
	// 	case OpDestroyTexture:
	// 		node = nil
	// 	}
	// }

	memBufT: ^VkMemBuffer = nil
	SaveToMapQueue(&memBufT)
	for len(opMapQueue) > 0 {
		VkMemBuffer_MapCopyExecute(memBufT, opMapQueue[:])
		clear(&opMapQueue)
		memBufT = nil
		SaveToMapQueue(&memBufT)
	}

	OpAllocQueueFree()

	haveCmds := false
	for node in opSaveQueue {
		#partial switch n in node {
		case OpCopyBuffer:
			haveCmds = true
		case OpCopyBufferToTexture:
			haveCmds = true
		case Op__UpdateDescriptorSets:
			ExecuteUpdateDescriptorSets(n.sets)
		}
	}
	if len(gVkUpdateDesciptorSetList) > 0 {
		vk.UpdateDescriptorSets(
			vkDevice,
			auto_cast len(gVkUpdateDesciptorSetList),
			raw_data(gVkUpdateDesciptorSetList),
			0,
			nil,
		)
		clear(&gVkUpdateDesciptorSetList)
		//?call callback this line
	}

	if haveCmds {
		vk.ResetCommandPool(vkDevice, cmdPool, {})

		beginInfo := vk.CommandBufferBeginInfo {
			flags = {.ONE_TIME_SUBMIT},
			sType = vk.StructureType.COMMAND_BUFFER_BEGIN_INFO,
		}
		vk.BeginCommandBuffer(gCmd, &beginInfo)
		for node in opSaveQueue {
			#partial switch n in node {
			case OpCopyBuffer:
				ExecuteCopyBuffer(n.src, n.target)
			case OpCopyBufferToTexture:
				ExecuteCopyBufferToTexture(n.src, n.target)
			}
		}
		vk.EndCommandBuffer(gCmd)

		gFenceNeedWait = true
		vk.ResetFences(vkDevice, 1, &gFence)
		submitInfo := vk.SubmitInfo {
			commandBufferCount = 1,
			pCommandBuffers    = &gCmd,
			sType              = .SUBMIT_INFO,
		}
		res := vk.QueueSubmit(vkGraphicsQueue, 1, &submitInfo, gFence)
		if res != .SUCCESS do panicLog("res := vk.QueueSubmit(vkGraphicsQueue, 1, &submitInfo, 0) : ", res)

		vkWaitAllocatorCmdFence()
		vkOpExecuteDestroy()
	} else if waitAndDestroy {
		vkWaitAllocatorCmdFence()
		vkOpExecuteDestroy()
	}

	mem.dynamic_arena_reset(&__tempArena)

	clear(&opSaveQueue)
}

