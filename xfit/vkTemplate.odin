#+private
package xfit

import "base:runtime"
import "core:math"
import "core:mem"
import "core:strings"
import vk "vendor:vulkan"
import "vendor:x11/xlib"


vkCreateXlibSurfaceKHR: proc "system" (
	_instance: vk.Instance,
	pCreateInfo: ^VkXlibSurfaceCreateInfoKHR,
	pAllocator: ^vk.AllocationCallbacks,
	pSurface: ^vk.SurfaceKHR,
) -> vk.Result

VK_STRUCTURE_TYPE_XLIB_SURFACE_CREATE_INFO_KHR :: 1000004000

VkXlibSurfaceCreateInfoKHR :: struct {
	sType:  i32,
	pNext:  rawptr,
	flags:  u64,
	dpy:    ^xlib.Display,
	window: xlib.Window,
}

@(rodata) vkDefaultDynamicStates := [2]vk.DynamicState{vk.DynamicState.VIEWPORT, vk.DynamicState.SCISSOR}
vkDefaultPipelineDynamicStateCreateInfo := vk.PipelineDynamicStateCreateInfo {
	sType             = vk.StructureType.PIPELINE_DYNAMIC_STATE_CREATE_INFO,
	dynamicStateCount = 2,
	pDynamicStates    = &vkDefaultDynamicStates[0],
}

@(private="file") __vkDefaultPipelineColorBlendAttachmentState := [1]vk.PipelineColorBlendAttachmentState{vkPipelineColorBlendAttachmentStateInit()}
vkDefaultPipelineColorBlendStateCreateInfo := vkPipelineColorBlendStateCreateInfoInit(__vkDefaultPipelineColorBlendAttachmentState[:1])

vkDefaultPipelineMultisampleStateCreateInfo := vkPipelineMultisampleStateCreateInfoInit()
vkDefaultPipelineInputAssemblyStateCreateInfo := vkPipelineInputAssemblyStateCreateInfoInit()
vkDefaultPipelineRasterizationStateCreateInfo := vkPipelineRasterizationStateCreateInfoInit()
vkDefaultPipelineVertexInputStateCreateInfo := vkPipelineVertexInputStateCreateInfoInit()
vkDefaultPipelineDepthStencilStateCreateInfo := vkPipelineDepthStencilStateCreateInfoInit()


@(require_results) vkCreateShaderModule :: proc(code: []byte) -> vk.ShaderModule {
	code_ := transmute([]u32)code
	createInfo := vk.ShaderModuleCreateInfo {
		codeSize = len(code_),
		pCode    = raw_data(code_),
		sType    = vk.StructureType.SHADER_MODULE_CREATE_INFO,
	}

	shaderModule: vk.ShaderModule
	vk.CreateShaderModule(vkDevice, &createInfo, nil, &shaderModule)

	return shaderModule
}

@(require_results) vkCreateShaderStages :: proc "contextless" (
	vertModule: vk.ShaderModule,
	fragModule: vk.ShaderModule,
) -> [2]vk.PipelineShaderStageCreateInfo {
	return [2]vk.PipelineShaderStageCreateInfo {
		vk.PipelineShaderStageCreateInfo {
			sType = vk.StructureType.PIPELINE_SHADER_STAGE_CREATE_INFO,
			pName = "main",
			module = vertModule,
			stage = {.VERTEX},
		},
		vk.PipelineShaderStageCreateInfo {
			sType = vk.StructureType.PIPELINE_SHADER_STAGE_CREATE_INFO,
			pName = "main",
			module = fragModule,
			stage = {.FRAGMENT},
		},
	}
}

@(require_results) vkCreateShaderStagesGS :: proc "contextless" (
	vertModule: vk.ShaderModule,
	fragModule: vk.ShaderModule,
	geomModule: vk.ShaderModule,
) -> [3]vk.PipelineShaderStageCreateInfo {
	return [3]vk.PipelineShaderStageCreateInfo {
		vk.PipelineShaderStageCreateInfo {
			sType = vk.StructureType.PIPELINE_SHADER_STAGE_CREATE_INFO,
			pName = "main",
			module = vertModule,
			stage = {.VERTEX},
		},
		vk.PipelineShaderStageCreateInfo {
			sType = vk.StructureType.PIPELINE_SHADER_STAGE_CREATE_INFO,
			pName = "main",
			module = geomModule,
			stage = {.GEOMETRY},
		},
		vk.PipelineShaderStageCreateInfo {
			sType = vk.StructureType.PIPELINE_SHADER_STAGE_CREATE_INFO,
			pName = "main",
			module = fragModule,
			stage = {.FRAGMENT},
		},
	}
}

@(require_results) vkDescriptorSetLayoutBindingInit :: proc "contextless"(
	binding: u32,
	descriptorCount: u32,
	descriptorType: vk.DescriptorType = .UNIFORM_BUFFER,
	stageFlags: vk.ShaderStageFlags = {.VERTEX, .FRAGMENT},
	pImmutableSampler: ^vk.Sampler = nil,
) -> vk.DescriptorSetLayoutBinding {
	return {
		binding = binding,
		descriptorCount = descriptorCount,
		descriptorType = descriptorType,
		stageFlags = stageFlags,
		pImmutableSamplers = pImmutableSampler,
	}
}

@(require_results) vkDescriptorSetLayoutInit :: proc "contextless"(
	bindings: []vk.DescriptorSetLayoutBinding,
) -> vk.DescriptorSetLayout {
	setLayoutInfo := vk.DescriptorSetLayoutCreateInfo {
		bindingCount = auto_cast len(bindings),
		pBindings    = raw_data(bindings),
		sType        = vk.StructureType.DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
	}
	descriptorSetLayout: vk.DescriptorSetLayout
	vk.CreateDescriptorSetLayout(vkDevice, &setLayoutInfo, nil, &descriptorSetLayout)

	return descriptorSetLayout
}


@(require_results) vkPipelineLayoutInit :: proc "contextless"(sets: []vk.DescriptorSetLayout) -> vk.PipelineLayout {
	pipelineLayoutInfo := vk.PipelineLayoutCreateInfo {
		setLayoutCount = auto_cast len(sets),
		pSetLayouts    = raw_data(sets),
		sType          = vk.StructureType.PIPELINE_LAYOUT_CREATE_INFO,
	}
	pipelineLayout: vk.PipelineLayout
	vk.CreatePipelineLayout(vkDevice, &pipelineLayoutInfo, nil, &pipelineLayout)

	return pipelineLayout
}

@(require_results) vkStencilOpStateInit :: proc "contextless"(
	compareOp: vk.CompareOp,
	depthFailOp: vk.StencilOp,
	passOp: vk.StencilOp,
	failOp: vk.StencilOp,
	compareMask: u32 = 0xff,
	writeMask: u32 = 0xff,
	reference: u32 = 0xff,
) -> vk.StencilOpState {
	return {
		compareOp = compareOp,
		depthFailOp = depthFailOp,
		passOp = passOp,
		failOp = failOp,
		compareMask = compareMask,
		writeMask = writeMask,
		reference = reference,
	}
}

@(require_results) vkPipelineDepthStencilStateCreateInfoInit :: proc "contextless"(
	depthTestEnable: b32 = true,
	depthWriteEnable: b32 = true,
	depthBoundsTestEnable: b32 = false,
	depthCompareOp: vk.CompareOp = vk.CompareOp.LESS_OR_EQUAL,
	stencilTestEnable: b32 = false,
	front: vk.StencilOpState = {},
	back: vk.StencilOpState = {},
	maxDepthBounds: f32 = 0,
	minDepthBounds: f32 = 0,
) -> vk.PipelineDepthStencilStateCreateInfo {
	return {
		depthTestEnable = depthTestEnable,
		depthWriteEnable = depthWriteEnable,
		depthBoundsTestEnable = depthBoundsTestEnable,
		depthCompareOp = depthCompareOp,
		stencilTestEnable = stencilTestEnable,
		front = front,
		back = back,
		maxDepthBounds = maxDepthBounds,
		minDepthBounds = minDepthBounds,
		sType = vk.StructureType.PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
	}
}

@(require_results) vkPipelineInputAssemblyStateCreateInfoInit :: proc "contextless"(
	topology: vk.PrimitiveTopology =  vk.PrimitiveTopology.TRIANGLE_LIST,
	primitiveRestartEnable: b32 = false,
	pNext: rawptr = nil,
	flags: vk.PipelineInputAssemblyStateCreateFlags = {},
) -> vk.PipelineInputAssemblyStateCreateInfo {
	return {
		sType = vk.StructureType.PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		pNext = pNext,
		flags = flags,
		topology = topology,
		primitiveRestartEnable = primitiveRestartEnable,
	}
}

@(require_results) vkPipelineViewportStateCreateInfoInit :: proc "contextless"(
	viewportCount: u32 = 1,
	pViewports:    [^]vk.Viewport = nil,
	scissorCount:  u32 = 1,
	pScissors:     [^]vk.Rect2D = nil,
	flags:         vk.PipelineViewportStateCreateFlags = {},
	pNext:         rawptr = nil,
) -> vk.PipelineViewportStateCreateInfo {
	return {
		sType = vk.StructureType.PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = viewportCount,
		pViewports = pViewports,
		scissorCount = scissorCount,
		pScissors = pScissors,
		flags = flags,
		pNext = pNext,
	}
}

@(require_results) vkPipelineVertexInputStateCreateInfoInit :: proc "contextless"(
	pVertexBindingDescriptions:Maybe([]vk.VertexInputBindingDescription) = nil,
	pVertexAttributeDescriptions:Maybe([]vk.VertexInputAttributeDescription) = nil,
	flags:         vk.PipelineVertexInputStateCreateFlags = {},
	pNext:         rawptr = nil,
) -> vk.PipelineVertexInputStateCreateInfo {
	return {
		sType = vk.StructureType.PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexBindingDescriptionCount = 0 if pVertexBindingDescriptions == nil else auto_cast len(pVertexBindingDescriptions.?),
		pVertexBindingDescriptions = raw_data(pVertexBindingDescriptions.?) if pVertexBindingDescriptions != nil && len(pVertexBindingDescriptions.?) > 0 else nil,
		vertexAttributeDescriptionCount = 0 if pVertexAttributeDescriptions == nil else auto_cast len(pVertexAttributeDescriptions.?),
		pVertexAttributeDescriptions = raw_data(pVertexAttributeDescriptions.?) if pVertexAttributeDescriptions != nil && len(pVertexAttributeDescriptions.?) > 0 else nil,
		flags = flags,
		pNext = pNext,
	}
}



@(require_results) vkGraphicsPipelineCreateInfoInit :: proc "contextless"(
	stages: []vk.PipelineShaderStageCreateInfo,
	layout: vk.PipelineLayout,
	renderPass: vk.RenderPass,
	pVertexInputState: ^vk.PipelineVertexInputStateCreateInfo = nil,
	pInputAssemblyState: ^vk.PipelineInputAssemblyStateCreateInfo = nil,
	pTessellationState: ^vk.PipelineTessellationStateCreateInfo = nil,
	pViewportState: ^vk.PipelineViewportStateCreateInfo = nil,
	pRasterizationState: ^vk.PipelineRasterizationStateCreateInfo = nil,
	pMultisampleState: ^vk.PipelineMultisampleStateCreateInfo = nil,
	pDepthStencilState: ^vk.PipelineDepthStencilStateCreateInfo = nil,
	pColorBlendState: ^vk.PipelineColorBlendStateCreateInfo = nil,
	pDynamicState: ^vk.PipelineDynamicStateCreateInfo = nil,
	subpass: u32 = 0,
	basePipelineHandle: vk.Pipeline = 0,
	basePipelineIndex: i32 = -1,
) -> vk.GraphicsPipelineCreateInfo {
	return {
		stageCount = auto_cast len(stages),
		pStages = raw_data(stages),
		pVertexInputState = pVertexInputState if pVertexInputState != nil else &vkDefaultPipelineVertexInputStateCreateInfo,
		pInputAssemblyState = pInputAssemblyState if pInputAssemblyState != nil else &vkDefaultPipelineInputAssemblyStateCreateInfo,
		pTessellationState = pTessellationState,
		pViewportState = pViewportState if pViewportState != nil else nil,
		pRasterizationState = pRasterizationState if pRasterizationState != nil else &vkDefaultPipelineRasterizationStateCreateInfo,
		pMultisampleState = pMultisampleState if pMultisampleState != nil else &vkDefaultPipelineMultisampleStateCreateInfo,
		pDepthStencilState = pDepthStencilState,
		pColorBlendState = pColorBlendState if pColorBlendState != nil else &vkDefaultPipelineColorBlendStateCreateInfo,
		pDynamicState = pDynamicState if pDynamicState != nil else &vkDefaultPipelineDynamicStateCreateInfo,
		layout = layout,
		renderPass = renderPass,
		subpass = subpass,
		basePipelineHandle = basePipelineHandle,
		basePipelineIndex = basePipelineIndex,
		sType = vk.StructureType.GRAPHICS_PIPELINE_CREATE_INFO,
		pNext = nil,
		flags = {},
	}
}

@(require_results) vkAttachmentDescriptionInit :: proc "contextless"(
	format: vk.Format,
	loadOp: vk.AttachmentLoadOp = .DONT_CARE,
	storeOp: vk.AttachmentStoreOp = .DONT_CARE,
	initialLayout: vk.ImageLayout = .UNDEFINED,
	finalLayout: vk.ImageLayout = .UNDEFINED,
	stencilLoadOp: vk.AttachmentLoadOp = .DONT_CARE,
	stencilStoreOp: vk.AttachmentStoreOp = .DONT_CARE,
	samples: vk.SampleCountFlags = {vk.SampleCountFlag._1},
) -> vk.AttachmentDescription {
	return {
		loadOp = loadOp,
		storeOp = storeOp,
		initialLayout = initialLayout,
		finalLayout = finalLayout,
		stencilLoadOp = stencilLoadOp,
		stencilStoreOp = stencilStoreOp,
		samples = samples,
		format = format,
	}
}

@(require_results) vkRenderPassCreateInfoInit :: proc "contextless"(
	pAttachments: []vk.AttachmentDescription,
	pSubpasses: []vk.SubpassDescription,
	pDependencies: []vk.SubpassDependency,
) -> vk.RenderPassCreateInfo {
	return {
		sType = vk.StructureType.RENDER_PASS_CREATE_INFO,
		attachmentCount = auto_cast len(pAttachments),
		pAttachments = &pAttachments[0],
		subpassCount = auto_cast len(pSubpasses),
		pSubpasses = &pSubpasses[0],
		dependencyCount = auto_cast len(pDependencies),
		pDependencies = &pDependencies[0],
	}
}

@(require_results) vkPipelineRasterizationStateCreateInfoInit :: proc "contextless"(
	polygonMode:             vk.PolygonMode = vk.PolygonMode.FILL,
	frontFace:               vk.FrontFace = vk.FrontFace.CLOCKWISE,
	cullMode:                vk.CullModeFlags = {},
	depthClampEnable:        b32 = false,
	rasterizerDiscardEnable: b32 = false,
	depthBiasEnable:         b32 = false,
	depthBiasConstantFactor: f32 = 0,
	depthBiasClamp:          f32 = 0,
	depthBiasSlopeFactor:    f32 = 0,
	lineWidth:               f32 = 1,
	pNext:                   rawptr = nil,
	flags:                   vk.PipelineRasterizationStateCreateFlags = {},
) -> vk.PipelineRasterizationStateCreateInfo {
	return {
		sType = vk.StructureType.PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		polygonMode = polygonMode,
		frontFace = frontFace,
		cullMode = cullMode,
		depthClampEnable = depthClampEnable,
		rasterizerDiscardEnable = rasterizerDiscardEnable, 
		depthBiasEnable = depthBiasEnable,
		depthBiasConstantFactor = depthBiasConstantFactor,
		depthBiasClamp = depthBiasClamp,
		depthBiasSlopeFactor = depthBiasSlopeFactor,
		lineWidth = lineWidth,
		pNext = pNext,
		flags = flags,
	}
}

@(require_results) vkPipelineMultisampleStateCreateInfoInit :: proc "contextless"(
	rasterizationSamples:  vk.SampleCountFlags = {._1},
	sampleShadingEnable:   b32 = true,
	minSampleShading:      f32 = 0,
	pSampleMask:           ^vk.SampleMask = nil,
	alphaToCoverageEnable: b32 = false,
	alphaToOneEnable:      b32 = false,
    pNext:                 rawptr = nil,
	flags:                 vk.PipelineMultisampleStateCreateFlags = {},
) -> vk.PipelineMultisampleStateCreateInfo {
	return {
		sType = vk.StructureType.PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        rasterizationSamples = rasterizationSamples,
        sampleShadingEnable = sampleShadingEnable,
        minSampleShading = minSampleShading,
        pSampleMask = pSampleMask,
        alphaToCoverageEnable = alphaToCoverageEnable,
        alphaToOneEnable = alphaToOneEnable,
        pNext = pNext,
        flags = flags,
	}
}

@(require_results) vkPipelineColorBlendAttachmentStateInit :: proc "contextless"(
	blendEnable:         b32 = true,
	srcColorBlendFactor: vk.BlendFactor = vk.BlendFactor.SRC_ALPHA,
	dstColorBlendFactor: vk.BlendFactor = vk.BlendFactor.ONE_MINUS_SRC_ALPHA,
	colorBlendOp:        vk.BlendOp = vk.BlendOp.ADD,
	srcAlphaBlendFactor: vk.BlendFactor = vk.BlendFactor.ONE,
	dstAlphaBlendFactor: vk.BlendFactor = vk.BlendFactor.ZERO,
	alphaBlendOp:        vk.BlendOp = vk.BlendOp.ADD,
	colorWriteMask:      vk.ColorComponentFlags = {.R,.G,.B,.A},
) -> vk.PipelineColorBlendAttachmentState {
	return {
		blendEnable = blendEnable,
		srcColorBlendFactor = srcColorBlendFactor,
		dstColorBlendFactor = dstColorBlendFactor,
		colorBlendOp = colorBlendOp,
		srcAlphaBlendFactor = srcAlphaBlendFactor,
		dstAlphaBlendFactor = dstAlphaBlendFactor,
		alphaBlendOp = alphaBlendOp,
		colorWriteMask = colorWriteMask,
	}
}

@(require_results) vkPipelineColorBlendStateCreateInfoInit :: proc "contextless"(
	pAttachments:    []vk.PipelineColorBlendAttachmentState,
	logicOpEnable:   b32 = false,
	logicOp:         vk.LogicOp = vk.LogicOp.COPY,
	blendConstants:  [4]f32 = {0,0,0,0},
	flags:           vk.PipelineColorBlendStateCreateFlags = {},
	pNext:           rawptr = nil,
) -> vk.PipelineColorBlendStateCreateInfo {
	return {
		sType = vk.StructureType.PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		pNext = pNext,
		flags = flags,
		logicOpEnable = logicOpEnable,
		logicOp = logicOp, 
		attachmentCount = auto_cast len(pAttachments),
		pAttachments = raw_data(pAttachments),
		blendConstants = blendConstants,
	}
}

vkTransitionImageLayout :: proc(cmd:vk.CommandBuffer, image:vk.Image, mipLevels:u32, arrayStart:u32, arrayLayers:u32, oldLayout:vk.ImageLayout, newLayout:vk.ImageLayout) {
	barrier := vk.ImageMemoryBarrier{
		sType = vk.StructureType.IMAGE_MEMORY_BARRIER,
		oldLayout = oldLayout,
		newLayout = newLayout,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image = image,
		subresourceRange = {
			aspectMask = {.COLOR},
			baseMipLevel = 0,
			levelCount = mipLevels,
			baseArrayLayer = arrayStart,
			layerCount = arrayLayers
		}
	}
	
	srcStage : vk.PipelineStageFlags
	dstStage : vk.PipelineStageFlags

	if oldLayout == .UNDEFINED && newLayout == .TRANSFER_DST_OPTIMAL {
		barrier.srcAccessMask = {}
		barrier.dstAccessMask = {.TRANSFER_WRITE}

		srcStage = {.TOP_OF_PIPE}
		dstStage = {.TRANSFER}
	} else if oldLayout == .TRANSFER_DST_OPTIMAL && newLayout == .SHADER_READ_ONLY_OPTIMAL {
		barrier.srcAccessMask = {.TRANSFER_WRITE}
		barrier.dstAccessMask = {.SHADER_READ}

		srcStage = {.TRANSFER}
		dstStage = {.FRAGMENT_SHADER}
	} else if oldLayout == .UNDEFINED && newLayout == .COLOR_ATTACHMENT_OPTIMAL {
		barrier.srcAccessMask = {}
		barrier.dstAccessMask = {.SHADER_READ}

		srcStage = {.TOP_OF_PIPE}
		dstStage = {.FRAGMENT_SHADER}
	} else if oldLayout == .UNDEFINED && newLayout == .GENERAL {
		barrier.srcAccessMask = {}
		barrier.dstAccessMask = {.SHADER_READ, .SHADER_WRITE}

		srcStage = {.TOP_OF_PIPE}
		dstStage = {.FRAGMENT_SHADER}
	} else {
		panicLog("unsupported layout transition!", oldLayout, newLayout)
	}

	vk.CmdPipelineBarrier(cmd,
	srcStage,
	dstStage,
	{},
	0,
	nil,
	0,
	nil,
	1,
	&barrier)
}