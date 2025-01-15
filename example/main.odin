package example

import "core:fmt"
import "core:reflect"
import "../xfit"

is_android :: xfit.is_android

Init ::proc() {

}
// Update ::proc(dt:f64) {
    
// }
// Destroy ::proc() {
    
// }
AfterDestroy ::proc() {
    
}

main :: proc() {
    xfit.xfitInit()

    xfit.Init = Init
    xfit.xfitMain()
}
