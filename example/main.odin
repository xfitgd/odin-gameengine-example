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

font:^xfit.Font

Init ::proc() {
    renderCmd = xfit.RenderCmd_Init()

    shape: ^xfit.Shape = xfit.AllocObject(xfit.Shape)

    //SourceHanSerifK-ExtraLight.otf
    //JSDongkang-Regular.ttf
    fontFileData, fontFileReadErr := os2.read_entire_file_from_path("SourceHanSerifK-ExtraLight.otf", context.temp_allocator)
    defer delete(fontFileData, context.temp_allocator)
    if fontFileReadErr != nil {
        xfit.panicLog(fontFileReadErr)
    }

    freeTypeErr : xfit.FreetypeErr
    font, freeTypeErr = xfit.Font_Init(fontFileData)
    if freeTypeErr != .Ok {
        xfit.panicLog(freeTypeErr)
    }

    //xfit.Font_SetScale(font, 1)

    renderOpt := xfit.FontRenderOpt{
        color = xfit.Point3DwF{1,1,1,1},
        flag = .GPU,
        scale = xfit.PointF{3,3},
    }

    rawText := xfit.Font_RenderString(font, "안녕하세요, 반갑습니다.\n안녕히가세요.", renderOpt)
    defer xfit.RawShape_Free(rawText)

    xfit.ShapeSrc_InitRaw(&shapeSrc, rawText)

    xfit.Camera_Init(&camera, )
    xfit.Projection_InitMatrixOrthoWindow(&proj, CANVAS_W, CANVAS_H)

    xfit.Shape_Init(shape, xfit.Shape, &shapeSrc, {-600, 0, 0}, 0, {1, 1}, &camera, &proj)

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
