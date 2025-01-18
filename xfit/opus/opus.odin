package opus

import "../xlibrary"
import "core:c"

LIBOPUS :: xlibrary.LIBPATH + "/opus/libopus" + xlibrary.ARCH_end
foreign import lib {
	LIBOPUS,
}

// opus_types.h


opus_int :: c.int
opus_int32 :: c.int
opus_int64 :: c.int64_t
opus_int8 :: c.char
opus_int16 :: c.int16_t

opus_uint :: c.uint
opus_uint32 :: c.uint
opus_uint64 :: c.uint64_t
opus_uint8 :: c.uchar
opus_uint16 :: c.uint16_t

// opus_types.h end

// opus_define.h


/** No error @hideinitializer*/
OPUS_OK :: 0
/** One or more invalid/out of range arguments @hideinitializer*/
OPUS_BAD_ARG :: -1
/** Not enough bytes allocated in the buffer @hideinitializer*/
OPUS_BUFFER_TOO_SMALL :: -2
/** An internal error was detected @hideinitializer*/
OPUS_INTERNAL_ERROR :: -3
/** The compressed data passed is corrupted @hideinitializer*/
OPUS_INVALID_PACKET :: -4
/** Invalid/unsupported request number @hideinitializer*/
OPUS_UNIMPLEMENTED :: -5
/** An encoder or decoder structure is invalid or already freed @hideinitializer*/
OPUS_INVALID_STATE :: -6
/** Memory allocation has failed @hideinitializer*/
OPUS_ALLOC_FAIL :: -7


/** These are the actual Encoder CTL ID numbers.
  * They should not be used directly by applications.
  * In general, SETs should be even and GETs should be odd.*/


OPUS_SET_APPLICATION_REQUEST    ::     4000
OPUS_GET_APPLICATION_REQUEST    ::     4001
OPUS_SET_BITRATE_REQUEST         ::    4002
OPUS_GET_BITRATE_REQUEST          ::   4003
OPUS_SET_MAX_BANDWIDTH_REQUEST   ::    4004
OPUS_GET_MAX_BANDWIDTH_REQUEST    ::   4005
OPUS_SET_VBR_REQUEST           ::      4006
OPUS_GET_VBR_REQUEST            ::     4007
OPUS_SET_BANDWIDTH_REQUEST      ::     4008
OPUS_GET_BANDWIDTH_REQUEST       ::    4009
OPUS_SET_COMPLEXITY_REQUEST       ::   4010
OPUS_GET_COMPLEXITY_REQUEST      ::    4011
OPUS_SET_INBAND_FEC_REQUEST      ::    4012
OPUS_GET_INBAND_FEC_REQUEST        ::  4013
OPUS_SET_PACKET_LOSS_PERC_REQUEST  ::  4014
OPUS_GET_PACKET_LOSS_PERC_REQUEST ::   4015
OPUS_SET_DTX_REQUEST               ::  4016
OPUS_GET_DTX_REQUEST              ::   4017
OPUS_SET_VBR_CONSTRAINT_REQUEST   ::   4020
OPUS_GET_VBR_CONSTRAINT_REQUEST    ::  4021
OPUS_SET_FORCE_CHANNELS_REQUEST   ::   4022
OPUS_GET_FORCE_CHANNELS_REQUEST   ::   4023
OPUS_SET_SIGNAL_REQUEST          ::    4024
OPUS_GET_SIGNAL_REQUEST          ::    4025
OPUS_GET_LOOKAHEAD_REQUEST       ::    4027
/*OPUS_RESET_STATE :: 4028 */


OPUS_GET_SAMPLE_RATE_REQUEST      ::   4029
OPUS_GET_FINAL_RANGE_REQUEST      ::   4031
OPUS_GET_PITCH_REQUEST           ::    4033
OPUS_SET_GAIN_REQUEST          ::      4034
/* Should have been 4035 */
OPUS_GET_GAIN_REQUEST         ::       4045 
OPUS_SET_LSB_DEPTH_REQUEST      ::     4036
OPUS_GET_LSB_DEPTH_REQUEST      ::     4037
OPUS_GET_LAST_PACKET_DURATION_REQUEST  :: 4039
OPUS_SET_EXPERT_FRAME_DURATION_REQUEST  :: 4040
OPUS_GET_EXPERT_FRAME_DURATION_REQUEST  :: 4041
OPUS_SET_PREDICTION_DISABLED_REQUEST  :: 4042
OPUS_GET_PREDICTION_DISABLED_REQUEST  :: 4043
/* Don't use 4045, it's already taken by OPUS_GET_GAIN_REQUEST */


OPUS_SET_PHASE_INVERSION_DISABLED_REQUEST  :: 4046
OPUS_GET_PHASE_INVERSION_DISABLED_REQUEST  :: 4047
OPUS_GET_IN_DTX_REQUEST           ::    4049
OPUS_SET_DRED_DURATION_REQUEST  :: 4050
OPUS_GET_DRED_DURATION_REQUEST  :: 4051
OPUS_SET_DNN_BLOB_REQUEST  :: 4052
/*OPUS_GET_DNN_BLOB_REQUEST   :: 4053 */


/** @defgroup opus_ctlvalues Pre-defined values for CTL interface
  * @see opus_genericctls, opus_encoderctls
  * @{
  */
/* Values for the various encoder CTLs */
OPUS_AUTO           ::                -1000 /**<Auto/default setting @hideinitializer*/
OPUS_BITRATE_MAX    ::                   -1 /**<Maximum bitrate @hideinitializer*/

/** Best for most VoIP/videoconference applications where listening quality and intelligibility matter most
 * @hideinitializer */
OPUS_APPLICATION_VOIP   ::             2048
/** Best for broadcast/high-fidelity application where the decoded audio should be as close as possible to the input
 * @hideinitializer */
OPUS_APPLICATION_AUDIO   ::            2049
/** Only use when lowest-achievable latency is what matters most. Voice-optimized modes cannot be used.
 * @hideinitializer */
OPUS_APPLICATION_RESTRICTED_LOWDELAY :: 2051

/**< Signal being encoded is voice */
OPUS_SIGNAL_VOICE        ::            3001
/**< Signal being encoded is music */
OPUS_SIGNAL_MUSIC        ::            3002
/**< 4 kHz bandpass @hideinitializer*/
OPUS_BANDWIDTH_NARROWBAND       ::     1101
/**< 6 kHz bandpass @hideinitializer*/
OPUS_BANDWIDTH_MEDIUMBAND       ::     1102
/**< 8 kHz bandpass @hideinitializer*/
OPUS_BANDWIDTH_WIDEBAND         ::     1103
/**<12 kHz bandpass @hideinitializer*/
OPUS_BANDWIDTH_SUPERWIDEBAND    ::     1104
/**<20 kHz bandpass @hideinitializer*/
OPUS_BANDWIDTH_FULLBAND         ::     1105 

/**< Select frame size from the argument (default) */
OPUS_FRAMESIZE_ARG :: 5000
/**< Use 2.5 ms frames */
OPUS_FRAMESIZE_2_5_MS :: 5001
/**< Use 5 ms frames */
OPUS_FRAMESIZE_5_MS :: 5002
/**< Use 10 ms frames */
OPUS_FRAMESIZE_10_MS :: 5003
/**< Use 20 ms frames */
OPUS_FRAMESIZE_20_MS :: 5004
/**< Use 40 ms frames */
OPUS_FRAMESIZE_40_MS :: 5005
/**< Use 60 ms frames */
OPUS_FRAMESIZE_60_MS :: 5006
/**< Use 80 ms frames */
OPUS_FRAMESIZE_80_MS :: 5007
/**< Use 100 ms frames */
OPUS_FRAMESIZE_100_MS :: 5008
/**< Use 120 ms frames */
OPUS_FRAMESIZE_120_MS :: 5009


/** Resets the codec state to be equivalent to a freshly initialized state.
  * This should be called when switching streams in order to prevent
  * the back to back decoding from giving different results from
  * one at a time decoding.
  * @hideinitializer */
OPUS_RESET_STATE :: 4028


@(default_calling_convention="c")
foreign lib {
    opus_strerror :: proc (error: c.int) -> cstring ---
    opus_get_version_string :: proc () -> cstring ---
}

// opus_define.h end


// opus.h


/** Opus encoder state.
  * This contains the complete state of an Opus encoder.
  * It is position independent and can be freely copied.
  * @see opus_encoder_create,opus_encoder_init
  */
OpusEncoder :: struct {

}

/** Opus decoder state.
  * This contains the complete state of an Opus decoder.
  * It is position independent and can be freely copied.
  * @see opus_decoder_create,opus_decoder_init
  */
OpusDecoder :: struct {

}

/** Opus DRED decoder.
  * This contains the complete state of an Opus DRED decoder.
  * It is position independent and can be freely copied.
  * @see opus_dred_decoder_create,opus_dred_decoder_init
  */
OpusDREDDecoder :: struct {

}

/** Opus DRED state.
  * This contains the complete state of an Opus DRED packet.
  * It is position independent and can be freely copied.
  * @see opus_dred_create,opus_dred_init
  */
OpusDRED :: struct {

}
  


// opus.h end


@(default_calling_convention="c")
foreign lib {
    // opus_define.h
    opus_strerror :: proc (error: c.int) -> cstring ---
    opus_get_version_string :: proc () -> cstring ---

    // opus.h


    /** Gets the size of an <code>OpusEncoder</code> structure.
    * @param[in] channels <tt>int</tt>: Number of channels.
    *                                   This must be 1 or 2.
    * @returns The size in bytes.
    */
    opus_encoder_get_size :: proc(channels: c.int) -> c.int ---

    /** Allocates and initializes an encoder state.
 * There are three coding modes:
 *
 * @ref OPUS_APPLICATION_VOIP gives best quality at a given bitrate for voice
 *    signals. It enhances the  input signal by high-pass filtering and
 *    emphasizing formants and harmonics. Optionally  it includes in-band
 *    forward error correction to protect against packet loss. Use this
 *    mode for typical VoIP applications. Because of the enhancement,
 *    even at high bitrates the output may sound different from the input.
 *
 * @ref OPUS_APPLICATION_AUDIO gives best quality at a given bitrate for most
 *    non-voice signals like music. Use this mode for music and mixed
 *    (music/voice) content, broadcast, and applications requiring less
 *    than 15 ms of coding delay.
 *
 * @ref OPUS_APPLICATION_RESTRICTED_LOWDELAY configures low-delay mode that
 *    disables the speech-optimized mode in exchange for slightly reduced delay.
 *    This mode can only be set on an newly initialized or freshly reset encoder
 *    because it changes the codec delay.
 *
 * This is useful when the caller knows that the speech-optimized modes will not be needed (use with caution).
 * @param [in] Fs <tt>opus_int32</tt>: Sampling rate of input signal (Hz)
 *                                     This must be one of 8000, 12000, 16000,
 *                                     24000, or 48000.
 * @param [in] channels <tt>int</tt>: Number of channels (1 or 2) in input signal
 * @param [in] application <tt>int</tt>: Coding mode (one of @ref OPUS_APPLICATION_VOIP, @ref OPUS_APPLICATION_AUDIO, or @ref OPUS_APPLICATION_RESTRICTED_LOWDELAY)
 * @param [out] error <tt>int*</tt>: @ref opus_errorcodes
 * @note Regardless of the sampling rate and number channels selected, the Opus encoder
 * can switch to a lower audio bandwidth or number of channels if the bitrate
 * selected is too low. This also means that it is safe to always use 48 kHz stereo input
 * and let the encoder optimize the encoding.
 */
  @(require_results) opus_encoder_create :: proc(Fs:opus_int32, channels:int, application:c.int, error:^c.int) -> ^OpusEncoder ---

    /** Initializes a previously allocated encoder state
  * The memory pointed to by st must be at least the size returned by opus_encoder_get_size().
  * This is intended for applications which use their own allocator instead of malloc.
  * @see opus_encoder_create(),opus_encoder_get_size()
  * To reset a previously initialized state, use the #OPUS_RESET_STATE CTL.
  * @param [in] st <tt>OpusEncoder*</tt>: Encoder state
  * @param [in] Fs <tt>opus_int32</tt>: Sampling rate of input signal (Hz)
 *                                      This must be one of 8000, 12000, 16000,
 *                                      24000, or 48000.
  * @param [in] channels <tt>int</tt>: Number of channels (1 or 2) in input signal
  * @param [in] application <tt>int</tt>: Coding mode (one of OPUS_APPLICATION_VOIP, OPUS_APPLICATION_AUDIO, or OPUS_APPLICATION_RESTRICTED_LOWDELAY)
  * @retval #OPUS_OK Success or @ref opus_errorcodes
  */
  opus_encoder_init :: proc(st:^OpusEncoder, Fs:opus_int32, channels:c.int, application:c.int) -> c.int ---

  /** Encodes an Opus frame.
  * @param [in] st <tt>OpusEncoder*</tt>: Encoder state
  * @param [in] pcm <tt>opus_int16*</tt>: Input signal (interleaved if 2 channels). length is frame_size*channels*sizeof(opus_int16)
  * @param [in] frame_size <tt>int</tt>: Number of samples per channel in the
  *                                      input signal.
  *                                      This must be an Opus frame size for
  *                                      the encoder's sampling rate.
  *                                      For example, at 48 kHz the permitted
  *                                      values are 120, 240, 480, 960, 1920,
  *                                      and 2880.
  *                                      Passing in a duration of less than
  *                                      10 ms (480 samples at 48 kHz) will
  *                                      prevent the encoder from using the LPC
  *                                      or hybrid modes.
  * @param [out] data <tt>unsigned char*</tt>: Output payload.
  *                                            This must contain storage for at
  *                                            least \a max_data_bytes.
  * @param [in] max_data_bytes <tt>opus_int32</tt>: Size of the allocated
  *                                                 memory for the output
  *                                                 payload. This may be
  *                                                 used to impose an upper limit on
  *                                                 the instant bitrate, but should
  *                                                 not be used as the only bitrate
  *                                                 control. Use #OPUS_SET_BITRATE to
  *                                                 control the bitrate.
  * @returns The length of the encoded packet (in bytes) on success or a
  *          negative error code (see @ref opus_errorcodes) on failure.
  */
  opus_encode :: proc(st:^OpusEncoder, pcm:[^]opus_int16, frame_size:c.int, data:[^]c.uchar, max_data_bytes:opus_int32) -> opus_int32 ---

  /** Encodes an Opus frame from floating point input.
  * @param [in] st <tt>OpusEncoder*</tt>: Encoder state
  * @param [in] pcm <tt>float*</tt>: Input in float format (interleaved if 2 channels), with a normal range of +/-1.0.
  *          Samples with a range beyond +/-1.0 are supported but will
  *          be clipped by decoders using the integer API and should
  *          only be used if it is known that the far end supports
  *          extended dynamic range.
  *          length is frame_size*channels*sizeof(float)
  * @param [in] frame_size <tt>int</tt>: Number of samples per channel in the
  *                                      input signal.
  *                                      This must be an Opus frame size for
  *                                      the encoder's sampling rate.
  *                                      For example, at 48 kHz the permitted
  *                                      values are 120, 240, 480, 960, 1920,
  *                                      and 2880.
  *                                      Passing in a duration of less than
  *                                      10 ms (480 samples at 48 kHz) will
  *                                      prevent the encoder from using the LPC
  *                                      or hybrid modes.
  * @param [out] data <tt>unsigned char*</tt>: Output payload.
  *                                            This must contain storage for at
  *                                            least \a max_data_bytes.
  * @param [in] max_data_bytes <tt>opus_int32</tt>: Size of the allocated
  *                                                 memory for the output
  *                                                 payload. This may be
  *                                                 used to impose an upper limit on
  *                                                 the instant bitrate, but should
  *                                                 not be used as the only bitrate
  *                                                 control. Use #OPUS_SET_BITRATE to
  *                                                 control the bitrate.
  * @returns The length of the encoded packet (in bytes) on success or a
  *          negative error code (see @ref opus_errorcodes) on failure.
  */
  opus_encode_float :: proc(st:^OpusEncoder, pcm:[^]c.float, frame_size:c.int, data:[^]c.uchar, max_data_bytes:opus_int32) -> opus_int32 ---

  /** Frees an <code>OpusEncoder</code> allocated by opus_encoder_create().
  * @param[in] st <tt>OpusEncoder*</tt>: State to be freed.
  */
  opus_encoder_destroy :: proc(st:^OpusEncoder) ---

  /** Gets the size of an <code>OpusDecoder</code> structure.
  * @param [in] channels <tt>int</tt>: Number of channels.
  *                                    This must be 1 or 2.
  * @returns The size in bytes.
  */
  @(require_results) opus_decoder_get_size :: proc(channels:c.int) -> c.int ---

  /** Allocates and initializes a decoder state.
  * @param [in] Fs <tt>opus_int32</tt>: Sample rate to decode at (Hz).
  *                                     This must be one of 8000, 12000, 16000,
  *                                     24000, or 48000.
  * @param [in] channels <tt>int</tt>: Number of channels (1 or 2) to decode
  * @param [out] error <tt>int*</tt>: #OPUS_OK Success or @ref opus_errorcodes
  *
  * Internally Opus stores data at 48000 Hz, so that should be the default
  * value for Fs. However, the decoder can efficiently decode to buffers
  * at 8, 12, 16, and 24 kHz so if for some reason the caller cannot use
  * data at the full sample rate, or knows the compressed data doesn't
  * use the full frequency range, it can request decoding at a reduced
  * rate. Likewise, the decoder is capable of filling in either mono or
  * interleaved stereo pcm buffers, at the caller's request.
  */
  @(require_results) opus_decoder_create :: proc(Fs:opus_int32, channels:int, error:^c.int) -> ^OpusDecoder ---
}