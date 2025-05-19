package example

import "../xfit"
import "../xfit/external/android"
import "base:runtime"

when xfit.is_android {
    @export android_main :: proc "c" (state : ^android.android_app) {
        context = runtime.default_context()
        xfit.__androidInit(state)
        #force_inline entry()
    }
} else {
    main :: proc() {
        #force_inline entry()
    }
}
