package vulkanexample

import "core:fmt"
import "core:mem"
import "core:thread"
import "core:math"
import "core:math/rand"
import "core:math/linalg"
import "core:reflect"
import "core:os/os2"
import "vendor:engine"
import "vendor:engine/font"
import "vendor:engine/sound"
import "vendor:engine/geometry"
import "vendor:engine/gui"
import "core:debug/trace"

is_android :: engine.is_android

renderCmd : ^engine.RenderCmd

shapeSrc: engine.ShapeSrc
texture:engine.Texture

camera: engine.Camera
proj: engine.Projection

CANVAS_W :f32: 1280
CANVAS_H :f32: 720

ft:^font.Font

bgSndSrc : ^sound.SoundSrc
bgSnd : ^sound.Sound

bgSndFileData:[]u8


GUI_Image_Init :: proc(self:^GUI_Image, src:^engine.Texture,
camera:^engine.Camera, projection:^engine.Projection,
colorTransform:^engine.ColorTransform = nil) {
    engine.Image_Init2(auto_cast self, GUI_Image, src, camera, projection, colorTransform)

    gui.gui_component_size(self, &self.com)
}


GUI_Image :: struct {
    using _:engine.Image,
    com:gui.gui_component,
}

Init ::proc() {
    renderCmd = engine.RenderCmd_Init()

    engine.Camera_Init(&camera, )
    engine.Projection_InitMatrixOrthoWindow(&proj, CANVAS_W, CANVAS_H)

    //Font Test
    shape: ^engine.Shape = engine.AllocObjectNonZeroed(engine.Shape)

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

    rawText, shapeErr := font.Font_RenderString(ft, "놀면서 개발", renderOpt, context.temp_allocator)
    if shapeErr != .None {
        trace.panic_log(shapeErr)
    }
    defer geometry.RawShape_Free(rawText, context.temp_allocator)

    engine.ShapeSrc_InitRaw(&shapeSrc, rawText)

    engine.Shape_Init(shape, engine.Shape, &shapeSrc, {-0.0, 0, 10}, &camera, &proj, math.to_radians_f32(45.0), {3, 3},
    pivot = {0.0, 0.0})

    engine.RenderCmd_AddObject(renderCmd, shape)

    //Sound Test
    // when engine.is_android {
    //     sndFileReadErr : engine.Android_AssetFileError
    //     bgSndFileData, sndFileReadErr = engine.Android_AssetReadFile("BG.opus", context.allocator)
    //     if sndFileReadErr != .None {
    //         trace.panic_log(sndFileReadErr)
    //     }
    // } else {
    //     sndFileReadErr :os2.Error
    //     bgSndFileData, sndFileReadErr = os2.read_entire_file_from_path("BG.opus", context.allocator)
    //     if sndFileReadErr != nil {
    //         trace.panic_log(sndFileReadErr)
    //     }
    // }

    // bgSndSrc, _ = sound.SoundSrc_DecodeSoundMemory(bgSndFileData)
    // bgSnd, _ = sound.SoundSrc_PlaySoundMemory(bgSndSrc, 0.2, true)

    //Image Test
    pngD :^engine.png_decoder = new(engine.png_decoder, engine.defAllocator())

    imgData, errCode := engine.image_converter_load_file(pngD, "panda.png", .RGBA)
    if errCode != nil {
        trace.panic_log(errCode)
    }
    engine.Texture_Init(&texture, engine.image_converter_width(pngD), engine.image_converter_height(pngD), imgData)

    img: ^GUI_Image = engine.AllocObject(GUI_Image)
    img.com.gui_scale = {1.0, 1.0}
    img.com.gui_rotation = math.to_radians_f32(45.0)
    img.com.gui_align_x = .left
    img.com.gui_pos.x = 200.0
    
    GUI_Image_Init(img, &texture,  &camera, &proj)
    

    engine.RenderCmd_AddObject(renderCmd, img)

    //Show
    engine.RenderCmd_Show(renderCmd)

    WaitThread :: proc(data:rawptr) {
        engine.GraphicsWaitAllOps()

        engine.image_converter_deinit(cast(^engine.png_decoder)data)
        free(data, engine.defAllocator())
    }
    thread.create_and_start_with_data(pngD, WaitThread, self_cleanup = true)

    // engine.GraphicsWaitAllOps()

    // engine.webp_decoder_deinit(webpD)
}
Update ::proc() {
}
Size :: proc() {
    engine.Projection_UpdateOrthoWindow(&proj, CANVAS_W, CANVAS_H)
    
    gui_img := (^GUI_Image)(engine.RenderCmd_GetObject(renderCmd, 1))

    gui.gui_component_size(gui_img, &gui_img.com)
}
Destroy ::proc() {
    engine.ShapeSrc_Deinit(&shapeSrc)
    engine.Texture_Deinit(&texture)
    len := engine.RenderCmd_GetObjectLen(renderCmd)
    for i in 0..<len {
        engine.IObject_Deinit(engine.RenderCmd_GetObject(renderCmd, i))
    }
    engine.RenderCmd_Deinit(renderCmd)

    engine.Camera_Deinit(&camera)
    engine.Projection_Deinit(&proj)

    //sound.SoundSrc_Deinit(bgSndSrc)
    //delete(bgSndFileData)

    //engine.webp_decoder_deinit(&webpD)
}


main :: proc() {
    engine.Init = Init
    engine.Update = Update
    engine.Destroy = Destroy
    engine.Size = Size
    engine.engineMain(windowWidth = int(CANVAS_W), windowHeight = int(CANVAS_H))
}


