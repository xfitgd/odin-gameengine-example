#+private
package xfit

import "base:runtime"
import "core:dynlib"
import "core:fmt"
import "core:math"
import "core:mem"
import "core:strings"
import "core:sync"
import vk "vendor:vulkan"
import "vendor:x11/xlib"

vkInstance: vk.Instance
vkDevice: vk.Device
vkLibrary: dynlib.Library

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
DEVICE_EXTENSIONS: [1]cstring = {"VK_KHR_swapchain"}
@(rodata)
INSTANCE_EXTENSIONS: [2]cstring = {
	"VK_KHR_get_surface_capabilities2",
	"VK_KHR_portability_enumeration",
}
@(rodata)
LAYERS: [1]cstring = {"VK_LAYER_KHRONOS_validation"}
DEVICE_EXTENSIONS_CHECK: [len(DEVICE_EXTENSIONS)]bool
INSTANCE_EXTENSIONS_CHECK: [len(INSTANCE_EXTENSIONS)]bool
LAYERS_CHECK: [len(LAYERS)]bool

validation_layer_support :: proc() -> bool {return LAYERS_CHECK[0]}
VK_KHR_portability_enumeration_support :: proc() -> bool {return INSTANCE_EXTENSIONS_CHECK[1]}

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

	instanceExtNames: [dynamic]cstring
	defer delete(instanceExtNames)
	layerNames: [dynamic]cstring
	defer delete(layerNames)

	append(&instanceExtNames, vk.KHR_SURFACE_EXTENSION_NAME)

	layerPropCnt: u32
	vk.EnumerateInstanceLayerProperties(&layerPropCnt, nil)

	availableLayers := make([]vk.LayerProperties, layerPropCnt)
	defer delete(availableLayers)

	vk.EnumerateInstanceLayerProperties(&layerPropCnt, &availableLayers[0])

	for &l in availableLayers {
		for _, i in LAYERS {
			if !LAYERS_CHECK[i] &&
			   mem.compare((transmute([^]u8)LAYERS[i])[:len(LAYERS)], l.layerName[:len(LAYERS)]) == 0 {
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

	availableInstanceExts := make([]vk.ExtensionProperties, instanceExtCnt)
	defer delete(availableInstanceExts)

	vk.EnumerateInstanceExtensionProperties(nil, &instanceExtCnt, &availableInstanceExts[0])

	for &e in availableInstanceExts {
		for _, i in INSTANCE_EXTENSIONS {
			if !LAYERS_CHECK[i] &&
			   mem.compare((transmute([^]u8)INSTANCE_EXTENSIONS[i])[:len(INSTANCE_EXTENSIONS)], e.extensionName[:len(INSTANCE_EXTENSIONS)]) == 0 {
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
	vkPhysicalDevices := make([]vk.PhysicalDevice, physicalDeviceCnt)
	defer delete(vkPhysicalDevices)
	vk.EnumeratePhysicalDevices(vkInstance, &physicalDeviceCnt, &vkPhysicalDevices[0])

	out: for pd in vkPhysicalDevices {
		queueFamilyPropCnt: u32
		vk.GetPhysicalDeviceQueueFamilyProperties(pd, &queueFamilyPropCnt, nil)
		queueFamilies := make([]vk.QueueFamilyProperties, queueFamilyPropCnt)
		defer delete(queueFamilies)
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
	deviceExts := make([]vk.ExtensionProperties, deviceExtCnt)
	defer delete(deviceExts)
	vk.EnumerateDeviceExtensionProperties(vkPhysicalDevice, nil, &deviceExtCnt, &deviceExts[0])

	deviceExtNames: [dynamic]cstring
	defer delete(deviceExtNames)
	append(&deviceExtNames, vk.KHR_SWAPCHAIN_EXTENSION_NAME)

	for &e in deviceExts {
		for _, i in DEVICE_EXTENSIONS {
			if !DEVICE_EXTENSIONS_CHECK[i] &&
			   mem.compare((transmute([^]u8)DEVICE_EXTENSIONS[i])[:len(DEVICE_EXTENSIONS)],e.extensionName[:len(DEVICE_EXTENSIONS)]) == 0 {
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

	createSwapChainAndImageViews(true)

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

	depthAttachmentSample := vkAttachmentDescriptionInit(
		format = .D24_UNORM_S8_UINT,
		loadOp = .LOAD,
		storeOp = .STORE,
		stencilLoadOp = .CLEAR,
		stencilStoreOp = .STORE,
		initialLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
		finalLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
		samples = {vk.SampleCountFlag._4},
	)
	depthAttachmentSampleClear := vkAttachmentDescriptionInit(
		format = .D24_UNORM_S8_UINT,
		loadOp = .CLEAR,
		storeOp = .STORE,
		finalLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
		samples = {vk.SampleCountFlag._4},
	)
	colorAttachmentSampleClear := vkAttachmentDescriptionInit(
		format = .R8G8B8A8_UNORM,
		loadOp = .CLEAR,
		storeOp = .STORE,
		finalLayout = .COLOR_ATTACHMENT_OPTIMAL,
		samples = {vk.SampleCountFlag._4},
	)
	colorAttachmentSample := vkAttachmentDescriptionInit(
		format = .R8G8B8A8_UNORM,
		loadOp = .LOAD,
		storeOp = .STORE,
		initialLayout = .COLOR_ATTACHMENT_OPTIMAL,
		finalLayout = .COLOR_ATTACHMENT_OPTIMAL,
		samples = {vk.SampleCountFlag._4},
	)
	colorAttachmentResolve := vkAttachmentDescriptionInit(
		format = .R8G8B8A8_UNORM,
		storeOp = .STORE,
		finalLayout = .COLOR_ATTACHMENT_OPTIMAL,
	)
	colorAttachmentLoadResolve := vkAttachmentDescriptionInit(
		format = .R8G8B8A8_UNORM,
		loadOp = .LOAD,
		initialLayout = .COLOR_ATTACHMENT_OPTIMAL,
		finalLayout = .COLOR_ATTACHMENT_OPTIMAL,
	)
	colorAttachmentClear := vkAttachmentDescriptionInit(
		format = .R8G8B8A8_UNORM,
		loadOp = .CLEAR,
		storeOp = .STORE,
		finalLayout = .PRESENT_SRC_KHR,
	)
	depthAttachmentClear := vkAttachmentDescriptionInit(
		format = .D24_UNORM_S8_UINT,
		loadOp = .CLEAR,
		storeOp = .STORE,
		finalLayout = .PRESENT_SRC_KHR,
	)
	colorAttachment := vkAttachmentDescriptionInit(
		format = .R8G8B8A8_UNORM,
		loadOp = .LOAD,
		storeOp = .STORE,
		initialLayout = .PRESENT_SRC_KHR,
		finalLayout = .PRESENT_SRC_KHR,
	)
	depthAttachment := vkAttachmentDescriptionInit(
		format = .D24_UNORM_S8_UINT,
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
