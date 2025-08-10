package game

import "core:log"
import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

Resource_Load_Result :: enum {
    Success,
    File_Not_Found,
    Invalid_Format,
    Memory_Error,
}

Resource_Manager :: struct {
    textures:[Texture_ID]rl.Texture,
    base_texture_path: string,
    sounds:[Sound_ID]rl.Sound,
    base_sound_path: string,
    // fonts: [Font_ID]rl.Font,
    // base_font_path: string,
    transparency_color: rl.Color,
}

setup_resource_manager :: proc(rm: ^Resource_Manager) {
    log.info("Setup resource manager...")
    rm.base_texture_path = "assets/"
    rm.base_sound_path = "assets/"
    // rm.base_font_path = "assets/fonts/"
    rm.transparency_color = {43, 255, 213, 255} // teal
}

load_all_assets :: proc(rm: ^Resource_Manager) -> bool {
    log.info("Loading all game assets...")

    texture_success := load_all_textures(rm)
    sound_success := load_all_sounds(rm)
    // font_success := load_all_fonts(rm)
    if texture_success && sound_success {
        log.infof("Asset loading complete")
        return true
    } else {
        log.errorf("Asset loading failed, there were some errors")
        return false
    }
}

load_all_textures :: proc(rm: ^Resource_Manager) -> bool {
    success := true
    for id in Texture_ID {
		result := load_texture(rm, id)
        if result != .Success {
            log.errorf("Failed to load texture %v: %v", id, result)
            success = false
        } 
    }
    return success
}

load_all_sounds :: proc(rm: ^Resource_Manager) -> bool {
    success := true
    for id in Sound_ID {
        result := load_sound(rm, id)
        if result != .Success {
            log.errorf("Failed to load sound %v: %v", id, result)
            success = false
        }
    }
    return success
}

get_name_from_id_texture :: proc(id: Texture_ID) -> string {
    return strings.to_lower(fmt.tprintf(("%v"), id), context.temp_allocator)
}

get_name_from_id_sound :: proc(id: Sound_ID) -> string {
    return strings.to_lower(fmt.tprintf("%v", id), context.temp_allocator)
}

get_name_from_id :: proc {
    get_name_from_id_texture,
    get_name_from_id_sound,
}

// Load a single texture with metadata tracking
load_texture :: proc(rm: ^Resource_Manager, id: Texture_ID) -> Resource_Load_Result {
    filename := get_name_from_id(id)
	filepath := fmt.ctprintf("%v%v.png", rm.base_texture_path, filename)

    image := rl.LoadImage(filepath)
    if image.data == nil {
        return .File_Not_Found
    }
    // Apply transparency processing
    rl.ImageColorReplace(&image, rm.transparency_color, rl.BLANK)
    texture := rl.LoadTextureFromImage(image)
    if texture.id == 0 {
        rl.UnloadImage(image)
        return .Memory_Error
    }
	// rl.SetTextureFilter(texture, .BILINEAR )
    rm.textures[id] = texture
    rl.UnloadImage(image)
    return .Success
}

// TODO: check for file existence before LoadSound
load_sound :: proc(rm: ^Resource_Manager, id: Sound_ID) -> Resource_Load_Result {
    filename := get_name_from_id(id)
	filepath_wav := fmt.ctprintf("%v%v.wav", rm.base_sound_path, filename)
    sound := rl.LoadSound(filepath_wav)
    if sound.stream.buffer == nil {
		filepath_mp3 := fmt.ctprintf("%v%v.mp3", rm.base_sound_path, filename)
		sound = rl.LoadSound(filepath_mp3)
		if sound.stream.buffer == nil {
			return .File_Not_Found
		}
    }
    rm.sounds[id] = sound
    return .Success
}

get_texture :: proc(id: Texture_ID) -> rl.Texture {
    if g.resman == nil {
        log.error("get_texture: resource_manager is nil")
        return {}
    }
    tex := g.resman.textures[id]
    if tex == {} do log.error("Failed to get texture", id)
    return tex
}

get_sound :: proc(id: Sound_ID) -> rl.Sound {
    if g.resman == nil {
        log.error("get_sound: resource_manager is nil")
        return {}
    }
    sound := g.resman.sounds[id]
    if sound == {} do log.error("Failed to get sound", id)
    return sound
}

unload_all_assets :: proc(rm: ^Resource_Manager) {
    log.info("Unloading all assets...")
    for id in Texture_ID {
        rl.UnloadTexture(rm.textures[id])
    }
    for id in Sound_ID {
        rl.UnloadSound(rm.sounds[id])
    }
    // for id in Font_ID {
    //     rl.UnloadFont(rm.fonts[id])
    // }
    log.info("All assets unloaded")
}

// Load all fonts with error handling
// load_all_fonts :: proc(rm: ^Resource_Manager) -> bool {
//     success := true
//     for id in Font_ID {
//         result := load_font(rm, id)
//         if result != .Success {
//             log.errorf("Failed to load font %v: %v", id, result)
//             success = false
//         }
//     }
//     return success
// }

// Load a single font with metadata tracking
// load_font :: proc(rm: ^Resource_Manager, kind: Font_Kind) -> Resource_Load_Result {
//     file_path := get_font_file_path(kind)
//     font := rl.LoadFont(file_path)
//     if font.texture.id == 0 {
//         metadata.load_result = .File_Not_Found
//         return .File_Not_Found
//     }
//     rm.fonts[kind] = font
//     return .Success
// }

// get_font :: proc(rm: ^Resource_Manager, kind: Font_Kind) -> rl.Font {
//     if rm == nil {
//         log.errorf("get_font called with nil Resource_Manager for font: %v", kind)
//         return {} // Return empty font
//     }
//     metadata := rm.font_metadata[kind]
//     if !metadata.is_loaded {
//         log.warnf("Accessing unloaded font: %v", kind)
//         // Return a default/error font if available, or the unloaded font
//     }
//     return rm.fonts[kind]
// }
