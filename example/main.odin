package example

import "core:fmt"
import "core:reflect"
import "../xfit"

is_android :: xfit.is_android

init ::proc() {

}
// update ::proc(dt:f64) {
    
// }
// destroy ::proc() {
    
// }

main :: proc() {
    xfit.xfit_main(init)
}
