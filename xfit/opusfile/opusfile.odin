package opusfile

import "core:c"
import "core:c/libc"
import "../xlibrary"


LIBOPUSFILE :: xlibrary.LIBPATH + "/opusfile/libopusfile" + xlibrary.ARCH_end

foreign import lib {
	LIBOPUSFILE,
}

/**A request did not succeed.*/
OP_FALSE :: -1
/**Currently not used externally.**/
OP_EOF :: -2
/**There was a hole in the page sequence numbers (e.g., a page was corrupt or missing).*/
OP_HOLE :: -3
/**An underlying read, seek, or tell operation failed when it should have
    succeeded.*/
OP_EREAD :: -128
/**A <code>NULL</code> pointer was passed where one was unexpected, or an
    internal memory allocation failed, or an internal library error was
    encountered.*/
OP_EFAULT :: -129
/**The stream used a feature that is not implemented, such as an unsupported
    channel family.*/
OP_EIMPL :: -130
/**One or more parameters to a function were invalid.*/
OP_EINVAL :: -131
/**A purported Ogg Opus stream did not begin with an Ogg page, a purported
    header packet did not start with one of the required strings, "OpusHead" or
    "OpusTags", or a link in a chained file was encountered that did not
    contain any logical Opus streams.*/
OP_ENOTFORMAT :: -132
/**A required header packet was not properly formatted, contained illegal
    values, or was missing altogether.*/
OP_EBADHEADER :: -133
/**The ID header contained an unrecognized version number.*/
OP_EVERSION :: -134
/**Currently not used at all.**/
OP_ENOTAUDIO :: -135
/**An audio packet failed to decode properly.
   This is usually caused by a multistream Ogg packet where the durations of
    the individual Opus packets contained in it are not all the same.*/
OP_EBADPACKET :: -136
/**We failed to find data we had seen before, or the bitstream structure was
    sufficiently malformed that seeking to the target destination was
    impossible.*/
OP_EBADLINK :: -137
/**An operation that requires seeking was requested on an unseekable stream.*/
OP_ENOSEEK :: -138
/**The first or last granule position of a link failed basic validity checks.*/
OP_EBADTIMESTAMP :: -139

/**The maximum number of channels in an Ogg Opus stream.*/
OPUS_CHANNEL_COUNT_MAX :: 255

OpusHead :: struct {
	version:c.int,
	channel_count:c.int,
	pre_skip : c.uint,
	
}