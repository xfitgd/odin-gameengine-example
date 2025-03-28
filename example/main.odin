package example

import "core:fmt"
import "core:reflect"
import "core:os/os2"
import "../xfit"

is_android :: xfit.is_android

renderCmd : ^xfit.RenderCmd
shapeSrc: xfit.ShapeSrc

camera: xfit.Camera
proj: xfit.Projection

CANVAS_W :f32: 1280
CANVAS_H :f32: 720

Init ::proc() {
    renderCmd = xfit.RenderCmd_Init()

    shape: ^xfit.Shape = xfit.AllocObject(xfit.Shape)

    fontFileData, fontFileReadErr := os2.read_entire_file_from_path("SourceHanSerifK-ExtraLight.otf", context.temp_allocator)
    defer delete(fontFileData, context.temp_allocator)
    if fontFileReadErr != nil {
        xfit.panicLog(fontFileReadErr)
    }
    vffData, freeTypeErr ,shapeErr := xfit.Font_ConvertFontFmtToVFF(fontFileData,0)


    font, fontErr := xfit.Font_Init(vffData)

    shapes : xfit.Shapes
    shapes.nPolys = []u32{6}
    shapes.colors = []xfit.Point3DwF{{1,0,0,1}, {1,0,0,1}, {1,0,0,1}, {1,0,0,1}, {1,0,0,1}, {1,0,0,1}}
    shapes.poly = []xfit.PointF{{-100,100}, {-200,-200}, {-200,200}, {-100,-100}, {100,-100}, {100,100}}
    shapes.types = []xfit.CurveType{.Unknown, .Line, .Line, .Line}
    shapeErr = xfit.ShapeSrc_Init(&shapeSrc, &shapes)
    if shapeErr != .None {
        xfit.panicLog("ShapeSrc_Init failed\n")
    }

    xfit.Camera_Init(&camera, )
    xfit.Projection_InitMatrixOrthoWindow(&proj, CANVAS_W, CANVAS_H)

    xfit.Shape_Init(shape, xfit.Shape, &shapeSrc, {0, 0, 0}, 0, {1, 1}, &camera, &proj)

    xfit.RenderCmd_AddObject(renderCmd, shape)
    
    xfit.RenderCmd_Show(renderCmd)
}
Update ::proc() {
    
}
Destroy ::proc() {
    xfit.ShapeSrc_Deinit(&shapeSrc)
    xfit.IObject_Deinit(xfit.RenderCmd_GetObject(renderCmd, 0))
    xfit.RenderCmd_Deinit(renderCmd)

    xfit.Camera_Deinit(&camera)
    xfit.Projection_Deinit(&proj)
}

main :: proc() {
    xfit.xfitInit()

    xfit.Init = Init
    xfit.Update = Update
    xfit.Destroy = Destroy
    xfit.xfitMain()
}
