package vulkanexample

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:math/geometry"
import "core:reflect"
import "core:os/os2"
import "core:engine"
import "core:engine/font"
import "core:engine/sound"
import "core:debug/trace"

is_android :: engine.is_android

renderCmd : ^engine.RenderCmd
shapeSrc: engine.ShapeSrc

camera: engine.Camera
proj: engine.Projection

CANVAS_W :f32: 1280
CANVAS_H :f32: 720

ft:^font.Font

bgSndSrc : ^sound.SoundSrc
bgSnd : ^sound.Sound

bgSndFileData:[]u8

Init ::proc() {
    renderCmd = engine.RenderCmd_Init()

    shape: ^engine.Shape = engine.AllocObject(engine.Shape)


    fontFileData:[]u8
    defer delete(fontFileData, context.temp_allocator)

    when engine.is_android {
        fontFileReadErr : engine.Android_AssetFileError
        fontFileData, fontFileReadErr = engine.Android_AssetReadFile("omyu pretty.ttf", context.temp_allocator)
        if fontFileReadErr != .None {
            trace.panic_log(fontFileReadErr)
        }
    } else {
        fontFileReadErr :os2.Error
        fontFileData, fontFileReadErr = os2.read_entire_file_from_path("omyu pretty.ttf", context.temp_allocator)
        if fontFileReadErr != nil {
            trace.panic_log(fontFileReadErr)
        }
    }

    freeTypeErr : font.FreetypeErr
    ft, freeTypeErr = font.Font_Init(fontFileData, 0)
    if freeTypeErr != .Ok {
        trace.panic_log(freeTypeErr)
    }

    //engine.Font_SetScale(font, 1)

    renderOpt := font.FontRenderOpt{
        color = linalg.Point3DwF{1,1,1,1},
        flag = .GPU,
        scale = linalg.PointF{3,3},
    }

    rawText, shapeErr := font.Font_RenderString(ft, "You And I", renderOpt, context.temp_allocator)
    if shapeErr != .None {
        trace.panic_log(shapeErr)
    }
    defer geometry.RawShape_Free(rawText, context.temp_allocator)

    engine.ShapeSrc_InitRaw(&shapeSrc, rawText)

    engine.Camera_Init(&camera, )
    engine.Projection_InitMatrixOrthoWindow(&proj, CANVAS_W, CANVAS_H)

    engine.Shape_Init(shape, engine.Shape, &shapeSrc, {-0.0, 0, 10}, math.to_radians_f32(45.0), {3, 3}, &camera, &proj,
    pivot = {0.0, 0.0})

    engine.RenderCmd_AddObject(renderCmd, shape)
    
    engine.RenderCmd_Show(renderCmd)

    //Sound Test
    when engine.is_android {
        sndFileReadErr : engine.Android_AssetFileError
        bgSndFileData, sndFileReadErr = engine.Android_AssetReadFile("BG.opus", context.allocator)
        if sndFileReadErr != .None {
            trace.panic_log(sndFileReadErr)
        }
    } else {
        sndFileReadErr :os2.Error
        bgSndFileData, sndFileReadErr = os2.read_entire_file_from_path("BG.opus", context.allocator)
        if sndFileReadErr != nil {
            trace.panic_log(sndFileReadErr)
        }
    }

    bgSndSrc, _ = sound.SoundSrc_DecodeSoundMemory(bgSndFileData)
    bgSnd, _ = sound.SoundSrc_PlaySoundMemory(bgSndSrc, 0.2, true)
}
Update ::proc() {
    
}
Size :: proc() {
    engine.Projection_UpdateOrthoWindow(&proj, CANVAS_W, CANVAS_H)
}
Destroy ::proc() {
    engine.ShapeSrc_Deinit(&shapeSrc)
    engine.IObject_Deinit(engine.RenderCmd_GetObject(renderCmd, 0))
    engine.RenderCmd_Deinit(renderCmd)

    engine.Camera_Deinit(&camera)
    engine.Projection_Deinit(&proj)

    sound.SoundSrc_Deinit(bgSndSrc)

    delete(bgSndFileData)
}


main :: proc() {
    engine.Init = Init
    engine.Update = Update
    engine.Destroy = Destroy
    engine.Size = Size
    engine.engineMain()
}


