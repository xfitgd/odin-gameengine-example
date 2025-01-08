#+private
package xfit

import "base:runtime"
import "core:dynlib"
import "core:fmt"
import "core:math"
import "core:mem"
import "core:strings"
import "core:reflect"
import "core:sync"
import vk "vendor:vulkan"
import "vendor:x11/xlib"

vkInstance: vk.Instance
vkDevice: vk.Device
vkLibrary: dynlib.Library
vkSwapchain: vk.SwapchainKHR

vkDebugUtilsMessenger: vk.DebugUtilsMessengerEXT

vkSurface: vk.SurfaceKHR

vkPhysicalDevice: vk.PhysicalDevice
vkPhysicalMemProp: vk.PhysicalDeviceMemoryProperties
vkPhysicalProp: vk.PhysicalDeviceProperties

vkGraphicsQueue: vk.Queue
vkPresentQueue: vk.Queue
vkQueueMutex: sync.Mutex

vkGraphicsFamilyIndex: u32 = max(u32)
vkPresentFamilyIndex: u32 = max(u32)

vkLinearSampler: vk.Sampler
vkNearestSampler: vk.Sampler

vkRenderPass: vk.RenderPass
vkRenderPassSample: vk.RenderPass
vkRenderPassSampleClear: vk.RenderPass
vkRenderPassClear: vk.RenderPass
vkRenderPassCopy: vk.RenderPass


vkGetInstanceProcAddr: proc "system" (
	_instance: vk.Instance,
	_name: cstring,
) -> vk.ProcVoidFunction

vkDebugCallBack :: proc "system" (
	messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
	messageTypes: vk.DebugUtilsMessageTypeFlagsEXT,
	pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT,
	pUserData: rawptr,
) -> b32 {
	context = runtime.default_context()

	//#VUID-VkSwapchainCreateInfoKHR-pNext-07781 1284057537
	//#VUID-vkDestroySemaphore-semaphore-05149 -1813885519
	switch pCallbackData.messageIdNumber {
	case 1284057537, -1813885519:
		return false
	}
	print(pCallbackData.pMessage)

	return false
}

@(rodata)
DEVICE_EXTENSIONS: [2]cstring = {vk.KHR_SWAPCHAIN_EXTENSION_NAME, vk.EXT_FULL_SCREEN_EXCLUSIVE_EXTENSION_NAME}
@(rodata)
INSTANCE_EXTENSIONS: [2]cstring = {
	vk.KHR_GET_SURFACE_CAPABILITIES_2_EXTENSION_NAME,
	vk.KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME,
}
@(rodata)
LAYERS: [1]cstring = {"VK_LAYER_KHRONOS_validation"}
DEVICE_EXTENSIONS_CHECK: [len(DEVICE_EXTENSIONS)]bool
INSTANCE_EXTENSIONS_CHECK: [len(INSTANCE_EXTENSIONS)]bool
LAYERS_CHECK: [len(LAYERS)]bool

validation_layer_support :: #force_inline proc "contextless" () -> bool {return LAYERS_CHECK[0]}
VK_KHR_portability_enumeration_support :: #force_inline proc "contextless" () -> bool {return INSTANCE_EXTENSIONS_CHECK[1]}
VK_EXT_full_screen_exclusive_support :: #force_inline proc "contextless" () -> bool {return DEVICE_EXTENSIONS_CHECK[1]}

vkShapeCurveVertShader: vk.ShaderModule
vkShapeCurveFragShader: vk.ShaderModule
//used copyScreenShaderStages
vkQuadShapeVertShader: vk.ShaderModule
vkQuadShapeFragShader: vk.ShaderModule
vkTexVertShader: vk.ShaderModule
vkTexFragShader: vk.ShaderModule
vkAnimateTexVertShader: vk.ShaderModule
vkAnimateTexFragShader: vk.ShaderModule
vkCopyScreenFragShader: vk.ShaderModule

shapeCurveShaderStages: [2]vk.PipelineShaderStageCreateInfo
quadShapeShaderStages: [2]vk.PipelineShaderStageCreateInfo
texShaderStages: [2]vk.PipelineShaderStageCreateInfo
animateTexShaderStages: [2]vk.PipelineShaderStageCreateInfo
copyScreenShaderStages: [2]vk.PipelineShaderStageCreateInfo

vkQuadShapeDescriptorSetLayout: vk.DescriptorSetLayout
vkShapeCurveDescriptorSetLayout: vk.DescriptorSetLayout
vkTexDescriptorSetLayout: vk.DescriptorSetLayout
//used animate tex
vkTexDescriptorSetLayout2: vk.DescriptorSetLayout
vkAnimateTexDescriptorSetLayout: vk.DescriptorSetLayout
vkCopyScreenDescriptorSetLayout: vk.DescriptorSetLayout

vkQuadShapePipelineLayout: vk.PipelineLayout
vkShapeCurvePipelineLayout: vk.PipelineLayout
vkTexPipelineLayout: vk.PipelineLayout
vkAnimateTexPipelineLayout: vk.PipelineLayout
vkCopyScreenPipelineLayout: vk.PipelineLayout

vkQuadShapePipeline: vk.Pipeline
vkShapeCurvePipeline: vk.Pipeline
vkTexPipeline: vk.Pipeline
vkAnimateTexPipeline: vk.Pipeline
vkCopyScreenPipeline: vk.Pipeline

vkPipelineX4MultisampleStateCreateInfo := vkPipelineMultisampleStateCreateInfoInit({._4})
@(private="file") __vkColorAlphaBlendingExternalState := [1]vk.PipelineColorBlendAttachmentState{vkPipelineColorBlendAttachmentStateInit(
	srcColorBlendFactor = vk.BlendFactor.SRC_ALPHA,
	dstColorBlendFactor = vk.BlendFactor.ONE_MINUS_SRC_ALPHA,
	colorBlendOp = vk.BlendOp.ADD,
	srcAlphaBlendFactor = vk.BlendFactor.ONE,
	dstAlphaBlendFactor = vk.BlendFactor.ONE_MINUS_SRC_ALPHA,
	alphaBlendOp = vk.BlendOp.ADD,
)}
@(private="file") __vkNoBlendingState := [1]vk.PipelineColorBlendAttachmentState{vkPipelineColorBlendAttachmentStateInit(
	blendEnable = false,
	srcColorBlendFactor = vk.BlendFactor.ONE,
	dstColorBlendFactor = vk.BlendFactor.ZERO,
	colorBlendOp = vk.BlendOp.ADD,
	srcAlphaBlendFactor = vk.BlendFactor.ONE,
	dstAlphaBlendFactor = vk.BlendFactor.ZERO,
	alphaBlendOp = vk.BlendOp.ADD,
	colorWriteMask = {},
)}
@(private="file") __vkCopyBlendingState := [1]vk.PipelineColorBlendAttachmentState{vkPipelineColorBlendAttachmentStateInit(
	srcColorBlendFactor = vk.BlendFactor.ONE,
	dstColorBlendFactor = vk.BlendFactor.ONE_MINUS_SRC_ALPHA,
	colorBlendOp = vk.BlendOp.ADD,
	srcAlphaBlendFactor = vk.BlendFactor.ZERO,
	dstAlphaBlendFactor = vk.BlendFactor.ONE,
	alphaBlendOp = vk.BlendOp.ADD,
)}
///https://stackoverflow.com/a/34963588
vkColorAlphaBlendingExternal := vkPipelineColorBlendStateCreateInfoInit(__vkColorAlphaBlendingExternalState[:1])
vkNoBlending := vkPipelineColorBlendStateCreateInfoInit(__vkNoBlendingState[:1])
vkCopyBlending := vkPipelineColorBlendStateCreateInfoInit(__vkNoBlendingState[:1])

vkInitShaderModules :: proc() {
	vkShapeCurveVertShader = vkCreateShaderModule(#load("shaders/shapeCurveVert.spv"))
	vkShapeCurveFragShader = vkCreateShaderModule(#load("shaders/shapeCurveFrag.spv"))
	vkQuadShapeVertShader = vkCreateShaderModule(#load("shaders/quadShapeVert.spv"))
	vkQuadShapeFragShader = vkCreateShaderModule(#load("shaders/quadShapeFrag.spv"))
	vkTexVertShader = vkCreateShaderModule(#load("shaders/texVert.spv"))
	vkTexFragShader = vkCreateShaderModule(#load("shaders/texFrag.spv"))
	vkAnimateTexVertShader = vkCreateShaderModule(#load("shaders/animateTexVert.spv"))
	vkAnimateTexFragShader = vkCreateShaderModule(#load("shaders/animateTexFrag.spv"))
	vkCopyScreenFragShader = vkCreateShaderModule(#load("shaders/copyScreenFrag.spv"))

	shapeCurveShaderStages = vkCreateShaderStages(vkShapeCurveVertShader, vkShapeCurveFragShader)
	quadShapeShaderStages = vkCreateShaderStages(vkQuadShapeVertShader, vkQuadShapeFragShader)
	texShaderStages = vkCreateShaderStages(vkTexVertShader, vkTexFragShader)
	animateTexShaderStages = vkCreateShaderStages(vkAnimateTexVertShader, vkAnimateTexFragShader)
	copyScreenShaderStages = vkCreateShaderStages(vkQuadShapeVertShader, vkCopyScreenFragShader)
}

vkCleanShaderModules :: proc() {
	vk.DestroyShaderModule(vkDevice, vkShapeCurveVertShader, nil)
	vk.DestroyShaderModule(vkDevice, vkShapeCurveFragShader, nil)
	vk.DestroyShaderModule(vkDevice, vkQuadShapeVertShader, nil)
	vk.DestroyShaderModule(vkDevice, vkQuadShapeFragShader, nil)
	vk.DestroyShaderModule(vkDevice, vkTexVertShader, nil)
	vk.DestroyShaderModule(vkDevice, vkTexFragShader, nil)
	vk.DestroyShaderModule(vkDevice, vkAnimateTexVertShader, nil)
	vk.DestroyShaderModule(vkDevice, vkAnimateTexFragShader, nil)
	vk.DestroyShaderModule(vkDevice, vkCopyScreenFragShader, nil)
}

vkInitPipelines :: proc() {
	vkQuadShapeDescriptorSetLayout = vkDescriptorSetLayoutInit(
		[]vk.DescriptorSetLayoutBinding {
			vkDescriptorSetLayoutBindingInit(0, 1, stageFlags = {.FRAGMENT}),},
	)
	vkQuadShapePipelineLayout = vkPipelineLayoutInit(
		[]vk.DescriptorSetLayout{vkQuadShapeDescriptorSetLayout},
	)

	vkShapeCurveDescriptorSetLayout = vkDescriptorSetLayoutInit(
		[]vk.DescriptorSetLayoutBinding {
			vkDescriptorSetLayoutBindingInit(0, 1),
			vkDescriptorSetLayoutBindingInit(1, 1),
			vkDescriptorSetLayoutBindingInit(2, 1),},
	)
	vkShapeCurvePipelineLayout = vkPipelineLayoutInit(
		[]vk.DescriptorSetLayout{vkShapeCurveDescriptorSetLayout},
	)

	vkTexDescriptorSetLayout = vkDescriptorSetLayoutInit(
		[]vk.DescriptorSetLayoutBinding {
			vkDescriptorSetLayoutBindingInit(0, 1),
			vkDescriptorSetLayoutBindingInit(1, 1),
			vkDescriptorSetLayoutBindingInit(2, 1),
			vkDescriptorSetLayoutBindingInit(3, 1, stageFlags = {.FRAGMENT}),},
	)
	vkTexDescriptorSetLayout2 = vkDescriptorSetLayoutInit(
		[]vk.DescriptorSetLayoutBinding {
			vkDescriptorSetLayoutBindingInit(0, 1, descriptorType = .COMBINED_IMAGE_SAMPLER),},
	)
	vkTexPipelineLayout = vkPipelineLayoutInit(
		[]vk.DescriptorSetLayout{vkTexDescriptorSetLayout, vkTexDescriptorSetLayout2},
	)

	vkAnimateTexDescriptorSetLayout = vkDescriptorSetLayoutInit(
		[]vk.DescriptorSetLayoutBinding {
			vkDescriptorSetLayoutBindingInit(0, 1),
			vkDescriptorSetLayoutBindingInit(1, 1),
			vkDescriptorSetLayoutBindingInit(2, 1),
			vkDescriptorSetLayoutBindingInit(3, 1, stageFlags = {.FRAGMENT}),
			vkDescriptorSetLayoutBindingInit(4, 1, stageFlags = {.FRAGMENT}),},
	)
	vkAnimateTexPipelineLayout = vkPipelineLayoutInit(
		[]vk.DescriptorSetLayout{vkAnimateTexDescriptorSetLayout, vkTexDescriptorSetLayout2},
	)

	vkCopyScreenDescriptorSetLayout = vkDescriptorSetLayoutInit(
		[]vk.DescriptorSetLayoutBinding {
			vkDescriptorSetLayoutBindingInit(
				0, 1, descriptorType = .INPUT_ATTACHMENT, stageFlags = {.FRAGMENT}),},
	)
	vkCopyScreenPipelineLayout = vkPipelineLayoutInit(
		[]vk.DescriptorSetLayout{vkCopyScreenDescriptorSetLayout},
	)

	quadStencilOp := vkStencilOpStateInit(.EQUAL, .ZERO, .ZERO, .ZERO)
	shapeStencilOp := vkStencilOpStateInit(.ALWAYS, .ZERO, .INVERT, .ZERO)

	defaultDepthStencilState := vkPipelineDepthStencilStateCreateInfoInit()
	shapeDepthStencilState := vkPipelineDepthStencilStateCreateInfoInit(
		stencilTestEnable = true,
		front = shapeStencilOp,
		back = shapeStencilOp,
	)
	quadDepthStencilState := vkPipelineDepthStencilStateCreateInfoInit(
		depthTestEnable = false,
		depthWriteEnable = false,
		stencilTestEnable = true,
		front = quadStencilOp,
		back = quadStencilOp,
	)

	pipelines:[5]vk.Pipeline
	pipelineCreateInfos:[len(pipelines)]vk.GraphicsPipelineCreateInfo

	pipelineCreateInfos[0] = vkGraphicsPipelineCreateInfoInit(
		stages = quadShapeShaderStages[:2],
		layout = vkQuadShapePipelineLayout,
		renderPass = vkRenderPassSample,
		pMultisampleState = &vkPipelineX4MultisampleStateCreateInfo,
		pDepthStencilState = &quadDepthStencilState,
		pColorBlendState = &vkColorAlphaBlendingExternal,
	)

	shapeCurveVertexInputBindingDescription := [1]vk.VertexInputBindingDescription{{
		binding = 0,
		stride = size_of(f32) * (2 + 3),
		inputRate = .VERTEX,
	}}

	shapeCurveVertexInputAttributeDescription := [2]vk.VertexInputAttributeDescription{{
		location = 0,
		binding = 0,
		format = vk.Format.R32G32_SFLOAT,
		offset = 0,
	},
	{
		location = 1,
		binding = 0,
		format = vk.Format.R32G32B32_SFLOAT,
		offset = size_of(f32) * 2,
	}}
	shapeCurveVertexInputState := vkPipelineVertexInputStateCreateInfoInit(shapeCurveVertexInputBindingDescription[:], shapeCurveVertexInputAttributeDescription[:])
	pipelineCreateInfos[1] = vkGraphicsPipelineCreateInfoInit(
		stages = shapeCurveShaderStages[:],
		layout = vkShapeCurvePipelineLayout,
		renderPass = vkRenderPassSample,
		pMultisampleState = &vkPipelineX4MultisampleStateCreateInfo,
		pDepthStencilState = &shapeDepthStencilState,
		pColorBlendState = &vkNoBlending,
		pVertexInputState = &shapeCurveVertexInputState,
	)
	pipelineCreateInfos[2] = vkGraphicsPipelineCreateInfoInit(
		stages = texShaderStages[:],
		layout = vkTexPipelineLayout,
		renderPass = vkRenderPass,
		pMultisampleState = &vkDefaultPipelineMultisampleStateCreateInfo,
		pDepthStencilState = &defaultDepthStencilState,
		pColorBlendState = &vkDefaultPipelineColorBlendStateCreateInfo,
	)
	pipelineCreateInfos[3] = vkGraphicsPipelineCreateInfoInit(
		stages = animateTexShaderStages[:],
		layout = vkAnimateTexPipelineLayout,
		renderPass = vkRenderPass,
		pMultisampleState = &vkDefaultPipelineMultisampleStateCreateInfo,
		pDepthStencilState = &defaultDepthStencilState,
		pColorBlendState = &vkDefaultPipelineColorBlendStateCreateInfo,
	)
	pipelineCreateInfos[4] = vkGraphicsPipelineCreateInfoInit(
		stages = copyScreenShaderStages[:],
		layout = vkCopyScreenPipelineLayout,
		renderPass = vkRenderPassCopy,
		pMultisampleState = &vkDefaultPipelineMultisampleStateCreateInfo,
		pDepthStencilState = nil,
		pColorBlendState = &vkCopyBlending,
	)
	vk.CreateGraphicsPipelines(vkDevice, 0, len(pipelines), raw_data(pipelineCreateInfos[:]), nil, raw_data(pipelines[:]))

	vkQuadShapePipeline = pipelines[0]
	vkShapeCurvePipeline = pipelines[1]
	vkTexPipeline = pipelines[2]
	vkAnimateTexPipeline = pipelines[3]
	vkCopyScreenPipeline = pipelines[4]
}

vkCleanPipelines :: proc() {
	vk.DestroyDescriptorSetLayout(vkDevice, vkQuadShapeDescriptorSetLayout, nil)
	vk.DestroyDescriptorSetLayout(vkDevice, vkShapeCurveDescriptorSetLayout, nil)
	vk.DestroyDescriptorSetLayout(vkDevice, vkTexDescriptorSetLayout, nil)
	vk.DestroyDescriptorSetLayout(vkDevice, vkTexDescriptorSetLayout2, nil)
	vk.DestroyDescriptorSetLayout(vkDevice, vkAnimateTexDescriptorSetLayout, nil)
	vk.DestroyDescriptorSetLayout(vkDevice, vkCopyScreenDescriptorSetLayout, nil)

	vk.DestroyPipelineLayout(vkDevice, vkQuadShapePipelineLayout, nil)
	vk.DestroyPipelineLayout(vkDevice, vkShapeCurvePipelineLayout, nil)
	vk.DestroyPipelineLayout(vkDevice, vkTexPipelineLayout, nil)
	vk.DestroyPipelineLayout(vkDevice, vkAnimateTexPipelineLayout, nil)
	vk.DestroyPipelineLayout(vkDevice, vkCopyScreenPipelineLayout, nil)

	vk.DestroyPipeline(vkDevice, vkQuadShapePipeline, nil)
	vk.DestroyPipeline(vkDevice, vkShapeCurvePipeline, nil)
	vk.DestroyPipeline(vkDevice, vkTexPipeline, nil)
	vk.DestroyPipeline(vkDevice, vkAnimateTexPipeline, nil)
	vk.DestroyPipeline(vkDevice, vkCopyScreenPipeline, nil)
}

vkFmts:[]vk.SurfaceFormatKHR
vkFmt:vk.SurfaceFormatKHR = {
	format = .UNDEFINED,
	colorSpace = .SRGB_NONLINEAR
}
vkPresentModes:[]vk.PresentModeKHR
vkPresentMode:vk.PresentModeKHR
vkSurfaceCap:vk.SurfaceCapabilitiesKHR
vkExtent:vk.Extent2D
vkExtent_rotation:vk.Extent2D

vkDepthHasOptimal:=false
vkDepthHasTransferSrcOptimal:=false
vkDepthHasTransferDstOptimal:=false
vkDepthHasSampleOptimal:=false

vkColorHasAttachOptimal:=false
vkColorHasSampleOptimal:=false
vkColorHasTransferSrcOptimal:=false
vkColorHasTransferDstOptimal:=false

initSwapChain :: proc() {
	fmtCnt:u32
	vk.GetPhysicalDeviceSurfaceFormatsKHR(vkPhysicalDevice, vkSurface, &fmtCnt, nil)
	vkFmts = make([]vk.SurfaceFormatKHR, fmtCnt)
	vk.GetPhysicalDeviceSurfaceFormatsKHR(vkPhysicalDevice, vkSurface, &fmtCnt, raw_data(vkFmts))

	presentModeCnt:u32
	vk.GetPhysicalDeviceSurfacePresentModesKHR(vkPhysicalDevice, vkSurface, &presentModeCnt, nil)
	vkPresentModes := make([]vk.PresentModeKHR, presentModeCnt)
	vk.GetPhysicalDeviceSurfacePresentModesKHR(vkPhysicalDevice, vkSurface, &presentModeCnt, raw_data(vkPresentModes))

	for f in vkFmts {
		if f.format == .R8G8B8A8_UNORM || f.format == .B8G8R8A8_UNORM {
			when is_log {
				printfln("XFIT SYSLOG : vulkan swapchain format : %s, colorspace : %s\n", f.format, f.colorSpace)
			}
			vkFmt = f
			break;
		}
	}
	if vkFmt.format == .UNDEFINED do panicLog("Xfit vulkan unsupported format")

	depthProp:vk.FormatProperties
	vk.GetPhysicalDeviceFormatProperties(vkPhysicalDevice, .D24_UNORM_S8_UINT, &depthProp)
	vkDepthHasOptimal := .DEPTH_STENCIL_ATTACHMENT in depthProp.optimalTilingFeatures

	__depthFmt = .D24UnormS8Uint
	if !vkDepthHasOptimal && .DEPTH_STENCIL_ATTACHMENT in depthProp.linearTilingFeatures {//not support D24_UNORM_S8_UINT
		vk.GetPhysicalDeviceFormatProperties(vkPhysicalDevice, .D32_SFLOAT_S8_UINT, &depthProp)
		vkDepthHasOptimal = .DEPTH_STENCIL_ATTACHMENT in depthProp.optimalTilingFeatures

		if !vkDepthHasOptimal && .DEPTH_STENCIL_ATTACHMENT in depthProp.linearTilingFeatures {
			vk.GetPhysicalDeviceFormatProperties(vkPhysicalDevice, .D16_UNORM_S8_UINT, &depthProp)
			vkDepthHasOptimal = .DEPTH_STENCIL_ATTACHMENT in depthProp.optimalTilingFeatures
			__depthFmt = .D16UnormS8Uint
		} else {
			__depthFmt = .D32SfloatS8Uint
		}
	}
	vkDepthHasTransferSrcOptimal = .TRANSFER_SRC in depthProp.optimalTilingFeatures
	vkDepthHasTransferDstOptimal = .TRANSFER_DST in depthProp.optimalTilingFeatures
	vkDepthHasSampleOptimal = .SAMPLED_IMAGE in depthProp.optimalTilingFeatures

	colorProp:vk.FormatProperties
	vk.GetPhysicalDeviceFormatProperties(vkPhysicalDevice, vkFmt.format, &colorProp)
	vkColorHasAttachOptimal = .COLOR_ATTACHMENT in colorProp.optimalTilingFeatures
	vkColorHasSampleOptimal = .SAMPLED_IMAGE in colorProp.optimalTilingFeatures
	vkColorHasTransferSrcOptimal =.TRANSFER_SRC in colorProp.optimalTilingFeatures
	vkColorHasTransferDstOptimal = .TRANSFER_DST in colorProp.optimalTilingFeatures

	when is_log {
		printfln("XFIT SYSLOG : depth format : %s", __depthFmt)
		println("XFIT SYSLOG : optimal format supports")
		printfln("vkDepthHasOptimal : %t", vkDepthHasOptimal)
		printfln("vkDepthHasTransferSrcOptimal : %t", vkDepthHasTransferSrcOptimal)
		printfln("vkDepthHasTransferDstOptimal : %t", vkDepthHasTransferDstOptimal)
		printfln("vkDepthHasSampleOptimal : %t", vkDepthHasSampleOptimal)
		printfln("vkColorHasAttachOptimal : %t", vkColorHasAttachOptimal)
		printfln("vkColorHasSampleOptimal : %t", vkColorHasSampleOptimal)
		printfln("vkColorHasTransferSrcOptimal : %t", vkColorHasTransferSrcOptimal)
		printfln("vkColorHasTransferDstOptimal : %t", vkColorHasTransferDstOptimal)
	}
}

createSwapChainAndImageViews :: proc() {
	vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(vkPhysicalDevice, vkSurface, &vkSurfaceCap)

	vkExtent = vkSurfaceCap.currentExtent
	if(vkSurfaceCap.currentExtent.width == max(u32)) {
		vkSurfaceCap.currentExtent.width = clamp(__windowWidth.?, vkSurfaceCap.minImageExtent.width, vkSurfaceCap.maxImageExtent.width)
		vkSurfaceCap.currentExtent.height = clamp(__windowHeight.?, vkSurfaceCap.minImageExtent.height, vkSurfaceCap.maxImageExtent.height)
	}
	vkExtent_rotation = vkExtent
	if is_mobile {
		if .ROTATE_90 in vkSurfaceCap.currentTransform {
			vkExtent_rotation.width = vkExtent.height
			vkExtent_rotation.height = vkExtent.width
			__screenOrientation = .Landscape90
		} else if .ROTATE_270 in vkSurfaceCap.currentTransform {
			vkExtent_rotation.width = vkExtent.height
			vkExtent_rotation.height = vkExtent.width
			__screenOrientation = .Landscape270
		} else if .ROTATE_180 in vkSurfaceCap.currentTransform {
			__screenOrientation = .Vertical180
		} else if .IDENTITY in vkSurfaceCap.currentTransform {
			__screenOrientation = .Vertical360
		} 
	}

	vkPresentMode = .FIFO
	if __vSync == .Double {
		when is_log {
			if programStart do println("XFIT SYSLOG : vulkan present mode fifo_khr vsync double")
		}
	} else {
		if __vSync == .Triple {
			for p in vkPresentModes {
				if p == .MAILBOX {
					when is_log {
						if programStart do println("XFIT SYSLOG : vulkan present mode mailbox_khr vsync triple")
					}
					vkPresentMode = p
					break;
				}
			}
		}
		for p in vkPresentModes {
			if p == .IMMEDIATE {
				when is_log {
					if programStart {
						if __vSync == .Triple do println("XFIT SYSLOG : vulkan present mode immediate_khr mailbox_khr instead(vsync triple -> none)")
						else do println("XFIT SYSLOG : vulkan present mode immediate_khr vsync none")
					} 
				}
				vkPresentMode = p
				break;
			}
		}
	}

	surfaceImgCnt := max(__swapImgCnt ,vkSurfaceCap.minImageCount)
	if vkSurfaceCap.maxImageCount > 0 && surfaceImgCnt > vkSurfaceCap.maxImageCount {//0 is no limit max+
		surfaceImgCnt = vkSurfaceCap.maxImageCount
	}
	__swapImgCnt = surfaceImgCnt

	swapChainCreateInfo := vk.SwapchainCreateInfoKHR{
		sType = vk.StructureType.SWAPCHAIN_CREATE_INFO_KHR,
		minImageCount = __swapImgCnt,
		imageFormat = vkFmt.format,
		imageColorSpace = vkFmt.colorSpace,
		imageExtent = vkExtent_rotation,
		imageArrayLayers = 1,
		imageUsage = {.COLOR_ATTACHMENT},
		presentMode = vkPresentMode,
		preTransform = vkSurfaceCap.currentTransform,
		compositeAlpha = vkSurfaceCap.supportedCompositeAlpha,
		clipped = true,
		oldSwapchain = 0,
		imageSharingMode = .EXCLUSIVE,
		pNext = nil,
		queueFamilyIndexCount = 0,
		surface = vkSurface
	}
	when ODIN_OS == .Windows {
		if __isFullScreenEx && VK_EXT_full_screen_exclusive_support {
			fullScreenWinInfo : vk.SurfaceFullScreenExclusiveWin32InfoEXT
			fullScreenInfo := vk.SurfaceFullScreenExclusiveInfoEXT{
				sType = vk.StructureType.SURFACE_FULL_SCREEN_EXCLUSIVE_INFO_EXT,
				pNext = nil,
				fullScreenExclusive = .APPLICATION_CONTROLLED,
			}
			if currentMonitor != nil {
				fullScreenWinInfo = vk.SurfaceFullScreenExclusiveWin32InfoEXT{
					sType = vk.StructureType.SURFACE_FULL_SCREEN_EXCLUSIVE_WIN32_INFO_EXT,
					pNext = nil,
					hMonitor = currentMonitor.__windows.hmonitor,
				}
				fullScreenInfo.pNext = &fullScreenWinInfo
			}
			swapChainCreateInfo.pNext = &fullScreenInfo
		}
	}
	queueFamiliesIndices := [2]u32{vkGraphicsFamilyIndex, vkPresentFamilyIndex}
	if vkGraphicsFamilyIndex != vkPresentFamilyIndex {
		swapChainCreateInfo.imageSharingMode = .CONCURRENT
		swapChainCreateInfo.queueFamilyIndexCount = 2
		swapChainCreateInfo.pQueueFamilyIndices = raw_data(queueFamiliesIndices[:])
	}

	res := vk.CreateSwapchainKHR(vkDevice, &swapChainCreateInfo, nil, &vkSwapchain)
	if res != .SUCCESS do panicLog("res = vk.CreateSwapchainKHR(vkDevice, &swapChainCreateInfo, nil, &vkSwapchain) : ", res)

	vk.GetSwapchainImagesKHR(vkDevice, vkSwapchain, &__swapImgCnt, nil)
	swapImgs:= make([]vk.Image, __swapImgCnt, context.temp_allocator)
	defer delete(swapImgs, context.temp_allocator)

	for img, i in swapImgs {
		
	}
} 

vulkanStart :: proc() {
	ok: bool
	when ODIN_OS == .Windows {
		vkLibrary, ok = dynlib.load_library("vulkan-1.dll")
		if !ok do panicLog(" vkLibrary, ok = dynlib.load_library(\"vulkan-1.dll\")")
	} else {
		vkLibrary, ok = dynlib.load_library("libvulkan.so.1")
		if !ok {
			vkLibrary, ok = dynlib.load_library("libvulkan.so")
			if !ok do panicLog(" vkLibrary, ok = dynlib.load_library(\"libvulkan.so\")")
		}
	}
	rawFunc: rawptr
	rawFunc, ok = dynlib.symbol_address(vkLibrary, "vkGetInstanceProcAddr")
	if !ok do panicLog("rawFunc, ok = dynlib.symbol_address(vkLibrary, \"vkGetInstanceProcAddr\")")
	vkGetInstanceProcAddr = auto_cast rawFunc
	vk.load_proc_addresses_global(rawFunc)

	appInfo := vk.ApplicationInfo {
		apiVersion         = vk.API_VERSION_1_4,
		engineVersion      = vk.MAKE_VERSION(1, 0, 0),
		applicationVersion = vk.MAKE_VERSION(1, 0, 0),
		pEngineName        = "Xfit",
		pApplicationName   = ODIN_BUILD_PROJECT_NAME,
	}
	GetInstanceProcAddr := vk.GetInstanceProcAddr(nil, "vkEnumerateInstanceVersion")
	if GetInstanceProcAddr == nil {
		when is_log do println("XFIT SYSLOG : vulkan 1.0 device, set api version 1.0")
		appInfo.apiVersion = vk.API_VERSION_1_0
	}

	instanceExtNames := make([dynamic]cstring, 0, len(INSTANCE_EXTENSIONS) + 3, context.temp_allocator)
	defer delete(instanceExtNames)
	layerNames := make([dynamic]cstring, 0, len(LAYERS), context.temp_allocator)
	defer delete(layerNames)

	append(&instanceExtNames, vk.KHR_SURFACE_EXTENSION_NAME)

	layerPropCnt: u32
	vk.EnumerateInstanceLayerProperties(&layerPropCnt, nil)

	availableLayers := make([]vk.LayerProperties, layerPropCnt, context.temp_allocator)
	defer delete(availableLayers, context.temp_allocator)

	vk.EnumerateInstanceLayerProperties(&layerPropCnt, &availableLayers[0])

	for &l in availableLayers {
		for _, i in LAYERS {
			if !LAYERS_CHECK[i] &&
			   mem.compare((transmute([^]byte)LAYERS[i])[:len(LAYERS[i])], l.layerName[:len(LAYERS[i])]) == 0 {
				when !ODIN_DEBUG {
					if LAYERS[i] == "VK_LAYER_KHRONOS_validation" do continue
				}
				append(&layerNames, LAYERS[i])
				LAYERS_CHECK[i] = true
				when is_log do printfln(
					"XFIT SYSLOG : vulkan %s instance layer support",
					LAYERS[i],
				)
			}
		}
	}
	instanceExtCnt: u32
	vk.EnumerateInstanceExtensionProperties(nil, &instanceExtCnt, nil)

	availableInstanceExts := make([]vk.ExtensionProperties, instanceExtCnt, context.temp_allocator)
	defer delete(availableInstanceExts, context.temp_allocator)

	vk.EnumerateInstanceExtensionProperties(nil, &instanceExtCnt, &availableInstanceExts[0])

	for &e in availableInstanceExts {
		for _, i in INSTANCE_EXTENSIONS {
			if !LAYERS_CHECK[i] &&
			   mem.compare((transmute([^]byte)INSTANCE_EXTENSIONS[i])[:len(INSTANCE_EXTENSIONS[i])], e.extensionName[:len(INSTANCE_EXTENSIONS[i])]) == 0 {
				append(&instanceExtNames, INSTANCE_EXTENSIONS[i])
				INSTANCE_EXTENSIONS_CHECK[i] = true
				when is_log do printfln(
					"XFIT SYSLOG : vulkan %s instance ext support",
					INSTANCE_EXTENSIONS[i],
				)
			}
		}
	}
	if validation_layer_support() {
		append(&instanceExtNames, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)

		when is_log do println("XFIT SYSLOG : vulkan validation layer enable")
	} else {
		when is_log do println("XFIT SYSLOG : vulkan validation layer disable")
	}

	when is_android {
		append(&instanceExtNames, "VK_KHR_android_surface")
	} else when ODIN_OS == .Linux {
		append(&instanceExtNames, "VK_KHR_xlib_surface")
	} else when ODIN_OS == .Windows {
		append(&instanceExtNames, vk.KHR_WIN32_SURFACE_EXTENSION_NAME)
	}

	instanceCreateInfo := vk.InstanceCreateInfo {
		pApplicationInfo        = &appInfo,
		enabledLayerCount       = auto_cast len(layerNames),
		ppEnabledLayerNames     = &layerNames[0] if len(layerNames) > 0 else nil,
		enabledExtensionCount   = auto_cast len(instanceExtNames),
		ppEnabledExtensionNames = &instanceExtNames[0],
		pNext                   = nil,
		flags                   = vk.InstanceCreateFlags{.ENUMERATE_PORTABILITY_KHR} if VK_KHR_portability_enumeration_support() else vk.InstanceCreateFlags{},
	}

	res := vk.CreateInstance(&instanceCreateInfo, nil, &vkInstance)
	if (res != vk.Result.SUCCESS) do panicLog("vk.CreateInstance(&instanceCreateInfo, nil, &vkInstance) : ", res)

	vk.load_proc_addresses_instance(vkInstance)

	if validation_layer_support() && ODIN_DEBUG {
		debugUtilsCreateInfo := vk.DebugUtilsMessengerCreateInfoEXT {
			messageSeverity = vk.DebugUtilsMessageSeverityFlagsEXT{.ERROR, .VERBOSE, .WARNING},
			messageType     = vk.DebugUtilsMessageTypeFlagsEXT {.GENERAL, .VALIDATION, .PERFORMANCE},
			pfnUserCallback = nil,
			pUserData       = nil,
		}
		vk.CreateDebugUtilsMessengerEXT(
			vkInstance,
			&debugUtilsCreateInfo,
			nil,
			&vkDebugUtilsMessenger,
		)
	}

	when is_android {
		//TODO LOAD FUNC
		vulkanAndroidStart(&vkSurface)
	} else when ODIN_OS == .Linux {
		vkCreateXlibSurfaceKHR = auto_cast vk.GetInstanceProcAddr(vkInstance, "vkCreateXlibSurfaceKHR")
		vulkanLinuxStart(&vkSurface)
	} else when ODIN_OS == .Windows {
		vulkanWindowsStart(&vkSurface)
	}

	physicalDeviceCnt: u32
	vk.EnumeratePhysicalDevices(vkInstance, &physicalDeviceCnt, nil)
	vkPhysicalDevices := make([]vk.PhysicalDevice, physicalDeviceCnt, context.temp_allocator)
	defer delete(vkPhysicalDevices, context.temp_allocator)
	vk.EnumeratePhysicalDevices(vkInstance, &physicalDeviceCnt, &vkPhysicalDevices[0])

	out: for pd in vkPhysicalDevices {
		queueFamilyPropCnt: u32
		vk.GetPhysicalDeviceQueueFamilyProperties(pd, &queueFamilyPropCnt, nil)
		queueFamilies := make([]vk.QueueFamilyProperties, queueFamilyPropCnt, context.temp_allocator)
		defer delete(queueFamilies, context.temp_allocator)
		vk.GetPhysicalDeviceQueueFamilyProperties(pd, &queueFamilyPropCnt, &queueFamilies[0])

		for i in 0 ..< queueFamilyPropCnt {
			if .GRAPHICS in queueFamilies[i].queueFlags do vkGraphicsFamilyIndex = i
			
			isPresentSupport: b32
			vk.GetPhysicalDeviceSurfaceSupportKHR(pd, i, vkSurface, &isPresentSupport)

			if isPresentSupport do vkPresentFamilyIndex = i
			if vkGraphicsFamilyIndex != max(u32) && vkPresentFamilyIndex != max(u32) {
				vkPhysicalDevice = pd
				break out
			}
		}
	}
	queuePriorty: [1]f32 = {1}
	deviceQueueCreateInfos := [2]vk.DeviceQueueCreateInfo {
		vk.DeviceQueueCreateInfo {
			sType = vk.StructureType.DEVICE_QUEUE_CREATE_INFO,
			queueCount = 1,
			queueFamilyIndex = vkGraphicsFamilyIndex,
			pQueuePriorities = &queuePriorty[0],
		},
		vk.DeviceQueueCreateInfo {
			sType = vk.StructureType.DEVICE_QUEUE_CREATE_INFO,
			queueCount = 1,
			queueFamilyIndex = vkPresentFamilyIndex,
			pQueuePriorities = &queuePriorty[0],
		},
	}
	queueCnt: u32 = 1 if vkGraphicsFamilyIndex == vkPresentFamilyIndex else 2

	physicalDeviceFeatures := vk.PhysicalDeviceFeatures {
		samplerAnisotropy = true,
		sampleRateShading = true, //FOR ANTI-ALISING
	}

	deviceExtCnt: u32
	vk.EnumerateDeviceExtensionProperties(vkPhysicalDevice, nil, &deviceExtCnt, nil)
	deviceExts := make([]vk.ExtensionProperties, deviceExtCnt, context.temp_allocator)
	defer delete(deviceExts, context.temp_allocator)
	vk.EnumerateDeviceExtensionProperties(vkPhysicalDevice, nil, &deviceExtCnt, &deviceExts[0])

	deviceExtNames := make([dynamic]cstring, 0, len(DEVICE_EXTENSIONS) + 1, context.temp_allocator)
	defer delete(deviceExtNames)
	append(&deviceExtNames, vk.KHR_SWAPCHAIN_EXTENSION_NAME)

	for &e in deviceExts {
		for _, i in DEVICE_EXTENSIONS {
			if !DEVICE_EXTENSIONS_CHECK[i] &&
			   mem.compare((transmute([^]byte)DEVICE_EXTENSIONS[i])[:len(DEVICE_EXTENSIONS[i])],e.extensionName[:len(DEVICE_EXTENSIONS[i])]) == 0 {
				append(&instanceExtNames, DEVICE_EXTENSIONS[i])
				DEVICE_EXTENSIONS_CHECK[i] = true
				when is_log do printfln(
					"XFIT SYSLOG : vulkan %s device ext support",
					DEVICE_EXTENSIONS[i],
				)
			}
		}
	}

	deviceCreateInfo := vk.DeviceCreateInfo {
		sType                   = vk.StructureType.DEVICE_CREATE_INFO,
		pQueueCreateInfos       = &deviceQueueCreateInfos[0],
		queueCreateInfoCount    = len(deviceQueueCreateInfos),
		pEnabledFeatures        = &physicalDeviceFeatures,
		ppEnabledExtensionNames = &deviceExtNames[0],
		enabledExtensionCount   = auto_cast len(deviceExtNames),
	}
	res = vk.CreateDevice(vkPhysicalDevice, &deviceCreateInfo, nil, &vkDevice)
	if (res != vk.Result.SUCCESS) do panicLog("res = vk.CreateDevice(vkPhysicalDevice, &deviceCreateInfo, nil, &vkDevice) : ", res)
	vk.load_proc_addresses_device(vkDevice)

	vk.GetPhysicalDeviceMemoryProperties(vkPhysicalDevice, &vkPhysicalMemProp)
	vk.GetPhysicalDeviceProperties(vkPhysicalDevice, &vkPhysicalProp)

	if vkGraphicsFamilyIndex == vkPresentFamilyIndex {
		vk.GetDeviceQueue(vkDevice, vkGraphicsFamilyIndex, 0, &vkGraphicsQueue)
		vkPresentQueue = vkGraphicsQueue
	} else {
		vk.GetDeviceQueue(vkDevice, vkGraphicsFamilyIndex, 0, &vkGraphicsQueue)
		vk.GetDeviceQueue(vkDevice, vkPresentFamilyIndex, 0, &vkPresentQueue)
	}

	vkInitBlockLen()
	vkAllocatorInit()

	initSwapChain()
	createSwapChainAndImageViews()

	samplerInfo := vk.SamplerCreateInfo {
		sType                   = vk.StructureType.SAMPLER_CREATE_INFO,
		addressModeU            = .REPEAT,
		addressModeV            = .REPEAT,
		addressModeW            = .REPEAT,
		mipmapMode              = .LINEAR,
		magFilter               = .LINEAR,
		minFilter               = .LINEAR,
		mipLodBias              = 0,
		compareOp               = .ALWAYS,
		compareEnable           = false,
		unnormalizedCoordinates = false,
		minLod                  = 0,
		maxLod                  = 0,
		anisotropyEnable        = false,
		maxAnisotropy           = vkPhysicalProp.limits.maxSamplerAnisotropy,
		borderColor             = .INT_OPAQUE_WHITE,
	}
	vk.CreateSampler(vkDevice, &samplerInfo, nil, &vkLinearSampler)
	samplerInfo.mipmapMode = .NEAREST
	samplerInfo.magFilter = .NEAREST
	samplerInfo.minFilter = .NEAREST
	vk.CreateSampler(vkDevice, &samplerInfo, nil, &vkNearestSampler)

	vkDepthFmt := TextureFmtToVkFmt(__depthFmt)
	depthAttachmentSample := vkAttachmentDescriptionInit(
		format = vkDepthFmt,
		loadOp = .LOAD,
		storeOp = .STORE,
		stencilLoadOp = .CLEAR,
		stencilStoreOp = .STORE,
		initialLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
		finalLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
		samples = {vk.SampleCountFlag._4},
	)
	depthAttachmentSampleClear := vkAttachmentDescriptionInit(
		format = vkDepthFmt,
		loadOp = .CLEAR,
		storeOp = .STORE,
		finalLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
		samples = {vk.SampleCountFlag._4},
	)
	colorAttachmentSampleClear := vkAttachmentDescriptionInit(
		format = vkFmt.format,
		loadOp = .CLEAR,
		storeOp = .STORE,
		finalLayout = .COLOR_ATTACHMENT_OPTIMAL,
		samples = {vk.SampleCountFlag._4},
	)
	colorAttachmentSample := vkAttachmentDescriptionInit(
		format = vkFmt.format,
		loadOp = .LOAD,
		storeOp = .STORE,
		initialLayout = .COLOR_ATTACHMENT_OPTIMAL,
		finalLayout = .COLOR_ATTACHMENT_OPTIMAL,
		samples = {vk.SampleCountFlag._4},
	)
	colorAttachmentResolve := vkAttachmentDescriptionInit(
		format = vkFmt.format,
		storeOp = .STORE,
		finalLayout = .COLOR_ATTACHMENT_OPTIMAL,
	)
	colorAttachmentLoadResolve := vkAttachmentDescriptionInit(
		format = vkFmt.format,
		loadOp = .LOAD,
		initialLayout = .COLOR_ATTACHMENT_OPTIMAL,
		finalLayout = .COLOR_ATTACHMENT_OPTIMAL,
	)
	colorAttachmentClear := vkAttachmentDescriptionInit(
		format = vkFmt.format,
		loadOp = .CLEAR,
		storeOp = .STORE,
		finalLayout = .PRESENT_SRC_KHR,
	)
	depthAttachmentClear := vkAttachmentDescriptionInit(
		format = vkDepthFmt,
		loadOp = .CLEAR,
		storeOp = .STORE,
		finalLayout = .PRESENT_SRC_KHR,
	)
	colorAttachment := vkAttachmentDescriptionInit(
		format = vkFmt.format,
		loadOp = .LOAD,
		storeOp = .STORE,
		initialLayout = .PRESENT_SRC_KHR,
		finalLayout = .PRESENT_SRC_KHR,
	)
	depthAttachment := vkAttachmentDescriptionInit(
		format = vkDepthFmt,
		loadOp = .LOAD,
		storeOp = .STORE,
		initialLayout = .PRESENT_SRC_KHR,
		finalLayout = .PRESENT_SRC_KHR,
	)

	colorAttachmentRef := vk.AttachmentReference {
		attachment = 0,
		layout     = .COLOR_ATTACHMENT_OPTIMAL,
	}
	colorResolveAttachmentRef := vk.AttachmentReference {
		attachment = 2,
		layout     = .COLOR_ATTACHMENT_OPTIMAL,
	}
	depthAttachmentRef := vk.AttachmentReference {
		attachment = 1,
		layout     = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
	}
	inputAttachmentRef := vk.AttachmentReference {
		attachment = 1,
		layout     = .SHADER_READ_ONLY_OPTIMAL,
	}

	subpassDesc := vk.SubpassDescription {
		pipelineBindPoint       = .GRAPHICS,
		colorAttachmentCount    = 1,
		pColorAttachments       = &colorAttachmentRef,
		pDepthStencilAttachment = &depthAttachmentRef,
	}
	subpassResolveDesc := subpassDesc
	subpassResolveDesc.pResolveAttachments = &colorResolveAttachmentRef
	subpassCopyDesc := vk.SubpassDescription {
		pipelineBindPoint    = .GRAPHICS,
		colorAttachmentCount = 1,
		inputAttachmentCount = 1,
		pColorAttachments    = &colorAttachmentRef,
		pInputAttachments    = &inputAttachmentRef,
	}

	subpassDependency := vk.SubpassDependency {
		srcSubpass    = vk.SUBPASS_EXTERNAL,
		dstSubpass    = 0,
		srcStageMask  = {.COLOR_ATTACHMENT_OUTPUT, .LATE_FRAGMENT_TESTS},
		srcAccessMask = {},
		dstStageMask  = {.COLOR_ATTACHMENT_OUTPUT, .EARLY_FRAGMENT_TESTS},
		dstAccessMask = {.COLOR_ATTACHMENT_READ, .DEPTH_STENCIL_ATTACHMENT_READ},
	}
	subpassDependencyCopy := vk.SubpassDependency {
		srcSubpass    = vk.SUBPASS_EXTERNAL,
		dstSubpass    = 0,
		srcStageMask  = {.COLOR_ATTACHMENT_OUTPUT},
		srcAccessMask = {},
		dstStageMask  = {.COLOR_ATTACHMENT_OUTPUT},
		dstAccessMask = {.COLOR_ATTACHMENT_WRITE},
	}

	renderPassSampleInfo := vkRenderPassCreateInfoInit(
		pAttachments = []vk.AttachmentDescription {
			colorAttachmentSample,
			depthAttachmentSample,
			colorAttachmentResolve,
		},
		pSubpasses = []vk.SubpassDescription{subpassResolveDesc},
		pDependencies = []vk.SubpassDependency{subpassDependency},
	)
	vk.CreateRenderPass(vkDevice, &renderPassSampleInfo, nil, &vkRenderPassSample)

	renderPassSampleClearInfo := vkRenderPassCreateInfoInit(
		pAttachments = []vk.AttachmentDescription {
			colorAttachmentSampleClear,
			depthAttachmentSampleClear,
			colorAttachmentResolve,
		},
		pSubpasses = []vk.SubpassDescription{subpassResolveDesc},
		pDependencies = []vk.SubpassDependency{subpassDependency},
	)
	vk.CreateRenderPass(vkDevice, &renderPassSampleClearInfo, nil, &vkRenderPassSampleClear)

	renderPassInfo := vkRenderPassCreateInfoInit(
		pAttachments = []vk.AttachmentDescription{colorAttachment, depthAttachment},
		pSubpasses = []vk.SubpassDescription{subpassDesc},
		pDependencies = []vk.SubpassDependency{subpassDependency},
	)
	vk.CreateRenderPass(vkDevice, &renderPassInfo, nil, &vkRenderPass)

	renderPassClearInfo := vkRenderPassCreateInfoInit(
		pAttachments = []vk.AttachmentDescription{colorAttachmentClear, depthAttachmentClear},
		pSubpasses = []vk.SubpassDescription{subpassDesc},
		pDependencies = []vk.SubpassDependency{subpassDependency},
	)
	vk.CreateRenderPass(vkDevice, &renderPassClearInfo, nil, &vkRenderPassClear)

	renderPassCopyInfo := vkRenderPassCreateInfoInit(
		pAttachments = []vk.AttachmentDescription{colorAttachment, colorAttachmentLoadResolve},
		pSubpasses = []vk.SubpassDescription{subpassCopyDesc},
		pDependencies = []vk.SubpassDependency{subpassDependencyCopy},
	)
	vk.CreateRenderPass(vkDevice, &renderPassCopyInfo, nil, &vkRenderPassCopy)

	vkInitShaderModules()

	vkInitPipelines()
}

vulkanDestory :: proc() {
	vkCleanPipelines()
	vkCleanShaderModules()
	dynlib.unload_library(vkLibrary)
}
