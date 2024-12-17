package xfit_system

__ANDROID__ :: #config(__ANDROID__, false)

system_start :: proc() {
    when ODIN_OS == .Linux {
        system_linux_start()
    } else when ODIN_OS == .Windows {
        system_windows_start()
    } else {
        #panic("not support platform")
    }
}