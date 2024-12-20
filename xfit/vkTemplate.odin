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


@(require_results) vkCreateShaderModule :: proc(code: []u8) -> vk.ShaderModule {
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

@(require_results) vkCreateShaderStages :: proc(
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

@(require_results) vkDescriptorSetLayoutBindingInit :: proc(
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

@(require_results) vkDescriptorSetLayoutInit :: proc(
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


@(require_results) vkPipelineLayoutInit :: proc(sets: []vk.DescriptorSetLayout) -> vk.PipelineLayout {
	pipelineLayoutInfo := vk.PipelineLayoutCreateInfo {
		setLayoutCount = auto_cast len(sets),
		pSetLayouts    = raw_data(sets),
		sType          = vk.StructureType.PIPELINE_LAYOUT_CREATE_INFO,
	}
	pipelineLayout: vk.PipelineLayout
	vk.CreatePipelineLayout(vkDevice, &pipelineLayoutInfo, nil, &pipelineLayout)

	return pipelineLayout
}

@(require_results) vkStencilOpStateInit :: proc(
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

@(require_results) vkPipelineDepthStencilStateCreateInfoInit :: proc(
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

@(rodata) vkDefaultDynamicStates := [2]vk.DynamicState{vk.DynamicState.VIEWPORT, vk.DynamicState.SCISSOR}
vkDefaultPipelineDynamicStateCreateInfo := vk.PipelineDynamicStateCreateInfo {
	sType             = vk.StructureType.PIPELINE_DYNAMIC_STATE_CREATE_INFO,
	dynamicStateCount = 2,
	pDynamicStates    = &vkDefaultDynamicStates[0],
}

@(require_results) vkGraphicsPipelineCreateInfoInit :: proc(
	pStages: [^]vk.PipelineShaderStageCreateInfo,
	layout: vk.PipelineLayout,
	renderPass: vk.RenderPass,
	pVertexInputState: ^vk.PipelineVertexInputStateCreateInfo,
	stageCount: u32 = 2,
	pInputAssemblyState: ^vk.PipelineInputAssemblyStateCreateInfo = nil,
	pTessellationState: ^vk.PipelineTessellationStateCreateInfo = nil,
	pViewportState: ^vk.PipelineViewportStateCreateInfo = nil,
	pRasterizationState: ^vk.PipelineRasterizationStateCreateInfo = nil,
	pMultisampleState: ^vk.PipelineMultisampleStateCreateInfo = nil,
	pDepthStencilState: ^vk.PipelineDepthStencilStateCreateInfo = nil,
	pColorBlendState: ^vk.PipelineColorBlendStateCreateInfo = nil,
	pDynamicState: ^vk.PipelineDynamicStateCreateInfo = nil, //vkDefaultPipelineDynamicStateCreateInfo
	subpass: u32 = 0,
	basePipelineHandle: vk.Pipeline = 0,
	basePipelineIndex: i32 = -1,
) -> vk.GraphicsPipelineCreateInfo {
	return {
		stageCount = stageCount,
		pStages = pStages,
		pVertexInputState = pVertexInputState,
		pInputAssemblyState = pInputAssemblyState,
		pTessellationState = pTessellationState,
		pViewportState = pViewportState,
		pRasterizationState = pRasterizationState,
		pMultisampleState = pMultisampleState,
		pDepthStencilState = pDepthStencilState,
		pColorBlendState = pColorBlendState,
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

@(require_results) vkAttachmentDescriptionInit :: proc(
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

@(require_results) vkRenderPassCreateInfoInit :: proc(
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

vkDefaultPipelineRasterizationStateCreateInfo :: proc() -> vk.PipelineRasterizationStateCreateInfo { return vkPipelineRasterizationStateCreateInfoInit() }

@(require_results) vkPipelineRasterizationStateCreateInfoInit ::  proc(
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