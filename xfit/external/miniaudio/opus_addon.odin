package miniaudio

import "core:c"
import "core:c/libc"
import "core:mem"
import "../opusfile"
import "../ogg"
import "../opus"

foreign import lib {
	LIB,
}

libopus :: struct {
	ds:data_source_base,
	onRead:ma_read_proc,
	onSeek:ma_seek_proc,
	onTell:ma_tell_proc,
	pReadSeekTellUserData:rawptr,
    format:format,
	of:^opusfile.OggOpusFile,
}

libopus_ds_read :: proc "c" (pDataSource:^data_source, pFramesOut:rawptr, frameCount:u64, pFramesRead:^u64) -> result {
    return libopus_read_pcm_frames(auto_cast pDataSource, pFramesOut, frameCount, pFramesRead)
}

libopus_ds_seek :: proc "c" (pDataSource:^data_source, frameIndex:u64) -> result {
    return libopus_seek_to_pcm_frame(auto_cast pDataSource, frameIndex)
}

libopus_ds_get_data_format :: proc "c" (pDataSource:^data_source,
    pFormat:^format,
    pChannels:^u32,
    pSampleRate:^u32,
    pChannelMap:[^]channel,
    channelMapCap:c.size_t) -> result {
    return libopus_get_data_format(auto_cast pDataSource, pFormat, pChannels, pSampleRate, pChannelMap, channelMapCap)
}

libopus_ds_get_cursor :: proc "c" (pDataSource:^data_source, pCursor:^u64) -> result {
    return libopus_get_cursor_in_pcm_frames(auto_cast pDataSource, pCursor)
}

libopus_ds_get_length :: proc "c" (pDataSource:^data_source, pLength:^u64) -> result {
    return libopus_get_length_in_pcm_frames(auto_cast pDataSource, pLength)
}

g_ma_libopus_ds_vtable := data_source_vtable{
    onRead = libopus_ds_read,
    onSeek = libopus_ds_seek,
    onGetDataFormat = libopus_ds_get_data_format,
    onGetCursor = libopus_ds_get_cursor,
    onGetLength = libopus_ds_get_length,
    //?Rest are Not Set ..
}

@(private="file") libopus_of_callback__read :: proc "c" (pUserData:rawptr, pBufferOut:[^]byte, bytesToRead:c.int) -> c.int {
    pOpus:^libopus = auto_cast pUserData
    res : result
    bytesRead:c.size_t

    res = pOpus.onRead(pOpus.pReadSeekTellUserData, auto_cast pBufferOut, auto_cast bytesToRead, &bytesRead)
    if res != .SUCCESS {
        return -1
    }

    return auto_cast bytesRead
}

@(private="file") libopus_of_callback__seek :: proc "c" (pUserData:rawptr, offset:ogg.ogg_int64_t, whence:c.int) -> c.int {
    pOpus:^libopus = auto_cast pUserData
    res : result
    origin:seek_origin

    if whence == libc.SEEK_SET {
        origin = seek_origin.start
    } else if whence == libc.SEEK_END {
        origin = seek_origin.end
    } else {
        origin = seek_origin.current
    }

    res = pOpus.onSeek(pOpus.pReadSeekTellUserData, offset, origin)
    if res != .SUCCESS {
        return -1
    }

    return 0
}

@(private="file") libopus_of_callback__tell :: proc "c" (pUserData:rawptr) -> opus.opus_int64 {
    pOpus:^libopus = auto_cast pUserData
    res : result
    cursor:i64

	if pOpus.onTell == nil do return -1

    res = pOpus.onTell(pOpus.pReadSeekTellUserData, &cursor)
    if res != .SUCCESS {
        return -1
    }

    return auto_cast cursor
}

libopus_init_internal :: proc "contextless" (pConfig:^decoding_backend_config, pOpus:^libopus) -> result {
    if pOpus == nil {
        return .INVALID_ARGS
    }
    
    mem.zero(pOpus, size_of(libopus))//MA_ZERO_OBJECT(pOpus);
    pOpus.format = .f32

    if pConfig != nil && (pConfig.preferredFormat == .f32 || pConfig.preferredFormat == .s16) {
        pOpus.format = pConfig.preferredFormat
    } else {
        /* Getting here means something other than f32 and s16 was specified. Just leave this unset to use the default format. */
    }

    dataSourceConfig := data_source_config_init()
    dataSourceConfig.vtable = &g_ma_libopus_ds_vtable

    res := data_source_init(&dataSourceConfig, auto_cast &pOpus.ds)
    if res != .SUCCESS {
        return res /* Failed to initialize the base data source. */
    }
    return .SUCCESS
}

libopus_init :: proc "contextless" (onRead:ma_read_proc,
onSeek:ma_seek_proc,
onTell:ma_tell_proc,
pReadSeekTellUserData:rawptr,
pConfig:^decoding_backend_config,
_:^allocation_callbacks,//?pAllocationCallbacks
pOpus:^libopus) -> result {
    res := libopus_init_internal(pConfig, pOpus)
    if res != .SUCCESS do return res

    if onRead == nil || onSeek == nil {
        return .INVALID_ARGS  /* onRead and onSeek are mandatory. */
    }

    pOpus.onRead = onRead
    pOpus.onSeek = onSeek
    pOpus.onTell = onTell
    pOpus.pReadSeekTellUserData = pReadSeekTellUserData

    libopusCallbacks : opusfile.OpusFileCallbacks

    /* We can now initialize the Opus decoder. This must be done after we've set up the callbacks. */
    libopusCallbacks.read = libopus_of_callback__read
    libopusCallbacks.seek = libopus_of_callback__seek
    libopusCallbacks.close = nil
    libopusCallbacks.tell = libopus_of_callback__tell

	libopusResult : c.int
    pOpus.of = opusfile.op_open_callbacks(pOpus, &libopusCallbacks, nil, 0, &libopusResult)
    if libopusResult < 0 do return .INVALID_FILE

    return .SUCCESS
}

libopus_init_file :: proc "contextless" (pFilePath:cstring,
    pConfig:^decoding_backend_config,
    _:^allocation_callbacks,//?pAllocationCallbacks
    pOpus:^libopus) -> result {
    res := libopus_init_internal(pConfig, pOpus)
    if res != .SUCCESS do return res
	
	libopusResult : c.int
    pOpus.of = opusfile.op_open_file(pFilePath, &libopusResult)
    if pOpus.of == nil do return .INVALID_FILE

    return .SUCCESS
}

libopus_uninit :: proc "contextless" (pOpus:^libopus,_:^allocation_callbacks,/*?pAllocationCallbacks*/) {
    if pOpus == nil do return

    opusfile.op_free(pOpus.of)
    data_source_uninit(auto_cast &pOpus.ds)
}

libopus_read_pcm_frames :: proc "contextless" (pOpus:^libopus,
pFramesOut:rawptr,
frameCount:u64,
pFramesRead:^u64) -> result {
    if pFramesRead != nil do pFramesRead^ = 0

    if frameCount == 0 || pOpus == nil do return .INVALID_ARGS

    res :result = .SUCCESS
    totalFramesRead : u64 = 0
    format:format
    channels:u32

    libopus_get_data_format(pOpus, &format, &channels, nil, nil, 0)

    for totalFramesRead < frameCount {
        libopusResult : c.int
        framesToRead:c.int = 1024
        framesRemaining:u64 = frameCount - totalFramesRead

        if auto_cast framesToRead > framesRemaining do framesToRead = auto_cast framesRemaining

        if format == .f32 {
            libopusResult = opusfile.op_read_float(pOpus.of,
				auto_cast offset_pcm_frames_ptr(pFramesOut, totalFramesRead, format, channels),
				framesToRead * auto_cast channels,
			nil)
        } else {
            libopusResult = opusfile.op_read(pOpus.of,
				auto_cast offset_pcm_frames_ptr(pFramesOut, totalFramesRead, format, channels),
				framesToRead * auto_cast channels,
			nil)
        }

		if libopusResult < 0 {
			res = .ERROR
			break
		} else {
			totalFramesRead += auto_cast libopusResult

			if libopusResult == 0 {
				res = .AT_END
				break
			}
		}
    }

    if pFramesRead != nil do pFramesRead^ = totalFramesRead

    if res == .SUCCESS && totalFramesRead == 0 do res = .AT_END

    return res
}

libopus_seek_to_pcm_frame :: proc "contextless" (pOpus: ^libopus, frameIndex: u64) -> result {
    if pOpus == nil do return .INVALID_ARGS

    libopusResult := opusfile.op_pcm_seek(pOpus.of, auto_cast frameIndex)
    if libopusResult != 0 {
        if libopusResult == opusfile.OP_ENOSEEK {
            return .INVALID_OPERATION
        } else if libopusResult == opusfile.OP_EINVAL {
            return .INVALID_ARGS
        } else {
            return .ERROR
        }
    }

    return .SUCCESS
}

libopus_get_data_format :: proc "contextless" (
    pOpus: ^libopus,
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
    if pOpus == nil do return .INVALID_OPERATION
    if pFormat != nil do pFormat^ = pOpus.format

    channels := opusfile.op_channel_count(pOpus.of, -1)

    if pChannels != nil do pChannels^ = auto_cast channels
    if pSampleRate != nil do pSampleRate^ = 48000
    if pChannelMap != nil do channel_map_init_standard(.vorbis, pChannelMap, channelMapCap, auto_cast channels)

    return .SUCCESS
}

libopus_get_cursor_in_pcm_frames :: proc "contextless" (pOpus: ^libopus, pCursor: ^u64) -> result {
    if pCursor == nil do return .INVALID_ARGS
    pCursor^ = 0

    if pOpus == nil do return .INVALID_ARGS

    offset := opusfile.op_pcm_tell(pOpus.of)
    if offset < 0 do return .INVALID_FILE

    pCursor^ = auto_cast offset
    
    return .SUCCESS
}

libopus_get_length_in_pcm_frames :: proc "contextless" (pOpus: ^libopus, pLength: ^u64) -> result {
    if pLength == nil do return .INVALID_ARGS
    pLength^ = 0 /* Safety. */

    if pOpus == nil do return .INVALID_ARGS

    length := opusfile.op_pcm_total(pOpus.of, -1)
	if length < 0 do return .ERROR

	pLength^ = u64(length)

    return .SUCCESS
}

@(private="file") decoding_backend_init__libopus :: proc "c" (_:rawptr,//pUserData
onRead:ma_read_proc,
onSeek:ma_seek_proc,
onTell:ma_tell_proc,
pReadSeekTellUserData:rawptr,
pConfig:^decoding_backend_config,
pAllocationCallbacks:^allocation_callbacks,
ppBackend:^^data_source) -> result {
    pOpus :^libopus = auto_cast malloc(size_of(libopus), pAllocationCallbacks)
    if pOpus == nil do return .OUT_OF_MEMORY

    result := libopus_init(onRead, onSeek, onTell, pReadSeekTellUserData, pConfig, pAllocationCallbacks, pOpus)
    if result != .SUCCESS {
        free(pOpus, pAllocationCallbacks)
        return result
    }

    ppBackend^ = auto_cast pOpus
    return .SUCCESS
}

@(private="file") decoding_backend_uninit__libopus :: proc "c" (
    _: rawptr,//pUserData
    pBackend: ^data_source,
    pAllocationCallbacks: ^allocation_callbacks,
) {
    pOpus :^libopus = auto_cast pBackend
    libopus_uninit(pOpus, pAllocationCallbacks)
    free(pOpus, pAllocationCallbacks)
}

@(private="file") decoding_backend_get_channel_map__libopus :: proc "c" (
    _: rawptr,//pUserData
    pBackend: ^data_source,
    pChannelMap: [^]channel,
    channelMapCap: c.size_t,
) -> result {
    pOpus :^libopus = auto_cast pBackend
    return libopus_get_data_format(pOpus, nil, nil, nil, pChannelMap, channelMapCap)
}

@(private="file") decoding_backend_init_file__libopus :: proc "c" (_:rawptr,//pUserData
    pFilePath: cstring,
    pConfig: ^decoding_backend_config,
    pAllocationCallbacks: ^allocation_callbacks,
    ppBackend: ^^data_source) -> result {

    pOpus :^libopus = auto_cast malloc(size_of(libopus), pAllocationCallbacks)
    if pOpus == nil do return .OUT_OF_MEMORY

    result := libopus_init_file(pFilePath, pConfig, pAllocationCallbacks, pOpus)
    if result != .SUCCESS {
        free(pOpus, pAllocationCallbacks)
        return result
    }

    ppBackend^ = auto_cast pOpus
    return .SUCCESS
}


g_decoding_backend_vtable_libopus := decoding_backend_vtable{
    onInit = decoding_backend_init__libopus,
    onInitFile = decoding_backend_init_file__libopus,
    onInitFileW = nil,
    onInitMemory = nil,
    onUninit = decoding_backend_uninit__libopus,
}
