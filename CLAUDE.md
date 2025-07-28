# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an Odin + Raylib game project with hot reloading support. The project is set up as a chess game (based on the repo name) but uses a general game template structure. It supports multiple build targets: development with hot reload, release builds, and web builds.

## Build Commands

- **Hot reload development**: `./build_hot_reload.sh` - Creates `game_hot_reload.bin` and `game.so`/`game.dylib`/`game.dll`. Run the executable and rebuild the script to hot reload changes.
- **Release build**: `./build_release.sh` - Creates optimized release build in `build/release/`
- **Debug build**: `./build_debug.sh` - Creates debuggable build without hot reload
- **Web build**: `./build_web.sh` - Creates web build in `build/web/` (requires Emscripten)
- **Quick tasks**: `./task.sh a` for hot reload build, `./task.sh b` to run the game

## Code Architecture

### Core Structure
- `src/game.odin` - Main game logic, contains `Game_Memory` struct and all core game systems
- `src/main_hot_reload/` - Hot reload executable entry point
- `src/main_release/` - Release build entry point  
- `src/main_web/` - Web build entry point with Emscripten integration

### Key Systems
- **Hot Reload System**: Game state persists in `Game_Memory` struct across DLL reloads
- **Resource Management**: `resource_manager.odin` handles texture and asset loading
- **Audio System**: `audio_manager.odin` for sound effects and music
- **Rendering**: Uses render texture with letterboxing for consistent viewport across window sizes
- **Scene System**: Union-based scene management (currently Play_Scene)

### Game Structure
- `Game_Memory` - Persistent state container for hot reloading
- Global variable `g` points to current `Game_Memory` instance
- Scene-based architecture with input processing per scene
- Entity system with Position, Vec2 types
- AABB and circle collision detection utilities

### Input System
- Global input (debug toggle, exit, reset, music toggle) 
- Scene-specific input processing
- Mouse action enumeration for game interactions

### Platform Support
- Multi-platform build scripts handle different library extensions (.dll/.dylib/.so)
- Web builds use Emscripten with proper asset embedding
- Assets folder automatically copied/embedded for different build types

## Development Workflow

1. Run `./build_hot_reload.sh` once to create initial build
2. Start `./game_hot_reload.bin` 
3. Edit code in `src/game.odin`
4. Run `./build_hot_reload.sh` again to hot reload changes
5. Game state persists across reloads via `Game_Memory`

## Code Style

- Uses tab indentation (size 4) as defined in `.editorconfig`
- Odin naming conventions with snake_case for procedures and variables
- Global shortcuts: `pr` for `fmt.println`, `prf` for `fmt.printfln`
- Type aliases: `Vec2 :: [2]f32`, `Position :: Vec2`