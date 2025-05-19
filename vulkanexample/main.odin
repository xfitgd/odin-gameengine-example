package example

import "core:fmt"
import "core:math"
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

bgSndSrc : ^xfit.SoundSrc
bgSnd : ^xfit.Sound

bgSndFileData:[]u8

Init ::proc() {
    renderCmd = xfit.RenderCmd_Init()

    shape: ^xfit.Shape = xfit.AllocObject(xfit.Shape)


    fontFileData:[]u8
    defer delete(fontFileData, context.temp_allocator)

    when xfit.is_android {
        fontFileReadErr : xfit.Android_AssetFileError
        fontFileData, fontFileReadErr = xfit.Android_AssetReadFile("omyu pretty.ttf", context.temp_allocator)
        if fontFileReadErr != .None {
            xfit.panicLog(fontFileReadErr)
        }
    } else {
        fontFileReadErr :os2.Error
        fontFileData, fontFileReadErr = os2.read_entire_file_from_path("omyu pretty.ttf", context.temp_allocator)
        if fontFileReadErr != nil {
            xfit.panicLog(fontFileReadErr)
        }
    }

    freeTypeErr : xfit.FreetypeErr
    font, freeTypeErr = xfit.Font_Init(fontFileData, 0)
    if freeTypeErr != .Ok {
        xfit.panicLog(freeTypeErr)
    }

    //xfit.Font_SetScale(font, 1)

    renderOpt := xfit.FontRenderOpt{
        color = xfit.Point3DwF{1,1,1,1},
        flag = .GPU,
        scale = xfit.PointF{3,3},
    }

    rawText, shapeErr := xfit.Font_RenderString(font, "You And I", renderOpt, context.temp_allocator)
    if shapeErr != .None {
        xfit.panicLog(shapeErr)
    }
    defer xfit.RawShape_Free(rawText, context.temp_allocator)

    xfit.ShapeSrc_InitRaw(&shapeSrc, rawText)

    xfit.Camera_Init(&camera, )
    xfit.Projection_InitMatrixOrthoWindow(&proj, CANVAS_W, CANVAS_H)

    xfit.Shape_Init(shape, xfit.Shape, &shapeSrc, {-0.0, 0, 10}, math.to_radians_f32(45.0), {3, 3}, &camera, &proj,
    pivot = {0.0, 0.0})

    xfit.RenderCmd_AddObject(renderCmd, shape)
    
    xfit.RenderCmd_Show(renderCmd)

    //Sound Test
    when xfit.is_android {
        sndFileReadErr : xfit.Android_AssetFileError
        bgSndFileData, sndFileReadErr = xfit.Android_AssetReadFile("BG.opus", context.allocator)
        if sndFileReadErr != .None {
            xfit.panicLog(sndFileReadErr)
        }
    } else {
        sndFileReadErr :os2.Error
        bgSndFileData, sndFileReadErr = os2.read_entire_file_from_path("BG.opus", context.allocator)
        if sndFileReadErr != nil {
            xfit.panicLog(sndFileReadErr)
        }
    }

    bgSndSrc, _ = xfit.SoundSrc_DecodeSoundMemory(bgSndFileData)
    bgSnd, _ = xfit.SoundSrc_PlaySoundMemory(bgSndSrc, 0.2, true)
}
Update ::proc() {
    
}
Size :: proc() {
    xfit.Projection_UpdateOrthoWindow(&proj, CANVAS_W, CANVAS_H)
}
Destroy ::proc() {
    xfit.ShapeSrc_Deinit(&shapeSrc)
    xfit.IObject_Deinit(xfit.RenderCmd_GetObject(renderCmd, 0))
    xfit.RenderCmd_Deinit(renderCmd)

    xfit.Camera_Deinit(&camera)
    xfit.Projection_Deinit(&proj)

    xfit.SoundSrc_Deinit(bgSndSrc)

    delete(bgSndFileData)
}


entry :: proc() {
     xfit.xfitInit()

    xfit.Init = Init
    xfit.Update = Update
    xfit.Destroy = Destroy
    xfit.Size = Size
    xfit.xfitMain()
}


