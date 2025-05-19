#+private
package xfit 

import "external/android"
import "core:thread"
import "core:sync"
import "core:c"
import "core:sys/posix"
import "core:strings"
import "base:intrinsics"
import "base:runtime"
import vk "vendor:vulkan"

when is_android {
    @(private="file") app : ^android.android_app

    VkAndroidSurfaceCreateFlagsKHR :: vk.Flags
    VkAndroidSurfaceCreateInfoKHR :: struct {
        sType: vk.StructureType,
        pNext:rawptr,
        flags:VkAndroidSurfaceCreateFlagsKHR,
        window:^android.ANativeWindow,
    }
    vkCreateAndroidSurfaceKHR : proc "system" (instance: vk.Instance, pCreateInfo: ^VkAndroidSurfaceCreateInfoKHR, pAllocator: ^vk.AllocationCallbacks, pSurface:^vk.SurfaceKHR) -> vk.Result

    //must call start
    __android_SetApp :: proc "contextless" (_app : ^android.android_app) {
        app = _app
    }
 
    android_GetAssetManager :: proc "contextless" () -> ^android.AAssetManager {
        return app.activity.assetManager
    }
    android_GetDeviceWidth :: proc "contextless" () -> u32 {
        return auto_cast max(0, android.ANativeWindow_getWidth(app.window))
    }
    android_GetDeviceHeight :: proc "contextless" () -> u32 {
        return auto_cast max(0, android.ANativeWindow_getHeight(app.window))
    }
    // android_GetCacheDir :: proc "contextless" () -> string {
    //     return app.cacheDir
    // }
    android_GetInternalDataPath :: proc "contextless" () -> string {
        return string(app.activity.internalDataPath)
    }
    android_PrintCurrentConfig :: proc () {
        lang:[2]u8
        country:[2]u8

        android.AConfiguration_getLanguage(app.config, &lang[0])
        android.AConfiguration_getCountry(app.config, &country[0])

        printf("Config: mcc=%d mnc=%d lang=%c%c cnt=%c%c orien=%d touch=%d dens=%d keys=%d nav=%d keysHid=%d navHid=%d sdk=%d size=%d long=%d modetype=%d modenight=%d", 
            android.AConfiguration_getMcc(app.config),
            android.AConfiguration_getMnc(app.config),
            lang[0],
            lang[1],
            country[0],
            country[1],
            android.AConfiguration_getOrientation(app.config),
            android.AConfiguration_getTouchscreen(app.config),
            android.AConfiguration_getDensity(app.config),
            android.AConfiguration_getKeyboard(app.config),
            android.AConfiguration_getNavigation(app.config),
            android.AConfiguration_getKeysHidden(app.config),
            android.AConfiguration_getNavHidden(app.config),
            android.AConfiguration_getSdkVersion(app.config),
            android.AConfiguration_getScreenSize(app.config),
            android.AConfiguration_getScreenLong(app.config),
            android.AConfiguration_getUiModeType(app.config),
            android.AConfiguration_getUiModeNight(app.config),
        )
    }

    vulkanAndroidStart :: proc "contextless" () {
        if vkSurface != 0 {
            vk.DestroySurfaceKHR(vkInstance, vkSurface, nil)
        }
        if vkCreateAndroidSurfaceKHR == nil {
            vkCreateAndroidSurfaceKHR = auto_cast vk.GetInstanceProcAddr(vkInstance, "vkCreateAndroidSurfaceKHR")
        }

        androidSurfaceCreateInfo : VkAndroidSurfaceCreateInfoKHR = {
            sType = vk.StructureType.ANDROID_SURFACE_CREATE_INFO_KHR,
            window = app.window,
        }
        res := vkCreateAndroidSurfaceKHR(vkInstance, &androidSurfaceCreateInfo, nil, &vkSurface)
        if res != .SUCCESS {
            panicLog(res)
        }
    }
    @(private="file") freeSavedState :: proc "contextless" () {
        //TODO
    }
    @(private="file") handleInput :: proc "c" (app:^android.android_app, evt : ^android.AInputEvent) -> c.int {
        type := android.AInputEvent_getType(evt)
        src := android.AInputEvent_getSource(evt)

        if type == .MOTION {
            toolType := android.AMotionEvent_getToolType(evt, 0)
            //https://github.com/gameplay3d/GamePlay/blob/master/gameplay/src/PlatformAndroid.cpp
            if android.InputSourceDevice.JOYSTICK in transmute(android.InputSourceDevice)(src.device) {
                
            }
        }
        return 0
    }
    @(private="file") handleCmd :: proc "c" (app:^android.android_app, cmd : android.AppCmd) {
        @static appInited := false

        #partial switch cmd {
            case .SAVE_STATE:
                //TODO
            case .INIT_WINDOW:
                if app.window != nil {
                    if !appInited {
                        context = runtime.default_context()
                        vkStart()

                        __windowWidth = vkExtent.width
		                __windowHeight = vkExtent.height

		                Init()
                        appInited = true
                    } else {
                        sizeUpdated = true
                    }
                }
            case .TERM_WINDOW:
                //EMPTY
            case .GAINED_FOCUS:
                paused = false
                activated = false
                Activate()
            case .LOST_FOCUS:
                paused = true
                activated = true
                Activate()
            case .WINDOW_RESIZED:
                sync.mutex_lock(&fullScreenMtx)
                defer sync.mutex_unlock(&fullScreenMtx)

                prop : vk.SurfaceCapabilitiesKHR
                res := vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(vkPhysicalDevice, vkSurface, &prop)
                if res != .SUCCESS do panicLog(res)
                if prop.currentExtent.width != vkExtent.width || prop.currentExtent.height != vkExtent.height {
                    sizeUpdated = true
                }
        }
    }

    androidStart :: proc () {
        app.userData = nil
        app.onAppCmd = handleCmd
        app.onInputEvent = handleInput

        for {
            events: i32
            source: ^android.android_poll_source

            ident := android.ALooper_pollAll(!paused ? 0 : -1, nil, &events, cast(^rawptr)&source)
            for ident >= 0 {
                if source != nil {
                    source.process(app, source)
                }

                if app.destroyRequested != 0 {
                    vkWaitDeviceIdle()
                    Destroy()
                    vkDestory()
                    systemDestroy()
                    systemAfterDestroy()
                    return
                }

                ident = android.ALooper_pollAll(!paused ? 0 : -1, nil, &events, cast(^rawptr)&source)
            }

            if (!paused) {
                RenderLoop()
            }
        }
    }
}