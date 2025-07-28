package game

import "core:log"
import rl "vendor:raylib"

Audio_Manager :: struct {
    master_volume: f32,
	muted: bool,
    sfx_volume: f32,
    music_volume: f32,
    current_music: Maybe(Sound_ID),
    music_state: Music_State,
    music_loop: bool,
}

Music_State :: enum {
    Stopped,
    Playing,
    Paused,
}

// Initialize audio manager with default settings
init_audio_manager :: proc() -> Audio_Manager {
    return Audio_Manager{
        master_volume = 1.0,
        sfx_volume = 1.0,
        music_volume = 1.0,
        muted = false,
        current_music = nil,
        music_state = .Stopped,
        music_loop = true,
    }
}

// Set master volume (0.0 to 1.0)
set_master_volume :: proc(volume: f32) {
	am := g.audman
    am.master_volume = clamp(volume, 0.0, 1.0)
    rl.SetMasterVolume(am.master_volume)
}

// Set SFX volume (0.0 to 1.0)
set_sfx_volume :: proc(volume: f32) {
	am := g.audman
    am.sfx_volume = clamp(volume, 0.0, 1.0)
}

// Set music volume (0.0 to 1.0)
set_music_volume :: proc(volume: f32) {
	am := g.audman
    am.music_volume = clamp(volume, 0.0, 1.0)
    if current_music := am.current_music; current_music != nil {
        sound := get_sound(current_music.?)
        rl.SetSoundVolume(sound, am.music_volume * am.master_volume)
    }
}

// Toggle mute state
toggle_mute :: proc() {
	set_mute(!g.audman.muted)
}

// Set mute state directly
set_mute :: proc(muted: bool) {
	am := g.audman
    am.muted = muted
    if am.muted {
        rl.SetMasterVolume(0.0)
    } else {
        rl.SetMasterVolume(am.master_volume)
    }
}

// Play a sound effect with volume control
play_sfx :: proc(id: Sound_ID) {
	am := g.audman
    if am.muted do return
    sound := get_sound(id)
    rl.SetSoundVolume(sound, am.sfx_volume * am.master_volume)
    rl.PlaySound(sound)
}

// Start playing music (stops current music if playing)
play_music :: proc(id: Sound_ID, loop: bool = true) {
	am := g.audman
    if am.muted do return

    // Stop current music if playing
    stop_music()

    am.current_music = id
    am.music_loop = loop
    am.music_state = .Playing

    sound := get_sound(id)
    rl.SetSoundVolume(sound, am.music_volume * am.master_volume)
    rl.PlaySound(sound)

    log.debugf("Started playing music: %v (loop: %v)", id, loop)
}

// Stop the current music
stop_music :: proc() {
	am := g.audman
    if current_music := am.current_music; current_music != nil {
        sound := get_sound(current_music.?)
        rl.StopSound(sound)
        log.debugf("Stopped music: %v", current_music)
    }
    am.current_music = nil
    am.music_state = .Stopped
}

// Pause the current music
pause_music :: proc() {
	am := g.audman
    if current_music := am.current_music; current_music != nil && am.music_state == .Playing {
        sound := get_sound(current_music.?)
        rl.PauseSound(sound)
        am.music_state = .Paused
        log.debugf("Paused music: %v", current_music)
    }
}

// Resume the current music
resume_music :: proc() {
	am := g.audman
    if current_music := am.current_music; current_music != nil && am.music_state == .Paused {
        sound := get_sound(current_music.?)
        rl.ResumeSound(sound)
        am.music_state = .Playing
        log.debugf("Resumed music: %v", current_music)
    }
}

// Check if music is currently playing
is_music_playing :: proc() -> bool {
	am := g.audman
    return am.music_state == .Playing
}

// Check if music is paused
is_music_paused :: proc() -> bool {
	am := g.audman
    return am.music_state == .Paused
}

// Get current music ID (if any)
get_current_music :: proc() -> Maybe(Sound_ID) {
	am := g.audman
    return am.current_music
}

// Update audio manager - call this every frame to handle music looping
update_audio_manager :: proc() {
	am := g.audman
    // Handle music looping
    if current_music := am.current_music; current_music != nil && am.music_state == .Playing {
        sound := get_sound(current_music.?)

        // If music stopped playing and we want to loop it
        if !rl.IsSoundPlaying(sound) && am.music_loop {
            rl.PlaySound(sound)
        } else if !rl.IsSoundPlaying(sound) {
            // Music finished and we don't want to loop
            am.current_music = nil
            am.music_state = .Stopped
        }
    }
}

// Convenience function to stop a specific sound effect
stop_sfx :: proc(id: Sound_ID) {
    sound := get_sound(id)
    rl.StopSound(sound)
}

// Check if a specific sound is playing
is_sfx_playing :: proc(id: Sound_ID) -> bool {
    sound := get_sound(id)
    return rl.IsSoundPlaying(sound)
}

// Restart a sound effect (stop if playing, then play)
restart_sfx :: proc(id: Sound_ID) {
    if is_sfx_playing(id) {
        stop_sfx(id)
    }
    play_sfx(id)
}
