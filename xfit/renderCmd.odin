package xfit


import "core:sync"
import vk "vendor:vulkan"


RenderCmd :: struct {}

@(private) __RenderCmd :: struct {
    scene: [dynamic]^IObject,
    sceneT: [dynamic]^IObject,
    refresh:[MAX_FRAMES_IN_FLIGHT]bool,
    cmds:[MAX_FRAMES_IN_FLIGHT][]vk.CommandBuffer,
    objLock:sync.RW_Mutex
}

@private gRenderCmd : [dynamic]^__RenderCmd
@private gMainRenderCmdIdx : int = -1

@private gRenderCmdMtx : sync.Mutex

RenderCmd_Init :: proc() -> ^RenderCmd {
    cmd := new(__RenderCmd)
    cmd.scene = make_non_zeroed([dynamic]^IObject)
    cmd.sceneT = make_non_zeroed([dynamic]^IObject)
    for i in 0..<MAX_FRAMES_IN_FLIGHT {
        cmd.refresh[i] = false
        cmd.cmds[i] = make_non_zeroed([]vk.CommandBuffer, __swapImgCnt)
        allocInfo := vk.CommandBufferAllocateInfo{
            sType = vk.StructureType.COMMAND_BUFFER_ALLOCATE_INFO,
            commandPool = vkCmdPool,
            level = vk.CommandBufferLevel.PRIMARY,
            commandBufferCount = __swapImgCnt,
        }
        res := vk.AllocateCommandBuffers(vkDevice, &allocInfo, &cmd.cmds[i][0])
        if res != .SUCCESS do panicLog("res = vk.AllocateCommandBuffers(vkDevice, &allocInfo, &cmd.cmds[i][0]) : ", res)
    }
    cmd.objLock = sync.RW_Mutex{}

    sync.mutex_lock(&gRenderCmdMtx)
    non_zero_append(&gRenderCmd, cmd)
    sync.mutex_unlock(&gRenderCmdMtx)
    return (^RenderCmd)(cmd)
}

RenderCmd_Deinit :: proc(cmd: ^RenderCmd) {
    cmd_ :^__RenderCmd = (^__RenderCmd)(cmd)
    for i in 0..<MAX_FRAMES_IN_FLIGHT {
        vk.FreeCommandBuffers(vkDevice, vkCmdPool, __swapImgCnt, &cmd_.cmds[i][0])
        delete(cmd_.cmds[i])
    }
    delete(cmd_.scene)
    delete(cmd_.sceneT)

    sync.mutex_lock(&gRenderCmdMtx)
    for cmd, i in gRenderCmd {
        if cmd == cmd_ {
            ordered_remove(&gRenderCmd, i)
            if i == gMainRenderCmdIdx do gMainRenderCmdIdx = -1
            break
        }
    }
    sync.mutex_unlock(&gRenderCmdMtx)
    free(cmd)
}

RenderCmd_Show :: proc (_cmd: ^RenderCmd) -> bool {
    sync.mutex_lock(&gRenderCmdMtx)
    defer sync.mutex_unlock(&gRenderCmdMtx)
    for cmd, i in gRenderCmd {
        if cmd == (^__RenderCmd)(_cmd) {
            RenderCmd_Refresh(_cmd)
            gMainRenderCmdIdx = i
            return true
        }
    }
    return false
}

RenderCmd_AddObject :: proc(cmd: ^RenderCmd, obj: ^IObject) {
    cmd_ :^__RenderCmd = (^__RenderCmd)(cmd)
    sync.rw_mutex_shared_lock(&cmd_.objLock)
    defer sync.rw_mutex_shared_unlock(&cmd_.objLock)

    for objT,i in cmd_.scene {
        if objT == obj {
            ordered_remove(&cmd_.scene, i)
            break
        }
    }
    non_zero_append(&cmd_.scene, obj)
    RenderCmd_Refresh(cmd)
}

RenderCmd_AddObjects :: proc(cmd: ^RenderCmd, objs: ..^IObject) {
    cmd_ :^__RenderCmd = (^__RenderCmd)(cmd)
    sync.rw_mutex_shared_lock(&cmd_.objLock)
    defer sync.rw_mutex_shared_unlock(&cmd_.objLock)

    for objT,i in cmd_.scene {
        for obj in objs {
            if objT == obj {
                ordered_remove(&cmd_.scene, i)
                break
            }
        }
    }
    non_zero_append(&cmd_.scene, ..objs)
    if len(objs) > 0 do RenderCmd_Refresh(cmd)
}


RenderCmd_RemoveObject :: proc(cmd: ^RenderCmd, obj: ^IObject) {
    cmd_ :^__RenderCmd = (^__RenderCmd)(cmd)
    sync.rw_mutex_shared_lock(&cmd_.objLock)
    defer sync.rw_mutex_shared_unlock(&cmd_.objLock)

    for objT, i in cmd_.scene {
        if objT == obj {
            ordered_remove(&cmd_.scene, i)
            RenderCmd_Refresh(cmd)
            break
        }
    }
}

RenderCmd_RemoveAll :: proc(cmd: ^RenderCmd) {
    cmd_ :^__RenderCmd = (^__RenderCmd)(cmd)
    sync.rw_mutex_shared_lock(&cmd_.objLock)
    defer sync.rw_mutex_shared_unlock(&cmd_.objLock)
    objLen := len(cmd_.scene)
    clear(&cmd_.scene)
    if objLen > 0 do RenderCmd_Refresh(cmd)
}

RenderCmd_HasObject :: proc "contextless"(cmd: ^RenderCmd, obj: ^IObject) -> bool {
    cmd_ :^__RenderCmd = (^__RenderCmd)(cmd)
    sync.rw_mutex_shared_lock(&cmd_.objLock)
    defer sync.rw_mutex_shared_unlock(&cmd_.objLock)
    
    for objT in cmd_.scene {
        if objT == obj {
            return true
        }
    }
    return false
}

RenderCmd_GetObjectLen :: proc "contextless" (cmd: ^RenderCmd) -> int {
    cmd_ :^__RenderCmd = (^__RenderCmd)(cmd)
    sync.rw_mutex_shared_lock(&cmd_.objLock)
    defer sync.rw_mutex_shared_unlock(&cmd_.objLock)
    return len(cmd_.scene)
}

RenderCmd_GetObject :: proc "contextless" (cmd: ^RenderCmd, index: int) -> ^IObject {
    cmd_ :^__RenderCmd = (^__RenderCmd)(cmd)
    sync.rw_mutex_shared_lock(&cmd_.objLock)
    defer sync.rw_mutex_shared_unlock(&cmd_.objLock)
    return cmd_.scene[index]
}

RenderCmd_GetObjectIdx :: proc "contextless"(cmd: ^RenderCmd, obj: ^IObject) -> int {
    cmd_ :^__RenderCmd = (^__RenderCmd)(cmd)
    sync.rw_mutex_shared_lock(&cmd_.objLock)
    defer sync.rw_mutex_shared_unlock(&cmd_.objLock)
    for objT, i in cmd_.scene {
        if objT == obj {
            return i
        }
    }
    return -1
}

//! thread non safe
RenderCmd_GetObjects :: proc(cmd: ^RenderCmd) -> []^IObject {
    cmd_ :^__RenderCmd = (^__RenderCmd)(cmd)

    clear(&cmd_.sceneT)
    sync.rw_mutex_shared_lock(&cmd_.objLock)
    non_zero_append(&cmd_.sceneT, ..cmd_.scene[:])
    sync.rw_mutex_shared_unlock(&cmd_.objLock)
    return cmd_.sceneT[:]
}

@private RenderCmd_Refresh :: proc "contextless" (cmd: ^RenderCmd) {
    cmd_ :^__RenderCmd = (^__RenderCmd)(cmd)
    for &b in cmd_.refresh {
        b = true
    }
}

@private RenderCmd_RefreshAll :: proc "contextless" () {
    sync.mutex_lock(&gRenderCmdMtx)
    defer sync.mutex_unlock(&gRenderCmdMtx)
    for cmd in gRenderCmd {
        for &b in cmd.refresh {
            b = true
        }
    }
}

@private RenderCmd_Clean :: proc () {
    sync.mutex_lock(&gRenderCmdMtx)
    defer sync.mutex_unlock(&gRenderCmdMtx)
    delete(gRenderCmd)
}

@private RenderCmd_Create :: proc () {
    sync.mutex_lock(&gRenderCmdMtx)
    defer sync.mutex_unlock(&gRenderCmdMtx)
    gRenderCmd = make_non_zeroed([dynamic]^__RenderCmd)
}