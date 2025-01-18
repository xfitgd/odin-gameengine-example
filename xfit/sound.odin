package xfit

import "miniaudio"
import "core:sync"
import "core:thread"
import "base:intrinsics"
import "base:runtime"
import "core:c/libc"

@(private = "file") Sound_private :: struct #packed {
    __miniaudio_sound:miniaudio.sound,
    __miniaudio_audioBuf:miniaudio.audio_buffer
}

SoundError :: miniaudio.result

Sound :: struct {
    src:^SoundSrc,
   __private : Sound_private,
}

SoundFormat::miniaudio.format

SoundSrc :: struct {
    outData:[]byte,
    format:SoundFormat,
    channels:u32,
    sampleRate:u32,
    sizeInFrames:u64,
}

@(private = "file") miniaudio_engine:miniaudio.engine

@(private = "file") miniaudio_pCustomBackendVTables:[2]^miniaudio.decoding_backend_vtable
@(private = "file") miniaudio_resourceManager:miniaudio.resource_manager

@(private = "file") gSoundsMtx:sync.Mutex
@(private = "file") gEndSoundsMtx:sync.Mutex
@(private = "file") gSema:sync.Sema
@(private = "file") gThread:^thread.Thread

@(private = "file") started:bool = false

@(private = "file") gEndSounds:[dynamic]^Sound
@(private = "file") gSounds:map[^Sound]^Sound

@private soundStart :: proc() {
    gSounds = make(map[^Sound]^Sound)
    gEndSounds = make([dynamic]^Sound)

    resourceManagerConfig := miniaudio.resource_manager_config_init()
    miniaudio_pCustomBackendVTables[0] = &miniaudio.g_decoding_backend_vtable_libopus
    miniaudio_pCustomBackendVTables[1] = &miniaudio.g_decoding_backend_vtable_libvorbis

    resourceManagerConfig.ppCustomDecodingBackendVTables = auto_cast &miniaudio_pCustomBackendVTables[0]
    resourceManagerConfig.customDecodingBackendCount = 2
    resourceManagerConfig.pCustomDecodingBackendUserData = nil

    res := miniaudio.resource_manager_init(&resourceManagerConfig, &miniaudio_resourceManager)
    if res != .SUCCESS do panicLog("miniaudio.resource_manager_init : ", res)

    engineConfig := miniaudio.engine_config_init()
    engineConfig.pResourceManager = &miniaudio_resourceManager
    
    res = miniaudio.engine_init(&engineConfig, &miniaudio_engine)
    if res != .SUCCESS do panicLog("miniaudio.engine_init : ", res)

    started = true
    gThread = thread.create(Callback)
    thread.start(gThread)
}

@(private = "file") Callback :: proc(_: ^thread.Thread) {
    for intrinsics.atomic_load_explicit(&started, .Acquire) {
        sync.sema_wait(&gSema)
        if !intrinsics.atomic_load_explicit(&started, .Acquire) do break

        this : ^Sound = nil
        sync.mutex_lock(&gEndSoundsMtx)
        if len(gEndSounds) > 0 {
            this = pop(&gEndSounds)
        }
        sync.mutex_unlock(&gEndSoundsMtx)

        if this != nil {
            sync.mutex_lock(&gSoundsMtx)
            defer sync.mutex_unlock(&gSoundsMtx)
            if !miniaudio.sound_is_looping(&this.__private.__miniaudio_sound) {
                deinit2(this)
            }
        }
    }
}

Sound_Deinit :: proc(self:^Sound) {
    sync.mutex_lock(&gSoundsMtx)
    defer sync.mutex_unlock(&gSoundsMtx)
    deinit2(self)
}
@(private = "file") deinit2 :: proc(self:^Sound) {
    //TODO if self.__private.__miniaudio_sound == nil do return
    miniaudio.sound_uninit(&self.__private.__miniaudio_sound)
    miniaudio.audio_buffer_uninit(&self.__private.__miniaudio_audioBuf)
    free(self)
    if intrinsics.atomic_load_explicit(&started, .Acquire) do delete_key(&gSounds, self)
}

@(private = "file") EndCallback :: proc "c" (userdata:rawptr, _:^miniaudio.sound) {
    self := cast(^Sound)(userdata)

    context = runtime.default_context()
    sync.mutex_lock(&gEndSoundsMtx)
    append(&gEndSounds, self)
    sync.mutex_unlock(&gEndSoundsMtx)
    sync.sema_post(&gSema)
}

@(private) soundDestroy :: proc() {
    if !intrinsics.atomic_load_explicit(&started, .Acquire) do panicLog("sound not started. can't destory")
    intrinsics.atomic_store_explicit(&started, false, .Release)
    sync.sema_post(&gSema)
    thread.join(gThread)

    miniaudio.engine_uninit(&miniaudio_engine)

    sync.mutex_lock(&gSoundsMtx)
    for key in gSounds {
        deinit2(key)
    }
    sync.mutex_unlock(&gSoundsMtx)

    delete(gEndSounds)
    delete(gSounds)
}

SoundSrc_Deinit :: proc(self:^SoundSrc) {
    sync.mutex_lock(&gSoundsMtx)
    for key in gSounds {
        if key.src == self do deinit2(key)
    }
    sync.mutex_unlock(&gSoundsMtx)
    libc.free(auto_cast &self.outData[0])
    free(self)
}

SoundSrc_PlaySoundMemory :: proc(self:^SoundSrc, volume:f32, loop:bool) -> (snd: ^Sound, err: SoundError) {
    if !intrinsics.atomic_load_explicit(&started, .Acquire) do panicLog("SoundSrc_PlaySoundMemory : sound not started.")

    err = .SUCCESS
    snd = new(Sound)
    defer if err != .SUCCESS do free(snd)
    snd^ = Sound{ src = self }

    audioBufConfig :miniaudio.audio_buffer_config = {
        channels = self.channels,
        format = self.format,
        sampleRate = self.sampleRate,
        pData = auto_cast &self.outData[0],
        sizeInFrames = self.sizeInFrames,
    }
    err = miniaudio.audio_buffer_init(&audioBufConfig, &snd.__private.__miniaudio_audioBuf)
    if err != .SUCCESS do return

    sndConfig := miniaudio.sound_config_init_2(&miniaudio_engine)
    sndConfig.endCallback = EndCallback
    sndConfig.pEndCallbackUserData = auto_cast snd
    sndConfig.pDataSource = auto_cast &snd.__private.__miniaudio_audioBuf
    sndConfig.isLooping = auto_cast loop

    err = miniaudio.sound_init_ex(&miniaudio_engine, &sndConfig, &snd.__private.__miniaudio_sound)
    if err != .SUCCESS do return

    miniaudio.sound_set_volume(&snd.__private.__miniaudio_sound, volume)

    err = miniaudio.sound_start(&snd.__private.__miniaudio_sound)
    if err != .SUCCESS {
        miniaudio.sound_uninit(&snd.__private.__miniaudio_sound)
        return
    }

    sync.mutex_lock(&gSoundsMtx)
    map_insert(&gSounds, snd, snd)
    sync.mutex_unlock(&gSoundsMtx)
    return
}