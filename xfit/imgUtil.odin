package xfit

import vk "vendor:vulkan"
import "base:runtime"
import "base:intrinsics"

TextureFmt :: enum {
    DefaultColor,
    DefaultDepth,
    R8G8B8A8Unorm,
    B8G8R8A8Unorm,
    // B8G8R8A8Srgb,
    // R8G8B8A8Srgb,
    D24UnormS8Uint,
    D32SfloatS8Uint,
    D16UnormS8Uint,
	R8Unorm,
}

@(require_results) TextureFmt_IsDepth :: proc  "contextless" (t:TextureFmt) -> bool {
	#partial switch(t) {
		case .D24UnormS8Uint, .D32SfloatS8Uint, .D16UnormS8Uint, .DefaultDepth:
		return true
	}
	return false
}

@(require_results) TextureFmt_BitSize :: proc  "contextless" (fmt:TextureFmt) -> int {
    switch (fmt) {
        case .DefaultColor : return TextureFmt_BitSize(vkFmtToTextureFmt(vkFmt.format))
        case .DefaultDepth : return TextureFmt_BitSize(__depthFmt)
        case .R8G8B8A8Unorm:
		case .B8G8R8A8Unorm:
		case .D24UnormS8Uint:
            return 4
		case .D16UnormS8Uint:
            return 3
		case .D32SfloatS8Uint:
            return 5
		case .R8Unorm:
			return 1
    }
    return 4
}

@(require_results) @private TextureFmtToVkFmt :: proc "contextless" (t:TextureFmt) -> vk.Format {
	switch t {
		case .DefaultColor:
			return vkFmt.format
        case .DefaultDepth:
            return TextureFmtToVkFmt(__depthFmt)
		case .R8G8B8A8Unorm:
			return .R8G8B8A8_UNORM
		case .B8G8R8A8Unorm:
			return .B8G8R8A8_UNORM
		case .D24UnormS8Uint:
			return .D24_UNORM_S8_UINT
		case .D16UnormS8Uint:
			return .D16_UNORM_S8_UINT
		case .D32SfloatS8Uint:
			return .D32_SFLOAT_S8_UINT
		case .R8Unorm:
			return .R8_UNORM
	}
    return vkFmt.format
}

@(require_results) @private vkFmtToTextureFmt :: proc "contextless" (t:vk.Format) -> TextureFmt {
	#partial switch t {
		case .R8G8B8A8_UNORM:
			return .R8G8B8A8Unorm
		case .B8G8R8A8_UNORM:
			return .B8G8R8A8Unorm
		case .D24_UNORM_S8_UINT:
			return .D24UnormS8Uint
		case .D16_UNORM_S8_UINT:
			return .D16UnormS8Uint
		case .D32_SFLOAT_S8_UINT:
			return .D32SfloatS8Uint
		case .R8_UNORM:
			return .R8Unorm
	}
	panicLog("unsupport format vkFmtToTextureFmt : ", t)
}
