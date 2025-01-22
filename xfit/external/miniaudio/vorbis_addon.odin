package miniaudio

import "core:c"
import "core:c/libc"
import "core:mem"
import "../vorbisfile"
import "../vorbis"
import "../ogg"

foreign import lib {
	LIB,
}


libvorbis :: struct {
	ds:data_source_base,
	onRead:ma_read_proc,
	onSeek:ma_seek_proc,
	onTell:ma_tell_proc,
	pReadSeekTellUserData:rawptr,
    format:format,
	vf:vorbisfile.OggVorbis_File,
}

libvorbis_ds_read :: proc "c" (pDataSource:^data_source, pFramesOut:rawptr, frameCount:u64, pFramesRead:^u64) -> result {
    return libvorbis_read_pcm_frames(auto_cast pDataSource, pFramesOut, frameCount, pFramesRead)
}

libvorbis_ds_seek :: proc "c" (pDataSource:^data_source, frameIndex:u64) -> result {
    return libvorbis_seek_to_pcm_frame(auto_cast pDataSource, frameIndex)
}

libvorbis_ds_get_data_format :: proc "c" (pDataSource:^data_source,
    pFormat:^format,
    pChannels:^u32,
    pSampleRate:^u32,
    pChannelMap:[^]channel,
    channelMapCap:c.size_t) -> result {
    return libvorbis_get_data_format(auto_cast pDataSource, pFormat, pChannels, pSampleRate, pChannelMap, channelMapCap)
}

libvorbis_ds_get_cursor :: proc "c" (pDataSource:^data_source, pCursor:^u64) -> result {
    return libvorbis_get_cursor_in_pcm_frames(auto_cast pDataSource, pCursor)
}

libvorbis_ds_get_length :: proc "c" (pDataSource:^data_source, pLength:^u64) -> result {
    return libvorbis_get_length_in_pcm_frames(auto_cast pDataSource, pLength)
}

g_ma_libvorbis_ds_vtable := data_source_vtable{
    onRead = libvorbis_ds_read,
    onSeek = libvorbis_ds_seek,
    onGetDataFormat = libvorbis_ds_get_data_format,
    onGetCursor = libvorbis_ds_get_cursor,
    onGetLength = libvorbis_ds_get_length,
    //?Rest are Not Set ..
}

@(private="file") libvorbis_vf_callback__read :: proc "c" (pBufferOut:rawptr, size:c.size_t, count:c.size_t, pUserData:rawptr) -> c.size_t {
    pVorbis:^libvorbis = auto_cast pUserData
    res : result
    bytesToRead:c.size_t
    bytesRead:c.size_t

    /* For consistency with fread(). If `size` of `count` is 0, return 0 immediately without changing anything. */
    if size == 0 || count == 0 {
        return 0
    }

    bytesToRead = size * count
    res = pVorbis.onRead(pVorbis.pReadSeekTellUserData, pBufferOut, bytesToRead, &bytesRead)
    if res != .SUCCESS {
         /* Not entirely sure what to return here. What if an error occurs, but some data was read and bytesRead is > 0? */
        return 0
    }

    return bytesRead / size
}

@(private="file") libvorbis_vf_callback__seek :: proc "c" (pUserData:rawptr, offset:ogg.ogg_int64_t, whence:c.int) -> c.int{
    pVorbis:^libvorbis = auto_cast pUserData
    res : result
    origin:seek_origin

    if whence == libc.SEEK_SET {
        origin = seek_origin.start
    } else if whence == libc.SEEK_END {
        origin = seek_origin.end
    } else {
        origin = seek_origin.current
    }

    res = pVorbis.onSeek(pVorbis.pReadSeekTellUserData, offset, origin)
    if res != .SUCCESS {
        return -1
    }

    return 0
}

@(private="file") libvorbis_vf_callback__tell :: proc "c" (pUserData:rawptr) -> c.long {
    pVorbis:^libvorbis = auto_cast pUserData
    res : result
    cursor:i64

    if pVorbis.onTell == nil do return -1

    res = pVorbis.onTell(pVorbis.pReadSeekTellUserData, &cursor)
    if res != .SUCCESS {
        return -1
    }

    return auto_cast cursor
}

libvorbis_init_internal :: proc "contextless" (pConfig:^decoding_backend_config, pVorbis:^libvorbis) -> result {
    if pVorbis == nil {
        return .INVALID_ARGS
    }
    
    mem.zero(pVorbis, size_of(libvorbis))//MA_ZERO_OBJECT(pVorbis);
    pVorbis.format = .f32

    if pConfig != nil && (pConfig.preferredFormat == .f32 || pConfig.preferredFormat == .s16) {
        pVorbis.format = pConfig.preferredFormat
    } else {
        /* Getting here means something other than f32 and s16 was specified. Just leave this unset to use the default format. */
    }

    dataSourceConfig := data_source_config_init()
    dataSourceConfig.vtable = &g_ma_libvorbis_ds_vtable

    res := data_source_init(&dataSourceConfig, auto_cast &pVorbis.ds)
    if res != .SUCCESS {
        return res /* Failed to initialize the base data source. */
    }
    return .SUCCESS
}

libvorbis_init :: proc "contextless" (onRead:ma_read_proc,
onSeek:ma_seek_proc,
onTell:ma_tell_proc,
pReadSeekTellUserData:rawptr,
pConfig:^decoding_backend_config,
_:^allocation_callbacks,//?pAllocationCallbacks
pVorbis:^libvorbis) -> result {
    res := libvorbis_init_internal(pConfig, pVorbis)
    if res != .SUCCESS do return res

    if onRead == nil || onSeek == nil {
        return .INVALID_ARGS  /* onRead and onSeek are mandatory. */
    }

    pVorbis.onRead = onRead
    pVorbis.onSeek = onSeek
    pVorbis.onTell = onTell
    pVorbis.pReadSeekTellUserData = pReadSeekTellUserData

    libvorbisCallbacks : vorbisfile.ov_callbacks

    /* We can now initialize the vorbis decoder. This must be done after we've set up the callbacks. */
    libvorbisCallbacks.read_func = libvorbis_vf_callback__read
    libvorbisCallbacks.seek_func = libvorbis_vf_callback__seek
    libvorbisCallbacks.close_func = nil
    libvorbisCallbacks.tell_func = libvorbis_vf_callback__tell

    libvorbisResult := vorbisfile.ov_open_callbacks(pVorbis, &pVorbis.vf, nil, 0, libvorbisCallbacks)
    if libvorbisResult < 0 do return .INVALID_FILE

    return .SUCCESS
}

libvorbis_init_file :: proc "contextless" (pFilePath:cstring,
    pConfig:^decoding_backend_config,
    _:^allocation_callbacks,//?pAllocationCallbacks
    pVorbis:^libvorbis) -> result {
    res := libvorbis_init_internal(pConfig, pVorbis)
    if res != .SUCCESS do return res

    libvorbisResult := vorbisfile.ov_fopen(pFilePath, &pVorbis.vf)
    if libvorbisResult < 0 do return .INVALID_FILE

    return .SUCCESS
}

libvorbis_uninit :: proc "contextless" (pVorbis:^libvorbis,_:^allocation_callbacks,/*?pAllocationCallbacks*/) {
    if pVorbis == nil do return

    vorbisfile.ov_clear(&pVorbis.vf)
    data_source_uninit(auto_cast &pVorbis.ds)
}

libvorbis_read_pcm_frames :: proc "contextless" (pVorbis:^libvorbis,
pFramesOut:rawptr,
frameCount:u64,
pFramesRead:^u64) -> result {
    if pFramesRead != nil do pFramesRead^ = 0

    if frameCount == 0 || pVorbis == nil do return .INVALID_ARGS

    res :result = .SUCCESS
    totalFramesRead : u64 = 0
    format:format
    channels:u32

    libvorbis_get_data_format(pVorbis, &format, &channels, nil, nil, 0)

    for totalFramesRead < frameCount {
        libvorbisResult : c.long
        framesToRead:c.int = 1024
        framesRemaining:u64 = frameCount - totalFramesRead

        if auto_cast framesToRead > framesRemaining do framesToRead = auto_cast framesRemaining

        if format == .f32 {
            ppFramesF32:^^c.float

            libvorbisResult = vorbisfile.ov_read_float(&pVorbis.vf, &ppFramesF32, framesToRead, nil)
            if libvorbisResult < 0 {
                res = .ERROR /* Error while decoding. */
                break
            } else {
                /* Frames need to be interleaved. */
                interleave_pcm_frames(format,
                    channels,
                    auto_cast libvorbisResult,
                    auto_cast ppFramesF32,
                    offset_pcm_frames_ptr(pFramesOut, totalFramesRead, format, channels))
                
                totalFramesRead += auto_cast libvorbisResult

                if libvorbisResult == 0 {
                    res = .AT_END
                    break
                }
            }
        } else {
            libvorbisResult = vorbisfile.ov_read(&pVorbis.vf, 
                auto_cast offset_pcm_frames_ptr(pFramesOut, totalFramesRead, format, channels),
            framesToRead * c.int(get_bytes_per_frame(format, channels)), 0, 2, 1, nil)

            if libvorbisResult < 0 {
                res = .ERROR /* Error while decoding. */
                break
            } else {
                /* Conveniently, there's no need to interleaving when using ov_read(). I'm not sure why ov_read_float() is different in that regard... */
                totalFramesRead += u64(libvorbisResult) / u64(get_bytes_per_frame(format, channels))

                if libvorbisResult == 0 {
                    res = .AT_END
                    break
                }
            }
        }
    }

    if pFramesRead != nil do pFramesRead^ = totalFramesRead

    if res == .SUCCESS && totalFramesRead == 0 do res = .AT_END

    return res
}

libvorbis_seek_to_pcm_frame :: proc "contextless" (pVorbis: ^libvorbis, frameIndex: u64) -> result {
    if pVorbis == nil do return .INVALID_ARGS

    libvorbisResult := vorbisfile.ov_pcm_seek(&pVorbis.vf, auto_cast frameIndex)
    if libvorbisResult != 0 {
        if libvorbisResult == vorbis.OV_ENOSEEK {
            return .INVALID_OPERATION
        } else if libvorbisResult == vorbis.OV_EINVAL {
            return .INVALID_ARGS
        } else {
            return .ERROR
        }
    }

    return .SUCCESS
}

libvorbis_get_data_format :: proc "contextless" (
    pVorbis: ^libvorbis,
    pFormat: ^format,
    pChannels: ^u32,
    pSampleRate: ^u32,
    pChannelMap: [^]channel,
    channelMapCap: c.size_t,
) -> result {
    /* Defaults for safety. */
    if pFormat != nil do pFormat^ = .unknown
    if pChannels != nil do pChannels^ = 0
    if pSampleRate != nil do pSampleRate^ = 0
    if pChannelMap != nil do mem.zero(pChannelMap, int(size_of(channel) * channelMapCap))
    if pVorbis == nil do return .INVALID_OPERATION
    if pFormat != nil do pFormat^ = pVorbis.format

    pInfo := vorbisfile.ov_info(&pVorbis.vf, 0)
    if pInfo == nil do return .INVALID_OPERATION

    if pChannels != nil do pChannels^ = auto_cast pInfo.channels
    if pSampleRate != nil do pSampleRate^ = auto_cast pInfo.rate
    if pChannelMap != nil do channel_map_init_standard(.vorbis, pChannelMap, channelMapCap, auto_cast pInfo.channels)

    return .SUCCESS
}

libvorbis_get_cursor_in_pcm_frames :: proc "contextless" (pVorbis: ^libvorbis, pCursor: ^u64) -> result {
    if pCursor == nil do return .INVALID_ARGS
    pCursor^ = 0

    if pVorbis == nil do return .INVALID_ARGS

    offset := vorbisfile.ov_pcm_tell(&pVorbis.vf)
    if offset < 0 do return .INVALID_FILE

    pCursor^ = auto_cast offset
    
    return .SUCCESS
}

libvorbis_get_length_in_pcm_frames :: proc "contextless" (pVorbis: ^libvorbis, pLength: ^u64) -> result {
    if pLength == nil do return .INVALID_ARGS
    pLength^ = 0 /* Safety. */

    if pVorbis == nil do return .INVALID_ARGS

    //TODO
    /* I don't know how to reliably retrieve the length in frames using libvorbis, so returning 0 for now. */
    //pLength^ = 0

    return .SUCCESS
}

@(private="file") decoding_backend_init__libvorbis :: proc "c" (_:rawptr,//pUserData
onRead:ma_read_proc,
onSeek:ma_seek_proc,
onTell:ma_tell_proc,
pReadSeekTellUserData:rawptr,
pConfig:^decoding_backend_config,
pAllocationCallbacks:^allocation_callbacks,
ppBackend:^^data_source) -> result {
    pVorbis :^libvorbis = auto_cast malloc(size_of(libvorbis), pAllocationCallbacks)
    if pVorbis == nil do return .OUT_OF_MEMORY

    result := libvorbis_init(onRead, onSeek, onTell, pReadSeekTellUserData, pConfig, pAllocationCallbacks, pVorbis)
    if result != .SUCCESS {
        free(pVorbis, pAllocationCallbacks)
        return result
    }

    ppBackend^ = auto_cast pVorbis
    return .SUCCESS
}

@(private="file") decoding_backend_uninit__libvorbis :: proc "c" (
    _: rawptr,//pUserData
    pBackend: ^data_source,
    pAllocationCallbacks: ^allocation_callbacks,
) {
    pVorbis :^libvorbis = auto_cast pBackend
    libvorbis_uninit(pVorbis, pAllocationCallbacks)
    free(pVorbis, pAllocationCallbacks)
}

@(private="file") decoding_backend_get_channel_map__libvorbis :: proc "c" (
    _: rawptr,//pUserData
    pBackend: ^data_source,
    pChannelMap: [^]channel,
    channelMapCap: c.size_t,
) -> result {
    pVorbis :^libvorbis = auto_cast pBackend
    return libvorbis_get_data_format(pVorbis, nil, nil, nil, pChannelMap, channelMapCap)
}

@(private="file") decoding_backend_init_file__libvorbis :: proc "c" (_:rawptr,//pUserData
    pFilePath: cstring,
    pConfig: ^decoding_backend_config,
    pAllocationCallbacks: ^allocation_callbacks,
    ppBackend: ^^data_source) -> result {

    pVorbis :^libvorbis = auto_cast malloc(size_of(libvorbis), pAllocationCallbacks)
    if pVorbis == nil do return .OUT_OF_MEMORY

    result := libvorbis_init_file(pFilePath, pConfig, pAllocationCallbacks, pVorbis)
    if result != .SUCCESS {
        free(pVorbis, pAllocationCallbacks)
        return result
    }

    ppBackend^ = auto_cast pVorbis
    return .SUCCESS
}


g_decoding_backend_vtable_libvorbis := decoding_backend_vtable{
    onInit = decoding_backend_init__libvorbis,
    onInitFile = decoding_backend_init_file__libvorbis,
    onInitFileW = nil,
    onInitMemory = nil,
    onUninit = decoding_backend_uninit__libvorbis,
}
