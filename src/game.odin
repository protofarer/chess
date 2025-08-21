package game

import "core:fmt"
import "core:log"
import "core:math/linalg"
import "core:math"
import "core:time"
import "core:time/datetime"
import "core:time/timezone"
import "core:strings"
import "core:os"
import sa "core:container/small_array"

import rl "vendor:raylib"

pr :: fmt.println
prf :: fmt.printfln

Void :: struct{}
Vec2 :: [2]f32
Vec2i :: [2]i32
Position :: Vec2i
Rec :: rl.Rectangle

LOGICAL_SCREEN_HEIGHT :: 360
LOGICAL_SCREEN_WIDTH :: 540
RENDER_TEXTURE_SCALE :: 2

WINDOW_TITLE :: "Odin Gamejam Template"
WINDOW_W :: 1600
WINDOW_H :: 900
TICK_RATE :: 60

BACKGROUND_COLOR :: rl.GRAY
DARK_TILE_COLOR :: rl.Color{40,160,40,255} // medium green
LIGHT_TILE_COLOR :: rl.WHITE

WHITE_PIECE_COLOR :: rl.RAYWHITE
BLACK_PIECE_COLOR :: rl.DARKGRAY

BOARD_LENGTH :: 8

Game_Memory :: struct {
	app_state: App_State,
	debug: bool,
	resman: Resource_Manager,
	render_texture: rl.RenderTexture,
	scene: Scene,
	audman: Audio_Manager,
	is_music_enabled: bool,
	using board: Board,
	time: Game_Time,
	promotion_piece_data: [4]Promotion_Piece_Data
}

Game_Time :: struct {
	local_timezone: ^datetime.TZ_Region,
	game_start_datetime: datetime.DateTime,
	game_end_datetime: datetime.DateTime,
	game_start: time.Tick,
	game_duration: time.Duration,
	turn_start: time.Tick,
	turn_duration: time.Duration,
	players_duration: [Player_Color]time.Duration,
}

MAX_SMALL_ARRAY_CAPTURE_COUNT :: 16
// corresponds to [a-h][1-8]
// contains board-specific gameplay state
Board :: struct {
	tiles: Tiles,
	n_turns: i32,
	current_player: Player_Color,
	is_white_bottom: bool, // predom for multiplayer

	last_double_move_end_position: Position,
	last_double_move_turn: i32,

	captures: [Player_Color]sa.Small_Array(MAX_SMALL_ARRAY_CAPTURE_COUNT, Piece_Type),
	points: [Player_Color]i32,

	// TODO: bit_set
	is_check: bool,
	is_checkmate: bool,
	is_draw: bool,
	is_dead_position: bool,

	draw_offered: [Player_Color]i32, // offered on turn number

	turn_phase: Turn_Phase,

	has_board_evaluated_this_turn: bool,
	can_kingside_castle: [Player_Color]bool,
	can_queenside_castle: [Player_Color]bool,

	threatened_positions: sa.Small_Array(MAX_ELEMENTS_FOR_MOVE_RESULTS, Position),
	legal_moves: Move_Results,
	gameover: bool,

	tile_pos_to_promote: Maybe(Position),

	show_move_overlay: bool,
	show_help: bool,
	message: string,
	dead_position_message: string,
}

Tiles :: [BOARD_LENGTH][BOARD_LENGTH]Tile

App_State :: enum {
	Running,
	Exit
}

Scene :: union {
	// Menu_Scene,
	Play_Scene,
	// End_Game_Scene,
}

Play_Scene :: struct {
}

Sprite :: struct {
	texture_id: Texture_ID,
}

Piece_Type :: enum {
	None,
	Pawn,
	Rook,
	Knight,
	Bishop,
	Queen,
	King,
}

Tile :: union {
	Piece,
	Empty_Tile
}

Piece :: struct {
	type: Piece_Type,
	color: Piece_Color,
	has_moved: bool,
}

Empty_Tile :: Void

Piece_Color :: enum u8 {
	White, Black,
}


Player_Color :: Piece_Color

Selected_Piece_Data :: struct {
	position: Position,
	legal_moves: Move_Results,
}

PIECE_POINTS := [Piece_Type]i32{
	.None = 0,
	.Pawn = 1,
	.Knight = 3,
	.Bishop = 3,
	.Rook = 5,
	.Queen = 9,
	.King = 0,
}

Turn_Phase :: union #no_nil {
	Eval, // start here
	Try_Move, // loop until legal move
	Choose_Promotion_Piece, // select promotion piece
	End, // ends here
}

Eval :: distinct Void
Try_Move :: struct {
	selected_piece: Maybe(Selected_Piece_Data),
}
Choose_Promotion_Piece :: distinct Void
End :: distinct Void

g: ^Game_Memory

// Run once: allocate, set global variable values used like constants
setup :: proc() -> bool {
	g = new(Game_Memory)
	if g == nil {
		log.error("Failed to allocate game memory")
		return false
	}

	rl.InitAudioDevice() // before resman init
	if !rl.IsAudioDeviceReady() {
		log.warn("Failed to initialize audio device.")
	}
	audman := init_audio_manager()

	resman: Resource_Manager
	setup_resource_manager(&resman)
	load_all_assets(&resman)

	gui_style_file := "assets/style_amber.rgs"
	if os.exists(gui_style_file) {
		rl.GuiLoadStyle(strings.clone_to_cstring(gui_style_file))
	} else {
		log.warn("Failed to load GUI style file, using default style")
	}

	rl.SetMouseCursor(.POINTING_HAND)
	update_mouse_transform()

	g^ = Game_Memory {
		resman = resman,
		render_texture = rl.LoadRenderTexture(
			LOGICAL_SCREEN_WIDTH * RENDER_TEXTURE_SCALE, 
			LOGICAL_SCREEN_HEIGHT * RENDER_TEXTURE_SCALE
		),
		audman = audman,
	}

	setup_promotion_piece_data(g.promotion_piece_data[:])

	return true
}

// clear collections, set initial values, Game_Memory already "setup"
init :: proc() {
	if g == nil {
		log.error("Failed to initialize app state, Game_Memory is nil (has not been setup)")
		// TODO: is return correct op?
		return
	}
	g.app_state = .Running
	g.debug = false
	g.scene = Play_Scene{}
	g.is_music_enabled = true
	g.board = init_board()

	// TEST BOARDS
	// g.board = test_init_white_checked_board()
	// g.board = test_init_black_checked_board()
	// g.board = test_init_trapped_king_board()
	// g.board = test_init_board_king_cannot_capture_check()
	// g.board = test_init_board_king_threatening_ray()
	// g.board = test_init_white_checkmated_board()
	// g.board = test_init_board_sparse()
	// g.board = test_init_board_castle_allow()
	// g.board = test_init_board_castle_threatened()
	// g.board = test_init_board_castle_blocked()
	// g.board = test_init_board_king_v_king()
	// g.board = test_init_board_king_v_king_bishop()
	// g.board = test_init_board_king_knight_v_king()
	// g.board = test_init_board_king_v_king_knight()
	// g.board = test_init_board_king_bishop_v_king_bishop_same_color_bishop_black()
	// g.board = test_init_board_king_bishop_v_king_bishop_same_color_bishop_white()
	g.board = test_init_board_promotion_white()
	// g.board = test_init_board_promotion_black()

	// TEST CAPTURES
	init_test_captures()

	 // name == "America/New York"
	if local_timezone, ok_timezone := timezone.region_load("local"); ok_timezone {
		g.time.local_timezone = local_timezone
	} else {
		log.warn("Failed to load local region for timezone")
	}

	g.time.game_start_datetime = get_datetime_now()
	g.time.game_start = time.tick_now()
	g.time.game_duration = 0
	g.time.turn_start = time.tick_now()
	g.time.turn_duration = 0
	g.time.players_duration = {}

	// In local play (same machine) Player White is always bot.
	g.is_white_bottom = true

	play_sfx(.New_Game)
}

eval_promotion :: proc(board: ^Board) -> bool {
	// if pawn in promotion row -> Post_Move
	// check promotion row for pawns. Can only be 1 pawn to promote, logically.
	promotion_row_index := g.current_player == .White ?  BOARD_LENGTH - 1 : 0
	for tile, x in g.board.tiles[promotion_row_index] {
		piece, is_piece := tile.(Piece)
		if is_piece && piece.type == .Pawn && piece.color == g.current_player {
			g.board.tile_pos_to_promote = Position{i32(x),i32(promotion_row_index)}
		}
	}
	if pos, ok := g.tile_pos_to_promote.(Position); ok {
		return true
	} 
	return false
}

update :: proc() {
	if rl.IsWindowResized() {
		update_mouse_transform()
	}
	update_audio_manager()
	process_global_input()
	if g.board.gameover {
		// TODO: draw results, play sounds
		return
	}
	// next_scene: Maybe(Scene) = nil
	switch &s in g.scene {
	case Play_Scene:
		switch v in g.board.turn_phase {

		case Eval:
			eval_board(&g.board)
			g.board.turn_phase = Try_Move{}

		// aka read and evaluate player input. aka Player_Action
		case Try_Move:
			action := process_play_input(&s)
			switch action {
			case .Toggle_Move_Overlay:
				toggle_move_overlay()
				log.debug("Toggled move overlay")
				play_sfx(.Button_Click)
				return

			case .Toggle_Help:
				toggle_help()
				log.debug("Toggled help modal")
				play_sfx(.Button_Click)
				return

			case .Left_Click_Board:
				handle_board_click()

			case .None:
			}

		case Choose_Promotion_Piece:
			if pos_to_promote, ok_pos := g.board.tile_pos_to_promote.(Position); ok_pos {
				is_left_mouse_clicked := rl.IsMouseButtonPressed(.LEFT)
				for data, i in g.promotion_piece_data {
					if is_left_mouse_clicked && is_mouse_over_rect(data.rect.x, data.rect.y, data.rect.width, data.rect.height) {
						piece_type := data.piece_type
						piece_color := g.current_player
						log.debug("Clicked on promote piece type:", piece_type)
						set_tile(&g.board.tiles, pos_to_promote, Piece{
							type = piece_type, 
							color = piece_color, 
							has_moved = true
						})
						g.board.tile_pos_to_promote = nil

						play_sfx(.Piece_Travel)
						log.debug("Promoted pawn to", piece_type)
						g.board.turn_phase = End{}
					}
				}
			} else {
				g.board.turn_phase = End{}
			}

		case End:
			end_turn(&g.board, &g.time)
			g.board.turn_phase = Eval{}
		}

		g.time.game_duration = time.tick_since(g.time.game_start)
		g.time.turn_duration = time.tick_since(g.time.turn_start)
	}
}

draw :: proc() {
	begin_letterbox_rendering()

	switch &s in g.scene {
	case Play_Scene:
		draw_board_tiles()

		if try_move_data, is_phase_try_move := g.board.turn_phase.(Try_Move); is_phase_try_move {
			selected_piece, ok_selected_piece := try_move_data.selected_piece.?
			if ok_selected_piece {
				selected_piece_tile_pos := selected_piece.position
				// Highlight selected piece
				draw_tile_border(selected_piece_tile_pos, rl.BLUE)

				if  g.board.show_move_overlay {
					draw_selected_piece_move_overlay(&selected_piece)
				}
			}
		}


		draw_pieces_to_board(g.board.tiles)
		if g.board.is_check {
			draw_check_overlay(g.board.tiles, g.board.current_player)
		}
		if g.debug {
			draw_debug_board_overlay()
		}
	}


	// rl.BeginMode2D(ui_camera())
		draw_ui()
	// rl.EndMode2D()

	end_letterbox_rendering()

	if g.debug {
		draw_debug_overlay()
	}

	rl.EndDrawing()
}

draw_ui :: proc() {
	// NB: text size min is 10, steps to 11, 12
	// Top Status Bar
	{
		topbar_width: f32 = LOGICAL_SCREEN_WIDTH
		topbar_height: f32 = TOPBAR_HEIGHT
		rl.GuiStatusBar({0,0,topbar_width, topbar_height}, "")
		BUTTON_WIDTH :: 70
		BUTTON_HEIGHT :: 15
		y: f32 = 4
		x: f32 = 5
		if rl.GuiButton({x, y, BUTTON_WIDTH, BUTTON_HEIGHT}, "New Game") {
			log.debug("Click New Game")
			play_sfx(.Button_Click)
			game_reset()
		}
		x += 75
		if rl.GuiButton({x,y,BUTTON_WIDTH, BUTTON_HEIGHT}, "Draw") {
			log.debug("Click Draw")
			g.draw_offered[g.current_player] = g.n_turns
			g.turn_phase = End{}
			play_sfx(.Button_Click)
		}
		x += 75
		if rl.GuiButton({x,y,15,BUTTON_HEIGHT}, "#193#") {
			log.debug("Click Help")
			g.show_help = true
			play_sfx(.Button_Click)
		}

		x += 70
		rl.GuiDrawIcon(.ICON_CLOCK, i32(x-20),i32(y-2),1,rl.WHITE)

		rl.DrawText(make_duration_display_string(get_game_duration()), i32(x), 7, 11, rl.WHITE)
		x += 80
		rl.DrawText(fmt.ctprintf("Turn: %v", g.board.n_turns), i32(x), 7, 11, rl.WHITE)

		if rl.GuiButton({465,y,BUTTON_WIDTH, BUTTON_HEIGHT}, "Exit") {
			log.debug("Click Exit")
			play_sfx(.Button_Click)
			g.app_state = .Exit
		}


		// centering logic
		// title_width := rl.MeasureText(fmt.ctprint(title), 32)
		// rl.DrawText(fmt.ctprint(title), panel_x + i32((panel_width - title_width) / 2), panel_y + 20, 32, rl.YELLOW)
		topbar_message := fmt.ctprintf("%v %v", g.message, g.dead_position_message)
		topbar_message_width := rl.MeasureText(topbar_message, 8)
		rl.DrawText(topbar_message, i32((i32(topbar_width) - topbar_message_width)/2), 27, 8, rl.RED)
	}

	draw_player_panel :: proc(panel_bounds: Rec, player_color: Player_Color, current_player: Player_Color, title: string, player_total_duration: time.Duration, turn_duration: time.Duration, captures: []Piece_Type, is_check: bool) {
		ygap :: 22
		PANEL_BORDER_THICKNESS :: 2
		is_current_player := player_color == current_player

		rl.GuiPanel(panel_bounds, nil)
		if is_current_player {
			rl.DrawRectangleLinesEx(panel_bounds, PANEL_BORDER_THICKNESS, rl.GREEN)
		} else {
			rl.DrawRectangleLinesEx(panel_bounds, PANEL_BORDER_THICKNESS, rl.LIGHTGRAY)
		}
		x0 := panel_bounds.x
		y0 := panel_bounds.y

		x := x0 + 5
		y := y0 + 5
		rl.GuiLabel({x, y, panel_bounds.width, 10}, strings.clone_to_cstring(title))

		y += 15
		cstr_player_duration := make_duration_display_string(player_total_duration)
		rl.GuiLabel({x, y, 100, 10}, cstr_player_duration)

		if is_current_player {
			y += 15
			cstr_turn_duration := make_duration_display_string(turn_duration)
			cstr_player_turn_duration_text := fmt.ctprintf("+%v", cstr_turn_duration)
			rl.GuiLabel({x, y, 100, 10}, cstr_player_turn_duration_text)

			if g.is_check {
				y += 15
				rl.DrawText("CHECK", i32(x + 50), i32(y0 + 5), 10, rl.RED)
			}
		}

		// Draw captured pieces from bottom up
		xcap :i32= i32(x0 + 10)
		ycap :i32= i32(panel_bounds.y + panel_bounds.height) - 30 * 9
		for piece_type,i in captures {
			if i % 8 == 0 && i > 0 {
				 xcap += 40
				 ycap -= 8 * ygap
			}
			ycap += ygap
			draw_piece_sprite({xcap, ycap}, 0.8, piece_type, get_other_player_color(player_color))
		}
	}

	// White Panel (Left)
	turn_duration := get_turn_duration()
	white_panel_bounds := LEFT_PANEL_BOUNDS
	white_total_duration := get_player_duration(.White)
	draw_player_panel(white_panel_bounds, .White, g.current_player, "White", white_total_duration, turn_duration, sa.slice(&g.board.captures[.White]), g.is_check)

	// Black Panel (Right)
	black_panel_bounds := RIGHT_PANEL_BOUNDS
	black_total_duration := get_player_duration(.Black)
	draw_player_panel(black_panel_bounds, .Black, g.current_player, "Black", black_total_duration, turn_duration, sa.slice(&g.board.captures[.Black]), g.is_check)

	if _, ok := g.turn_phase.(Choose_Promotion_Piece); ok {
		draw_promotion_piece_frame()
	}

	if g.show_help {
		draw_help_modal()
	}

	// Draw Checkmate / Gameover state
	if g.gameover {
		if g.is_checkmate {
			winner := get_other_player_color(g.current_player)
			t := fmt.ctprintf("Checkmate! %v wins!", winner)
			rl.DrawText(t,140,180, 24, rl.RED)
		} else if g.is_draw {
			t := fmt.ctprintf("- Draw -")
			rl.DrawText(t, 250,180, 24, rl.RED)

		}

	}
}

@(export)
game_update :: proc() {
	update()
	draw()
	free_all(context.temp_allocator)
}

@(export)
game_init_window :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(WINDOW_W, WINDOW_H, WINDOW_TITLE)
	rl.SetWindowPosition(10, 125)
	rl.SetTargetFPS(TICK_RATE )
	rl.SetExitKey(nil)
}

@(export)
game_init :: proc() {
	log.info("Initializing game...")

	 // runs once
	if !setup() {
		log.error("Setup failed, cannot run game")
		game_shutdown()
		game_shutdown_window()
		return
	}
	init() // run after setup, then on game reset
	game_hot_reloaded(g)
}

@(export)
game_should_run :: proc() -> bool {
	when ODIN_OS != .JS {
		// Never run this proc in browser. It contains a 16 ms sleep on web!
		if rl.WindowShouldClose() {
			return false
		}
	}
	return g.app_state != .Exit
}

@(export)
game_shutdown :: proc() {
	free(g.time.local_timezone)
	unload_all_assets(&g.resman)
	rl.UnloadRenderTexture(g.render_texture)
	free(g)
}

@(export)
game_shutdown_window :: proc() {
	rl.CloseAudioDevice()
	rl.CloseWindow()
}

@(export)
game_memory :: proc() -> rawptr {
	return g
}

@(export)
game_memory_size :: proc() -> int {
	return size_of(Game_Memory)
}

@(export)
game_hot_reloaded :: proc(mem: rawptr) {
	g = (^Game_Memory)(mem)

	// Here you can also set your own global variables. A good idea is to make
	// your global variables into pointers that point to something inside `g`.
}

@(export)
game_force_reload :: proc() -> bool {
	return rl.IsKeyPressed(.F5)
}

@(export)
game_force_restart :: proc() -> bool {
	return rl.IsKeyPressed(.R)
}

// In a web build, this is called when browser changes size. Remove the
// `rl.SetWindowSize` call if you don't want a resizable game.
game_parent_window_size_changed :: proc(w, h: int) {
	rl.SetWindowSize(i32(w), i32(h))
}

game_reset :: proc() {
	init()
}

///////////////////////////////////////////////////////////////////////////////
// Global Input
///////////////////////////////////////////////////////////////////////////////

Global_Input :: enum {
	Toggle_Debug,
	Exit,
	Exit2,
	Reset,
	Toggle_Music,
}

GLOBAL_INPUT_LOOKUP := [Global_Input]rl.KeyboardKey{
	.Toggle_Debug = .GRAVE,
	.Exit = .ESCAPE,
	.Exit2 = .Q,
	.Reset = .R,
	.Toggle_Music = .M,
}

process_global_input :: proc() {
	input: bit_set[Global_Input]
	for key, input_ in GLOBAL_INPUT_LOOKUP {
		switch input_ {
		case .Toggle_Debug, .Exit, .Exit2, .Toggle_Music, .Reset:
			if rl.IsKeyPressed(key) {
				input += {input_}
			}
		}
	}
    if .Toggle_Debug in input {
        g.debug = !g.debug
    } else if .Exit in input || .Exit2 in input {
		g.app_state = .Exit
    } else if .Reset in input {
		game_reset()
    } else if .Toggle_Music in input {
		toggle_music()
    }
}

///////////////////////////////////////////////////////////////////////////////
// Play Scene
///////////////////////////////////////////////////////////////////////////////

// TODO: mouse play input, see randy and simpler approaches

Play_Action :: enum {
	None,
	Left_Click_Board,
	Toggle_Move_Overlay,
	Toggle_Help,
}

is_mouse_over_board :: proc() -> bool {
	return is_mouse_over_rect(BOARD_BOUNDS.x, 
							  BOARD_BOUNDS.y, 
							  BOARD_BOUNDS.width, 
							  BOARD_BOUNDS.height)
}

process_play_input :: proc(s: ^Play_Scene) -> Play_Action {
	if is_mouse_over_board() && rl.IsMouseButtonPressed(.LEFT) {
		return .Left_Click_Board
	}
	if rl.IsKeyPressed(.M) {
		return .Toggle_Move_Overlay
	}
	if (rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.LEFT_SHIFT)) && rl.IsKeyPressed(.SLASH) {
		return .Toggle_Help
	}
	return .None
}

toggle_help :: proc() {
	g.board.show_help = !g.board.show_help
}

toggle_move_overlay :: proc() {
	g.board.show_move_overlay = !g.board.show_move_overlay
}

draw_sprite :: proc(
	texture_id: Texture_ID, 
	pos: Vec2, 
	size: Vec2, 
	rotation: f32 = 0, 
	scale: f32 = 1, 
	tint: rl.Color = rl.WHITE
) {
	tex := get_texture(texture_id)
	src_rect := Rec {
		0, 0, f32(tex.width), f32(tex.height),
	}
	dst_rect := Rec {
		pos.x, pos.y, size.x, size.y,
	}
	rl.DrawTexturePro(tex, src_rect, dst_rect, {}, rotation, tint)
}

make_duration_display_string :: proc(d: time.Duration) -> cstring {
	h,m,s := time.clock_from_duration(d)
	cstr := fmt.ctprintf("%dh %dm %ds", h,m,s)
	return cstr
}

make_datetime_display_string :: proc(dt: datetime.DateTime) -> cstring {
	if e := datetime.validate(dt); e != .None {
		// log.error("Failed datetime validation:", e)
		return fmt.ctprint("Invalid date")
	}
	return fmt.ctprintf("%v %v, %v %v:%v:%v", 
						get_month_by_seq(dt.month), 
						dt.day,
						dt.year,
						dt.hour,
						dt.minute,
						dt.second)
}

// get position of top left corner of tile in render (render logical) coords from game logical coords board tile pos
board_tile_pos_to_sprite_logical_render_pos :: proc(x, y: i32) -> Vec2 {
	// origin is bottom left of board
	pos := Vec2{BOARD_BOUNDS.x + f32(x) * TILE_SIZE, 
				BOARD_BOUNDS.y + BOARD_BOUNDS.height - f32(y+1) * TILE_SIZE}
	return pos
}

aabb_intersects :: proc(a_x, a_y, a_w, a_h: f32, b_x, b_y, b_w, b_h: f32) -> bool {
    return !(a_x + a_w < b_x ||
           b_x + b_w < a_x ||
           a_y + a_h < b_y ||
           b_y + b_h < a_y)
}

toggle_music :: proc() {
	g.is_music_enabled = !g.is_music_enabled
}

begin_letterbox_rendering :: proc() {
	rl.BeginTextureMode(g.render_texture)
	rl.ClearBackground(BACKGROUND_COLOR)
	
	// Scale all drawing by RENDER_TEXTURE_SCALE for higher resolution
	camera := rl.Camera2D{
		zoom = RENDER_TEXTURE_SCALE,
		// no offset for chess
		// offset = { 
		// 	LOGICAL_SCREEN_WIDTH * RENDER_TEXTURE_SCALE / 2,
		// 	LOGICAL_SCREEN_HEIGHT * RENDER_TEXTURE_SCALE / 2
		// },
	}
	rl.BeginMode2D(camera)
}

end_letterbox_rendering :: proc() {
	rl.EndMode2D()  // End the scale transform
	rl.EndTextureMode()
	
	rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)
	
	// Calculate letterbox dimensions
	viewport_width, viewport_height := get_viewport_size()
	offset_x, offset_y := get_viewport_offset()
	
	// Draw the render texture with letterboxing
	render_texture_width: f32 = LOGICAL_SCREEN_WIDTH * RENDER_TEXTURE_SCALE
	render_texture_height: f32 = LOGICAL_SCREEN_HEIGHT * RENDER_TEXTURE_SCALE
	src := Rec{0, 0, render_texture_width, -render_texture_height} // negative height flips texture
	dst := Rec{-offset_x, -offset_y, viewport_width, viewport_height}
	rl.DrawTexturePro(g.render_texture.texture, src, dst, {}, 0, rl.WHITE)
	// rl.EndDrawing() // moved outside for debug overlay
}

get_viewport_scale :: proc() -> f32 {
	window_w := f32(rl.GetScreenWidth())
	window_h := f32(rl.GetScreenHeight())
	scale := min(window_w / LOGICAL_SCREEN_WIDTH, window_h / LOGICAL_SCREEN_HEIGHT)
	return scale
}

get_viewport_size :: proc() -> (width, height: f32) {
	scale := get_viewport_scale()
	width = LOGICAL_SCREEN_WIDTH * scale
	height = LOGICAL_SCREEN_HEIGHT * scale
	return width, height
}

get_viewport_offset :: proc() -> (f32,f32) {
	window_w := f32(rl.GetScreenWidth())
	window_h := f32(rl.GetScreenHeight())
	viewport_width, viewport_height := get_viewport_size()
	off_x := -(window_w - viewport_width) / 2
	off_y := -(window_h - viewport_height) / 2
	return off_x, off_y
}

is_in_bounds :: proc(x,y: i32) -> bool {
	return !(x < 0 || x > 7 || y < 0 || y > 7)
}

// Also tests for board boundary
get_tile_by_position :: proc(tiles: Tiles, pos: Position) -> (tile: Tile, in_bounds: bool) {
	if !is_in_bounds(pos.x, pos.y){
		return {}, false
	}
	return tiles[pos.y][pos.x], true
}

get_piece_by_position :: proc(tiles: Tiles, pos: Position) -> (piece: Piece, is_piece: bool) {
	tile, in_bounds := get_tile_by_position(tiles, pos)
	if !in_bounds {
		return {}, false
	}
	if tile_piece, piece_ok := tile.(Piece); piece_ok {
		return tile_piece, true
	}
	return {}, false

}

get_message_for_illegal_move :: proc(board: Board, proposed_move: Move_Data) -> string {
	// CSDR: improve this function to contain a suite of helpful messages
	// for now just use eval_move
	_, message := eval_move(board, proposed_move)
	return message
}


// test for legality, if illegal emit message, else approve move
eval_move :: proc(original_board: Board, proposed_move: Move_Data) -> (
	is_legal: bool, message: string
) {
	proposed_board := original_board
	make_move(&proposed_board, proposed_move)

	threatened_positions := get_threatened_all_positions_for_player(proposed_board,
																    proposed_board.current_player)
	is_king_threatened := is_position_threatened(sa.slice(&threatened_positions),
												 get_king_position(proposed_board.tiles, 
												 proposed_board.current_player))
	if is_king_threatened {
		if original_board.is_check {
			return false, "Illegal move: must get your king out of check"
		} else {
			return false, "Illegal move: cannot move your king into check"
		}
	}
	return true, ""
}


make_move :: proc(board: ^Board, move_result: Move_Data) {
	if move_result.piece_action == .None {
		return
	}

	selected_piece, is_piece := get_piece_by_position(board.tiles, move_result.old_position)
	if !is_piece {
		log.error("Failed to get Piece from position for make_move")
	}
	selected_piece_old_position := move_result.old_position

	switch move_result.piece_action {
	case .Travel:
		// Update the selected piece and store in new position
		// update double move data before has_piece_moved is flagged
		if selected_piece.type == .Pawn && !selected_piece.has_moved && abs(move_result.new_position.y - selected_piece_old_position.y) == 2 {
			board.last_double_move_turn = board.n_turns
			board.last_double_move_end_position = move_result.new_position
		}

		curr_pos := selected_piece_old_position
		set_tile(&board.tiles, curr_pos, Empty_Tile{})

		new_tile := selected_piece
		new_tile.has_moved = true
		new_pos := move_result.new_position
		set_tile(&board.tiles, new_pos, new_tile)

	case .En_Passant:
		// Captured piece is in a special en passant capture position
		curr_pos := selected_piece_old_position
		set_tile(&board.tiles, curr_pos, Empty_Tile{})

		new_pos := move_result.new_position

		captured_position := g.last_double_move_end_position
		captured_piece, _ := get_piece_by_position(board.tiles, captured_position)
		sa.push(&board.captures[board.current_player], captured_piece.type)
		set_tile(&board.tiles, captured_position, Empty_Tile{})

		new_tile := selected_piece
		new_tile.has_moved = true
		set_tile(&board.tiles, new_pos, new_tile)

		update_points(board, board.current_player, captured_piece.type)

	case .Capture:
		// Captured piece is in selected piece's new position
		curr_pos := selected_piece_old_position
		set_tile(&board.tiles, curr_pos, Empty_Tile{})

		new_pos := move_result.new_position

		captured_piece, _ := get_piece_by_position(board.tiles, new_pos)
		sa.push(&board.captures[board.current_player], captured_piece.type)

		new_tile := selected_piece
		new_tile.has_moved = true
		set_tile(&board.tiles, new_pos, new_tile)

		update_points(board, board.current_player, captured_piece.type)

	case .Kingside_Castle:
		// Update the selected piece and store in new position

		curr_king_pos := selected_piece_old_position
		set_tile(&board.tiles, curr_king_pos, Empty_Tile{})

		new_king_piece := selected_piece
		new_king_piece.has_moved = true
		new_king_pos := move_result.new_position
		set_tile(&board.tiles, new_king_pos, new_king_piece)

		// Move Corresponding Rook
		rook_pos: Position
		if board.current_player == .White {
			rook_pos = WHITE_KINGSIDE_ROOK_POSITION
		} else {
			rook_pos = BLACK_KINGSIDE_ROOK_POSITION
		}
		rook_piece, _ := get_piece_by_position(board.tiles, rook_pos)
		set_tile(&board.tiles, rook_pos, Empty_Tile{})

		new_rook_piece := rook_piece
		new_rook_piece.has_moved = true
		new_rook_pos := new_king_pos + {-1,0}
		set_tile(&board.tiles, new_rook_pos, new_rook_piece)

	case .Queenside_Castle:
		// Update the selected piece and store in new position

		curr_king_pos := selected_piece_old_position
		set_tile(&board.tiles, curr_king_pos, Empty_Tile{})

		new_king_piece := selected_piece
		new_king_piece.has_moved = true
		new_king_pos := move_result.new_position
		set_tile(&board.tiles, new_king_pos, new_king_piece)

		// Move Corresponding Rook
		rook_pos: Position
		if board.current_player == .White {
			rook_pos =  WHITE_QUEENSIDE_ROOK_POSITION
		} else {
			rook_pos = BLACK_QUEENSIDE_ROOK_POSITION
		}
		rook_piece, _ := get_piece_by_position(board.tiles, rook_pos)
		set_tile(&board.tiles, rook_pos, Empty_Tile{})

		new_rook_piece := rook_piece
		new_rook_piece.has_moved = true
		new_rook_pos := new_king_pos + {1,0}
		set_tile(&board.tiles, new_rook_pos, new_rook_piece)

	case .None:
	}
}

WHITE_KING_POSITION :: Position{4,0}
WHITE_QUEENSIDE_ROOK_POSITION :: Position{0,0}
WHITE_KINGSIDE_ROOK_POSITION :: Position{BOARD_LENGTH-1,0}

BLACK_KING_POSITION :: Position{4,BOARD_LENGTH-1}
BLACK_QUEENSIDE_ROOK_POSITION :: Position{0,BOARD_LENGTH-1}
BLACK_KINGSIDE_ROOK_POSITION :: Position{BOARD_LENGTH-1,BOARD_LENGTH-1}

get_legal_moves_for_position :: proc(legal_moves: []Move_Data, position: Position) -> (selected_move_results: Move_Results) {
	for m in legal_moves {
		if m.old_position == position {
			sa.append(&selected_move_results, m)
		}
	}
	return selected_move_results
}
// All this does is flag check or checkmate
// This is called at start of next player's turn (right afte end_turn but before next frame)
eval_board :: proc(board: ^Board) {
	// Update board state for downstream logic

	// Cache state ///////////////////////////////////////////////////////////////////////
	// this is for moves to present to player, including illegal moves
	board.threatened_positions = get_threatened_all_positions_for_player(board^,
																		 board.current_player)
	player_moves := get_moves_for_player(board^, board.current_player)
	board.legal_moves = get_legal_moves(board^,
										board.current_player, 
										sa.slice(&board.threatened_positions),
										sa.slice(&player_moves))
	/////////////////////////////////////////////////////////////////////////////////////

	// Check and Checkmate

	is_check := is_position_threatened(sa.slice(&board.threatened_positions),
												 get_king_position(board.tiles, 
												 board.current_player))
	if is_check {
		board.is_check = true

		if sa.len(board.legal_moves) == 0 {
			log.debug("Game Over: Checkmate")
			board.is_checkmate = true
			board.gameover = true
			play_sfx(.Gameover_Win)
		}
	} else {
		board.is_check = false
	}

	// Stalemate conditions

	// No legal moves for either single player
	if !board.is_check && sa.len(board.legal_moves) == 0 {
		log.debug("Game Over: Stalemate, no legal moves left for player")
		board.message = "Stalemate: No legal moves available for player"
		board.is_draw = true
		board.gameover = true
		play_sfx(.Gameover_Draw)
	}

	// Mutual draw
	draw_offer_black_turn := board.draw_offered[.Black]
	draw_offer_white_turn := board.draw_offered[.White]
	if draw_offer_black_turn > 0 && draw_offer_white_turn > 0 {
		if abs(draw_offer_black_turn - draw_offer_white_turn) == 1{
			log.debug("Game Over: Mutual Draw")
			board.message = "Draw: A tie was agreed to"
			board.gameover = true
			board.is_draw = true
			play_sfx(.Gameover_Draw)
		} else {
			log.debug("Reset draw offers")
			board.draw_offered[.Black] = 0
			board.draw_offered[.White] = 0
		}
	}

	// Dead position, show message, don't force

	// get all white/black pieces, is len == 1 and king
	pieces: [Player_Color]sa.Small_Array(16, Piece)
	pieces[.White] = get_pieces_by_player(board.tiles, .White)
	pieces[.Black] = get_pieces_by_player(board.tiles, .Black)

	is_only_king_left :: proc(player_pieces: []Piece) -> bool {
		return len(player_pieces) == 1 && player_pieces[0].type == .King
	}

	is_only_king_bishop_left :: proc(player_pieces: []Piece) -> bool {
		if len(player_pieces) == 2 && is_any_piece_type_from_pieces_slice(player_pieces, .Bishop) && is_any_piece_type_from_pieces_slice(player_pieces, .King) {
			return true
		}
		return false
	}

	is_any_piece_type_from_pieces_slice :: proc(pieces: []Piece, piece_type: Piece_Type) -> bool {
		for p in pieces {
			if p.type == piece_type {
				return true
			}
		}
		return false
	}

	Piece_Type_Counts :: map[Piece_Type]int
	is_only_pieces_left_from_pieces_slice :: proc(player_pieces: []Piece, piece_types_counts: Piece_Type_Counts) -> bool {

		// Create map from player_pieces
		player_pieces_counts: Piece_Type_Counts
		for p in player_pieces {
			if _, ok := player_pieces_counts[p.type]; ok {
				player_pieces_counts[p.type] += 1
			} else {
				player_pieces_counts[p.type] = 1
			}
		}

		// Test and count while looping
		piece_type_total_count: int
		for piece_type, count in piece_types_counts {
			if player_piece_count, ok := player_pieces_counts[piece_type]; ok {
				// counts not the same for a piece type
				if player_piece_count != count {
					return false
				}
			// piece_type not in player_pieces
			} else {
				return false
			}
			piece_type_total_count += count
		}

		is_equal_count := len(player_pieces) == piece_type_total_count
		if !is_equal_count {
			return false
		}

		return true
	}

	Tile_Color :: distinct Player_Color
	get_tile_color :: proc(x, y: i32) -> Tile_Color {
		// on even rows, odd column is black
		if y % 2 == 0 {
			return x % 2 == 0 ? .Black : .White
		}
		return x % 2 == 0 ? .White : .Black
	}

	get_piece_by_position :: proc(tiles: Tiles, position: Position) -> (piece: Piece, is_piece: bool) {
		tile, in_bounds := get_tile_by_position(tiles, position)
		if !in_bounds {
			return {}, false
		}
		if tile_piece, tile_is_piece := tile.(Piece); tile_is_piece {
			return tile_piece, true
		} 
		return {}, false
	}
	get_pieces_of_type_from_slice :: proc(pieces: []Piece, piece_type: Piece_Type) -> (pieces_of_type: sa.Small_Array(8,Piece)) {
		for piece in pieces {
			if piece.type == piece_type {
				sa.append(&pieces_of_type, piece)
			}
		}
		return pieces_of_type
	}

	is_king_only: [Player_Color]bool
	is_king_only[.White] = is_only_king_left(sa.slice(&pieces[.White]))
	is_king_only[.Black] = is_only_king_left(sa.slice(&pieces[.Black]))

	// Case King v King
	is_king_v_king := is_king_only[.White] && is_king_only[.Black]
	if is_king_v_king {
		board.is_dead_position = true
		board.dead_position_message = "King versus King is a dead position. This is a draw."
	}


	// Case King Bishop v King
	is_king_bishop_v_king: [Player_Color]bool
	for pc in Player_Color {
		other_pc := get_other_player_color(pc)
		is_king_only_pc := is_king_only[pc]
		is_other_king_bishop := is_only_king_bishop_left(sa.slice(&pieces[other_pc]))
		if is_king_only_pc && is_only_king_bishop_left(sa.slice(&pieces[other_pc])) {
			is_king_bishop_v_king[pc] = true
		}
	}
	if is_king_bishop_v_king[.White] || is_king_bishop_v_king[.Black] {
		board.is_dead_position = true
		board.dead_position_message = "King versus King & Bishop is a dead position. Consider a draw."
	}


	// Case King Knight v King
	is_king_knight_v_king: [Player_Color]bool

	white_king_knight_map: Piece_Type_Counts
	white_king_knight_map[.King] = 1
	white_king_knight_map[.Knight] = 1
	is_white_king_knight_only := is_only_pieces_left_from_pieces_slice(sa.slice(&pieces[.White]), white_king_knight_map)

	black_king_knight_map: Piece_Type_Counts
	black_king_knight_map[.King] = 1
	black_king_knight_map[.Knight] = 1
	is_black_king_knight_only := is_only_pieces_left_from_pieces_slice(sa.slice(&pieces[.Black]), black_king_knight_map)

	if is_white_king_knight_only || is_black_king_knight_only {
		board.is_dead_position = true
		board.dead_position_message = "King versus King & Knight is a dead position. Consider a draw."
	}


	is_king_bishop_v_king_bishop_same_color := false
	// for both players:
	// is 2 pieces left
	// one is king other is bishop

	// are both bishops same color? (get color of tile!)

	white_king_bishop_map: Piece_Type_Counts
	white_king_bishop_map[.King] = 1
	white_king_bishop_map[.Bishop] = 1
	is_white_king_bishop_only := is_only_pieces_left_from_pieces_slice(sa.slice(&pieces[.White]), white_king_bishop_map)

	white_bishop_tile_color: Tile_Color
	white_piece_positions := get_piece_positions_by_player(board.tiles, .White)
	for pos in sa.slice(&white_piece_positions) {
		piece, is_piece := get_piece_by_position(board.tiles, pos)
		if is_piece && piece.type == .Bishop {
			white_bishop_tile_color = get_tile_color(pos.x, pos.y)
		}
	}

	black_king_bishop_map: Piece_Type_Counts
	black_king_bishop_map[.King] = 1
	black_king_bishop_map[.Bishop] = 1
	is_black_king_bishop_only := is_only_pieces_left_from_pieces_slice(sa.slice(&pieces[.Black]), black_king_bishop_map)

	black_bishop_tile_color: Tile_Color
	black_piece_positions := get_piece_positions_by_player(board.tiles, .Black)
	for pos in sa.slice(&black_piece_positions) {
		piece, is_piece := get_piece_by_position(board.tiles, pos)
		if is_piece && piece.type == .Bishop {
			black_bishop_tile_color = get_tile_color(pos.x, pos.y)
		}
	}

	if is_white_king_bishop_only && is_black_king_bishop_only && white_bishop_tile_color == black_bishop_tile_color {
		board.is_dead_position = true
		board.dead_position_message = "King & Bishop versus King & Bishop where bishops are same tile color is a dead position. Consider a draw."
	}


	// TODO: refactor propose_move (and others?) so that state is set here and the other fns simple read the state, eg see how castling is done here.

	// Castling Conditions:
	// - king not in check
	// - king & rook cannot have moved
	// - king move-through and final position must have no piece, nor under threat

	board.can_queenside_castle[board.current_player] = is_castle_available(
			board.current_player == .White ? WHITE_KING_POSITION : BLACK_KING_POSITION,
			board.current_player == .White ? WHITE_QUEENSIDE_ROOK_POSITION : BLACK_QUEENSIDE_ROOK_POSITION,
			board.is_check,
			board.tiles,
			sa.slice(&board.threatened_positions),
		)

	board.can_kingside_castle[board.current_player] = is_castle_available(
			board.current_player == .White ? WHITE_KING_POSITION : BLACK_KING_POSITION,
			board.current_player == .White ? WHITE_KINGSIDE_ROOK_POSITION : BLACK_KINGSIDE_ROOK_POSITION,
			board.is_check,
			board.tiles,
			sa.slice(&board.threatened_positions),
		)
}

debug_is_castle_available :: proc(
	initial_king_position: Position,
	initial_rook_position: Position,
	is_check: bool,
	tiles: Tiles,
	threatened_positions: []Position,
) -> bool {
	// test while check
	pr("--------------  is_castle_avail_debug --------------")
	if is_check {
		return false // cannot castle if check?
	}
	pr("passed is_checK")

	// test king moved
	king_tile, _ := get_tile_by_position(tiles, initial_king_position)
	king_piece, is_king_piece := king_tile.(Piece)
	if (is_king_piece && king_piece.has_moved) || !is_king_piece {
		return false // no, king has moved
	}
	pr("passed king moved")

	// test rook moved
	rook_tile, _ := get_tile_by_position(tiles, initial_rook_position)
	rook_piece, is_rook_piece := rook_tile.(Piece)
	if (is_rook_piece && rook_piece.has_moved) || !is_rook_piece {
		return false // no, rook has moved
	}
	pr("passed rook moved")

	// test pieces blocking

	// move left/right
	move_pos_1: Position
	move_pos_2: Position
	if initial_king_position.x > initial_rook_position.x {
		move_pos_1 = initial_king_position + {-1,0}
		move_pos_2 = initial_king_position + {-2,0}
	} else {
		move_pos_1 = initial_king_position + {1,0}
		move_pos_2 = initial_king_position + {2,0}
	}

	tile_1, _ := get_tile_by_position(tiles, move_pos_1)
	if _, is_piece_1 := tile_1.(Piece); is_piece_1 {
		return false // no, first pos to side is blocked by piece
	}
	pr("passed block 1st pos")

	tile_2, _ := get_tile_by_position(tiles, move_pos_2)
	if _, is_piece_2 := tile_2.(Piece); is_piece_2 {
		return false // no, second pos to side is blocked by piece
	}
	pr("passed block 2nd pos")

	// test positions threatened. Equivalent to testing for king moving into a check
	is_threatened_1 := is_position_threatened(threatened_positions, move_pos_1)
	is_threatened_2 := is_position_threatened(threatened_positions, move_pos_2)
	if is_threatened_1 || is_threatened_2 {
		return false // no, one of side positions is threatened
	}
	pr("passed threatened")

	pr("----------------- end castle debug")
	return true
}

is_castle_available :: proc(
	initial_king_position: Position,
	initial_rook_position: Position,
	is_check: bool,
	tiles: Tiles,
	threatened_positions: []Position,
) -> bool {
	// test while check
	if is_check {
		return false // cannot castle if check?
	}

	// test king moved
	king_tile, _ := get_tile_by_position(tiles, initial_king_position)
	king_piece, is_king_piece := king_tile.(Piece)
	if (is_king_piece && king_piece.has_moved) || !is_king_piece {
		return false // no, king has moved
	}

	// test rook moved
	rook_tile, _ := get_tile_by_position(tiles, initial_rook_position)
	rook_piece, is_rook_piece := rook_tile.(Piece)
	if (is_rook_piece && rook_piece.has_moved) || !is_rook_piece {
		return false // no, rook has moved
	}

	// test pieces blocking

	// move left/right
	move_pos_1: Position
	move_pos_2: Position
	if initial_king_position.x > initial_rook_position.x {
		move_pos_1 = initial_king_position + {-1,0}
		move_pos_2 = initial_king_position + {-2,0}
	} else {
		move_pos_1 = initial_king_position + {1,0}
		move_pos_2 = initial_king_position + {2,0}
	}

	tile_1, _ := get_tile_by_position(tiles, move_pos_1)
	if _, is_piece_1 := tile_1.(Piece); is_piece_1 {
		return false // no, first pos to side is blocked by piece
	}

	tile_2, _ := get_tile_by_position(tiles, move_pos_2)
	if _, is_piece_2 := tile_2.(Piece); is_piece_2 {
		return false // no, second pos to side is blocked by piece
	}

	// test positions threatened. Equivalent to testing for king moving into a check
	is_threatened_1 := is_position_threatened(threatened_positions, move_pos_1)
	is_threatened_2 := is_position_threatened(threatened_positions, move_pos_2)
	if is_threatened_1 || is_threatened_2 {
		return false // no, one of side positions is threatened
	}

	return true
}

get_moves_for_player :: proc(
	board: Board, 
	player_color: Player_Color
) -> (
	player_moves: Move_Results
) {
	piece_positions := get_piece_positions_by_player(board.tiles, player_color)
	for piece_position in sa.slice(&piece_positions) {
		moves := get_moves_for_position(board, piece_position, player_color)
		for move in sa.slice(&moves) {
			sa.push(&player_moves, move)
		}
	}
	return
}

get_legal_moves :: proc(
	original_board: Board,
	player_color: Player_Color, 
	threatened_positions: []Position, 
	player_moves: []Move_Data
) -> (
	legal_moves: Move_Results
) {
	outer_loop: for move in player_moves {
		is_move_legal, _message := eval_move(original_board, move)
		if is_move_legal  {
			sa.push(&legal_moves, move)
		}
	}
	return legal_moves
}

get_king_legal_moves :: proc(
	board: Board, 
	player_color: Player_Color
) -> (
	legal_moves: Move_Results
) {
	blind_moves := get_moves_for_position(board, 
							 get_king_position(board.tiles, player_color), 
							 player_color)
	threatened_positions := board.threatened_positions
	for blind_move in sa.slice(&blind_moves) {
		for p in sa.slice(&threatened_positions) {
			if blind_move.new_position == p {
				break
			}
		}
		sa.append(&legal_moves, blind_move)
	}
	return legal_moves
}

can_king_move :: proc(board: Board, player_color: Player_Color) -> bool {
	blind_moves := get_moves_for_position(board, 
								   get_king_position(board.tiles, player_color), 
								   player_color)
	threatened_positions := board.threatened_positions
	for blind_move in sa.slice(&blind_moves) {
		is_move_threatened := false
		for threatened_position in sa.slice(&threatened_positions) {
			if blind_move.new_position == threatened_position {
				is_move_threatened = true
			}
		}
		// has a non-threatened move
		if !is_move_threatened {
			return true
		}
	}
	return false
}

// CSDR rename _current_turn or _current_player
is_position_threatened :: proc(threatened_positions: []Position, tile_pos: Position) -> bool {
	// does any enemy piece threaten this position?
	for pos in threatened_positions {
		if tile_pos == pos {
			return true
		}
	}
	return false
}

get_king_position :: proc(tiles: Tiles, player_color: Player_Color) -> Position {
	for row, y in tiles {
		for tile, x in row {
			piece, is_piece := tile.(Piece)
			if is_piece && piece.type == .King && piece.color == player_color {
				return Position{i32(x),i32(y)}
			}
		}
	}

	// Should never happen, but if it does...
	log.error("CRITICAL GAME STATE CORRUPTION: Failed to get king position for player:", player_color)
	when ODIN_DEBUG {
		panic("Invalid chess state: missing king")
	} else {
		g.app_state = .Exit
		return {}
	}
}

get_king_piece :: proc(tiles: Tiles, player_color: Player_Color) -> Piece {
	for row, y in tiles {
		for tile, x in row {
			if piece, is_piece := tile.(Piece); is_piece {
				if piece.type == .King && piece.color == player_color {
					return piece
				}
			}
		}
	}
	log.error("Failed to get king position, no king exists for player:", player_color)
	return {}
}

get_piece_positions_by_player :: proc(
	tiles: Tiles, player_color: Player_Color
) -> (
	piece_positions: sa.Small_Array(16, Position)
) {
	for row, y in tiles {
		for tile, x in row {
			if piece, is_piece := tile.(Piece); is_piece && piece.color == player_color {
				sa.push(&piece_positions, Position{i32(x), i32(y)})
			}
		}
	}
	return
}

get_pieces_by_player :: proc(
	tiles: Tiles, player_color: Player_Color
) -> (
	pieces: sa.Small_Array(16, Piece)
) {
	for row, y in tiles {
		for tile, x in row {
			if piece, is_piece := tile.(Piece); is_piece && piece.color == player_color {
				sa.push(&pieces, piece)
			}
		}
	}
	return pieces
}

get_threatened_all_positions_for_player :: proc(
	board: Board, 
	player_being_threatened: Player_Color
) -> (
	threatened_positions: sa.Small_Array(MAX_ELEMENTS_FOR_MOVE_RESULTS, Position)
) {
	// Cant use blind moves... it doesnt take into account all threatened positions

	threatening_player := get_other_player_color(player_being_threatened)
	enemy_piece_positions := get_piece_positions_by_player(board.tiles, threatening_player)

	set_of_threatened_positions: map[Position]Void
	set_of_threatened_positions_en_passant: map[Position]Void

	en_passant_override := false
	for enemy_piece_pos in sa.slice(&enemy_piece_positions) {
		piece_threatened_positions, is_en_passant := get_threatened_positions_by_piece(
																board,
																enemy_piece_pos,
																threatening_player)
		for ptp in sa.slice(&piece_threatened_positions) {
			set_of_threatened_positions[ptp] = {}
			if is_en_passant == true {
				set_of_threatened_positions_en_passant[ptp] = {}
				en_passant_override = true
			}
		}
	}

	if en_passant_override {
		sarr: sa.Small_Array(BOARD_LENGTH * BOARD_LENGTH, Position)
		for key in set_of_threatened_positions_en_passant {
			sa.append(&sarr, key)
		}
		return sarr
	}

	for key in set_of_threatened_positions {
		sa.append(&threatened_positions, key)
	}
	return threatened_positions
}

init_board :: proc() -> Board {
	positions_with_pieces := [BOARD_LENGTH][BOARD_LENGTH]Piece_Type{
		{.Rook, .Knight, .Bishop, .Queen, .King, .Bishop, .Knight, .Rook},
		{.Pawn,.Pawn,.Pawn,.Pawn,.Pawn,.Pawn,.Pawn,.Pawn,},
		{}, {}, {}, {},
		{.Pawn,.Pawn,.Pawn,.Pawn,.Pawn,.Pawn,.Pawn,.Pawn,},
		{.Rook, .Knight, .Bishop, .Queen, .King, .Bishop, .Knight, .Rook},
	}
	tiles := make_tiles_with_piece_types(positions_with_pieces)
	return Board{
		tiles = tiles,
		n_turns = 1,
		current_player = .White,
	}
}

make_tiles_with_piece_types :: proc(
	piece_types: [BOARD_LENGTH][BOARD_LENGTH]Piece_Type
) -> (
	tiles: Tiles
) {
	for row, y in piece_types {
		for piece_type, x in row {
			tile_type: enum { Empty, White_Piece, Black_Piece } = .Empty
			if piece_type != .None {
				if y <= 3 {
					tile_type = .White_Piece
				} else if y >= 4 {
					tile_type = .Black_Piece
				}
			}
			if tile_type == .Empty {
				tiles[y][x] = Empty_Tile{}
			} else {
				piece_color: Piece_Color = tile_type == .White_Piece ? .White : .Black
				tiles[y][x] = Piece{
					type = piece_type,
					color = piece_color,
				}
			}
		}
	}
	return
}

MAX_ELEMENTS_FOR_MOVE_RESULTS :: BOARD_LENGTH * BOARD_LENGTH
Move_Results :: sa.Small_Array(MAX_ELEMENTS_FOR_MOVE_RESULTS, Move_Data)
Move_Data :: struct {
	old_position: Position,
	new_position: Position,
	piece_action: Piece_Action,
}

Piece_Action :: enum u8 {
	None,
	Travel,
	Capture,
	En_Passant,
	Queenside_Castle,
	Kingside_Castle,
}

KNIGHT_RELATIVE_MOVE_POSITIONS :: [?]Position{
	{-1,  2},
	{ 1,  2},
	{ 2,  1},
	{ 2, -1},
	{ 1, -2},
	{-1, -2},
	{-2,  1},
	{-2, -1},
}

DIAGONAL_DIRECTIONS :: [4]Vec2i{
	{1,1},{1,-1},{-1,-1},{-1,1},
}

CARDINAL_DIRECTIONS :: [4]Vec2i{
	{0,1},{1,0},{0,-1},{-1,0},
}

ALL_DIRECTIONS :: [8]Vec2i{
	{1,1},{1,-1},{-1,-1},{-1,1},
	{0,1},{1,0},{0,-1},{-1,0},
}

// Previously named get_possible_moves. Moves that are presented to player for a given piece (position)
get_moves_for_position :: proc(board: Board, pos: Position, player_color: Player_Color) -> Move_Results {
	piece, is_piece := get_piece_by_position(board.tiles, pos)
	if !is_piece {
		return {}
	}

	// aka color and top/bottom side factor
	flip_factor: i32 = piece.color == .White ? 1 : -1
	flip_factor *= g.is_white_bottom ? 1 : -1

	arr: Move_Results
	#partial top_switch: switch piece.type {
	case .Pawn:
		// CASE pawn en passants, not a forced move

		// this pawn is on 5th rank (white) or 4th rank (black)
		is_pawn_on_passant_row_condition_satisfied: bool
		if (pos.y == 4 && player_color == .White) || (pos.y == 3 && player_color == .Black) {
			is_pawn_on_passant_row_condition_satisfied = true
		}

		// last double move was previous turn and is adjacent to this pawn
		is_double_move_condition_satisfied: bool
		// NB: move_turn >= n_turns - 1 because this fn is also used for checking for threatened positions, in which case the moveturn is +1
		if (board.last_double_move_turn >= board.n_turns - 1) && (board.last_double_move_end_position.x == pos.x - 1 || board.last_double_move_end_position.x == pos.x + 1) {
			is_double_move_condition_satisfied = true
		}

		if is_pawn_on_passant_row_condition_satisfied && is_double_move_condition_satisfied {
			// capture end position is effectively behind the double moved pawn
			capture_position := board.last_double_move_end_position 
			capture_offset_y: i32 = player_color == .White ? 1 : -1
			capture_position.y += capture_offset_y
			sa.push(&arr, Move_Data{ 
				old_position = pos, 
				new_position = capture_position, 
				piece_action = .En_Passant,
			})
			break top_switch
		}

		// CASE pawn basic move
		move_direction := Position{0,1} * flip_factor

		// cast ray of length 1 for basic move
		pos_0 := pos + move_direction
		tile_0, in_bounds := get_tile_by_position(board.tiles, pos_0)
		tile_0_empty, tile_0_is_empty := tile_0.(Empty_Tile)
		if tile_0_is_empty && in_bounds {
			sa.push(&arr, Move_Data{
				old_position = pos,
				new_position = pos_0, 
				piece_action = .Travel,
			})
		} 

		// cast ray of length 2 for first move
		if !piece.has_moved {
			pos_1 := pos + move_direction * 2
			tile_1, ray2_in_bounds := get_tile_by_position(board.tiles, pos_1)
			tile_1_empty, tile_1_is_empty := tile_1.(Empty_Tile)
			if tile_0_is_empty && tile_1_is_empty && ray2_in_bounds {
				sa.push(&arr, Move_Data{
					old_position = pos,
					new_position = pos_1,
					piece_action = .Travel,
				})
			}
		}

		// CASE pawn captures
		capture_position_right_1 := pos + Position{1,1} * flip_factor
		tile_cap_right_1, _ := get_tile_by_position(board.tiles, capture_position_right_1)
		tile_cap_right_1_piece, is_tcr1_piece := tile_cap_right_1.(Piece)
		if is_tcr1_piece && tile_cap_right_1_piece.color != player_color {
			sa.push(&arr, Move_Data{
				old_position = pos,
				new_position = capture_position_right_1,
				piece_action = .Capture,
			})
		}

		capture_position_left_1 := pos + Position{-1,1} * flip_factor
		tile_cap_left_1, _ := get_tile_by_position(board.tiles, capture_position_left_1)
		tile_cap_left_1_piece, is_tcl1_piece := tile_cap_left_1.(Piece)
		if is_tcl1_piece && tile_cap_left_1_piece.color != player_color {
			sa.push(&arr, Move_Data{
				old_position = pos,
				new_position = capture_position_left_1,
				piece_action = .Capture,
			})
		}

	case .Knight:
		// CASE knight basic move
		relative_move_positions := [?]Position{
			{-1,  2},
			{ 1,  2},
			{ 2,  1},
			{ 2, -1},
			{ 1, -2},
			{-1, -2},
			{-2,  1},
			{-2, -1},
		}
		for rel_pos in relative_move_positions {
			target_pos := pos + rel_pos * flip_factor
			target_tile, in_bounds := get_tile_by_position(board.tiles, target_pos)
			if in_bounds {
				switch v in target_tile {
				case Piece:
					if v.color == get_other_player_color(player_color) {
						sa.push(&arr, Move_Data{
							old_position = pos,
							new_position = target_pos, 
							piece_action = .Capture,
						})
					}
				case Empty_Tile:
					sa.push(&arr, Move_Data{
						old_position = pos,
						new_position = target_pos,
						piece_action = .Travel,
					})
				}
			}
		}

	case .Bishop:
		move_directions := DIAGONAL_DIRECTIONS
		for dir in move_directions {
			// cast ray until: intersect piece or out of bounds
			bishop_ray: for i in 1..<BOARD_LENGTH {
				target_pos := pos + (dir * i32(i))
				target_tile, in_bounds := get_tile_by_position(board.tiles, target_pos)
				if !in_bounds {
					break bishop_ray
				}
				switch v in target_tile {
				case Piece:
					if v.color == get_other_player_color(player_color) {
						sa.push(&arr, Move_Data{
							old_position = pos,
							new_position = target_pos,
							piece_action = .Capture,
						})
					}
					break bishop_ray
				case Empty_Tile:
					sa.push(&arr, Move_Data{
						old_position = pos,
						new_position = target_pos,
						piece_action = .Travel,
					})
				}
			}
		}

	case .Rook:
		move_directions := CARDINAL_DIRECTIONS
		for dir in move_directions {
			rook_ray: for i in 1..<BOARD_LENGTH {
				// cast ray until: hit piece or out of bounds
				target_pos := pos + (dir * i32(i))
				target_tile, in_bounds := get_tile_by_position(board.tiles, target_pos)
				if !in_bounds {
					break rook_ray

				} 

				switch v in target_tile {
				case Piece:
					if v.color == get_other_player_color(player_color) {
						sa.push(&arr, Move_Data{
							old_position = pos,
							new_position = target_pos,
							piece_action = .Capture,
						})
					}
					break rook_ray
				case Empty_Tile:
					sa.push(&arr, Move_Data{
						old_position = pos,
						new_position = target_pos,
						piece_action = .Travel,
					})
				}
			}
		}
	
	case .Queen:
		move_directions := ALL_DIRECTIONS
		for dir in move_directions {
			queen_ray: for i in 1..<BOARD_LENGTH {
				// cast ray until: hit piece or out of bounds
				target_pos := pos + (dir * i32(i))
				target_tile, in_bounds := get_tile_by_position(board.tiles, target_pos)
				if !in_bounds {
					break queen_ray
				}

				switch v in target_tile {
				case Piece:
					if v.color == get_other_player_color(player_color) {
						sa.push(&arr, Move_Data{
							old_position = pos,
							new_position = target_pos,
							piece_action = .Capture,
						})
					}
					break queen_ray
				case Empty_Tile:
					sa.push(&arr, Move_Data{
						old_position = pos,
						new_position = target_pos,
						piece_action = .Travel,
					})
				}
			}
		}
	case .King:
		move_directions := ALL_DIRECTIONS
		for dir in move_directions {
			// cast ray until: hit piece or out of bounds
			target_pos := pos + dir
			target_tile, in_bounds := get_tile_by_position(board.tiles, target_pos)
			if !in_bounds {
				continue
			}
			switch v in target_tile {
			case Piece:
				if v.color == get_other_player_color(player_color) {
					sa.push(&arr, Move_Data{
						old_position = pos,
						new_position = target_pos,
						piece_action = .Capture,
					})
				}
				continue
			case Empty_Tile:
				sa.push(&arr, Move_Data{
					old_position = pos,
					new_position = target_pos,
					piece_action = .Travel,
				})
			}
		}
		if board.can_queenside_castle[player_color] {
			sa.push(&arr, Move_Data{
				old_position = pos,
				new_position = pos + {-2,0},
				piece_action = .Queenside_Castle,
			})
		}
		if board.can_kingside_castle[player_color] {
			sa.push(&arr, Move_Data{
				old_position = pos,
				new_position = pos + {2,0},
				piece_action = .Kingside_Castle,
			})
		}
	}
	return arr
}

get_threatened_positions_by_piece :: proc(
	board: Board, 
	pos: Position, 
	threatening_player: Player_Color
) -> (
	threatened_positions: sa.Small_Array(MAX_ELEMENTS_FOR_MOVE_RESULTS, Position), 
	is_en_passant: bool
) {
	// Add standard moves first
	enemy_blind_moves := get_moves_for_position(board, pos, threatening_player)
	for enemy_blind_move in sa.slice(&enemy_blind_moves) {
		piece, _ := get_piece_by_position(board.tiles, enemy_blind_move.old_position)
		is_pawn := piece.type == .Pawn

		is_capture_action := enemy_blind_move.piece_action == .Capture
		is_travel_action := enemy_blind_move.piece_action == .Travel

		// Pawn Travel action cannot capture
		if is_pawn && is_capture_action {
			sa.append(&threatened_positions, enemy_blind_move.new_position)

		// Rest of pieces Travel action can also capture
		} else if !is_pawn && (is_travel_action || is_capture_action) {
			sa.append(&threatened_positions, enemy_blind_move.new_position)
		}
	}

	// Now get any additional positions being threatened by doing something similar to get_blind_moves for but including positions that are capturable by enemy pieces AND occupied by an enemy piece.

	tile, _ := get_tile_by_position(board.tiles, pos)
	piece := tile.(Piece) 

	// aka color and top/bottom side factor
	flip_factor: i32 = piece.color == .White ? 1 : -1
	flip_factor *= g.is_white_bottom ? 1 : -1

	arr: Move_Results
	#partial top_switch: switch piece.type {
	case .Pawn:
		// this pawn is on 5th rank (white) or 4th rank (black)
		is_pawn_on_passant_row_condition_satisfied: bool
		if (pos.y == 4 && threatening_player == .White) || (pos.y == 3 && threatening_player == .Black) {
			is_pawn_on_passant_row_condition_satisfied = true
		}

		// last double move was previous turn and is adjacent to this pawn
		is_double_move_condition_satisfied: bool
		// NB: move_turn >= n_turns - 1 because this fn is also used for checking for threatened positions, in which case the moveturn is +1
		if (board.last_double_move_turn >= board.n_turns - 1) && (board.last_double_move_end_position.x == pos.x - 1 || board.last_double_move_end_position.x == pos.x + 1) {
			is_double_move_condition_satisfied = true
		}

		if is_pawn_on_passant_row_condition_satisfied && is_double_move_condition_satisfied {
			// capture end position is effectively behind the double moved pawn
			capture_position := board.last_double_move_end_position 
			capture_offset_y: i32 = threatening_player  == .White ? 1 : -1
			capture_position.y += capture_offset_y
			sa.push(&threatened_positions, capture_position)
			is_en_passant = true
			break top_switch
		}

		// CASE pawn captures
		capture_position_right_1 := pos + Position{1,1} * flip_factor
		_, in_bounds_tcr1 := get_tile_by_position(board.tiles, capture_position_right_1)
		if in_bounds_tcr1 {
			sa.push(&threatened_positions, capture_position_right_1)
		}

		capture_position_left_1 := pos + Position{-1,1} * flip_factor
		_, in_bounds_tcl1 := get_tile_by_position(board.tiles, capture_position_left_1)
		if in_bounds_tcl1 {
			sa.push(&threatened_positions, capture_position_left_1)
		}

	case .Knight:
		relative_move_positions := KNIGHT_RELATIVE_MOVE_POSITIONS 
		for rel_pos in relative_move_positions {
			target_pos := pos + rel_pos * flip_factor
			target_tile, in_bounds := get_tile_by_position(board.tiles, target_pos)
			if in_bounds {
				if target_piece, is_piece := target_tile.(Piece); is_piece && target_piece.color == threatening_player {
					sa.push(&threatened_positions, target_pos)
				}
			}
		}

	case .Bishop:
		move_directions := DIAGONAL_DIRECTIONS
		for dir in move_directions {
			// cast ray until: intersect piece or out of bounds
			bishop_ray: for i in 1..<BOARD_LENGTH {
				target_pos := pos + (dir * i32(i))
				target_tile, in_bounds := get_tile_by_position(board.tiles, target_pos)
				if !in_bounds {
					break bishop_ray
				}
				if target_piece, is_piece := target_tile.(Piece); is_piece {
					if target_piece.color == threatening_player {
						sa.push(&threatened_positions, target_pos)
					}
					break bishop_ray
				}
			}
		}

	case .Rook:
		move_directions := CARDINAL_DIRECTIONS
		for dir in move_directions {
			rook_ray: for i in 1..<BOARD_LENGTH {
				// cast ray until: hit piece or out of bounds
				target_pos := pos + (dir * i32(i))
				target_tile, in_bounds := get_tile_by_position(board.tiles, target_pos)
				if !in_bounds {
					break rook_ray
				}

				if target_piece, is_piece := target_tile.(Piece); is_piece {
					if target_piece.color == threatening_player {
						sa.push(&threatened_positions, target_pos)
					}
					break rook_ray
				}
			}
		}
	
	case .Queen:
		move_directions := ALL_DIRECTIONS
		for dir in move_directions {
			queen_ray: for i in 1..<BOARD_LENGTH {
				// cast ray until: hit piece or out of bounds
				target_pos := pos + (dir * i32(i))
				target_tile, in_bounds := get_tile_by_position(board.tiles, target_pos)
				if !in_bounds {
					break queen_ray
				}
				if target_piece, is_piece := target_tile.(Piece); is_piece {
					if target_piece.color == threatening_player {
						sa.push(&threatened_positions, target_pos)
					}
					break queen_ray
				}
			}
		}
	case .King:
		move_directions := ALL_DIRECTIONS
		for dir in move_directions {
			// cast ray until: hit piece or out of bounds
			target_pos := pos + dir
			target_tile, in_bounds := get_tile_by_position(board.tiles, target_pos)
			if !in_bounds {
				continue
			}
			if target_piece, is_piece := target_tile.(Piece); is_piece {
				if target_piece.color == threatening_player {
					sa.push(&threatened_positions, target_pos)
				}
				continue
			}
		}
	}
	return
}

get_tile_position_from_mouse_already_over_board :: proc() -> Position {
	mouse_pos := get_mouse_position()

	// from tile coords origin (bot left board)
	dx := math.round(mouse_pos.x - BOARD_BOUNDS.x)
	dy := math.round(BOARD_BOUNDS.y + BOARD_BOUNDS.height - mouse_pos.y)

	return {i32(math.floor(dx / TILE_SIZE)), i32(math.floor(dy / TILE_SIZE))}
}

set_tile :: proc(tiles: ^Tiles, pos: Position, tile: Tile) {
	if pos.y < 0 || pos.y >= BOARD_LENGTH || pos.x < 0 || pos.x >= BOARD_LENGTH {
		log.error("Cannot set a tile outside of board positions. position:", pos, ", tile: ", tile)
		return
	}
	tiles[pos.y][pos.x] = tile
}

end_turn :: proc(board: ^Board, t: ^Game_Time) {
	t.players_duration[board.current_player] += g.time.turn_duration
	t.turn_start = time.tick_now()
	end_board_turn(board)
	g.message = ""
}

end_board_turn :: proc(board: ^Board) {
	board.n_turns += 1
	switch board.current_player {
	case .Black: board.current_player = .White
	case .White: board.current_player = .Black
	}
}

update_points :: proc(board: ^Board, current_player: Player_Color, piece_type: Piece_Type) {
	board.points[current_player] += PIECE_POINTS[piece_type]
}

ui_camera :: proc() -> rl.Camera2D {
	return {
		zoom = RENDER_TEXTURE_SCALE,
	}
}

draw_piece_sprite :: proc(render_position: Vec2i, scale: f32 = 1, piece_type: Piece_Type, piece_color: Piece_Color) {
	tex := get_texture_by_piece_type(piece_type)

	// set src/dst rectangels
	src_rect := Rec{0,0,f32(tex.width), f32(tex.height)}
	dst_rect := Rec{f32(render_position.x), f32(render_position.y), f32(TILE_SIZE) * scale, f32(TILE_SIZE) * scale}
	tint := piece_color == .White ? WHITE_PIECE_COLOR : BLACK_PIECE_COLOR
	rl.DrawTexturePro(tex, src_rect, dst_rect, {}, 0, tint)
}

draw_piece_character :: proc(piece_type: Piece_Type, piece_color: Piece_Color, tile_position: Position) {
	text: cstring
	color := piece_color == .White ? rl.BEIGE : rl.BROWN
	switch piece_type {
	case .Rook:
		text = fmt.ctprintf("R")
	case .Knight:
		text = fmt.ctprintf("K")
	case .Bishop:
		text = fmt.ctprintf("B")
	case .Queen:
		text = fmt.ctprintf("Q")
	case .King:
		text = fmt.ctprintf("K")
	case .Pawn:
		text = fmt.ctprintf("P")
	case .None:
	}
	rl.DrawText(text, tile_position.x, tile_position.y, 28, color)

	if g.debug {
		rl.DrawRectangle(i32(tile_position.x), i32(tile_position.y), 1, 1, rl.RED)
	}
}

get_player_duration :: proc(p: Player_Color) -> time.Duration {
	return g.time.players_duration[p]
}

get_turn_duration :: proc() -> time.Duration {
	return g.time.turn_duration
}

get_game_duration :: proc() -> time.Duration {
	return g.time.game_duration
}

get_datetime_now :: proc() -> datetime.DateTime {
	time_now := time.now()
	dt, _ := time.time_to_datetime(time_now)
	local_dt, ok := timezone.datetime_to_tz(dt, g.time.local_timezone) // handles nil region
	return local_dt
}

MONTHS_SHORT_DISPLAY := [?]string{
	"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
}

// 1-based index
get_month_by_seq :: proc(seq: i8) -> string {
	// return MONTHS_SHORT_DISPLAY[seq]
	return fmt.tprintf("%v", time.Month(seq))
}

get_other_player_color :: proc(player_color: Player_Color) -> Player_Color {
	return player_color == .White ? .Black : .White
}

draw_tile_border :: proc(tile_pos: Position, color: rl.Color) {
	sprite_origin := board_tile_pos_to_sprite_logical_render_pos(tile_pos.x, tile_pos.y)
	rl.DrawRectangleLinesEx({sprite_origin.x, sprite_origin.y, TILE_SIZE, TILE_SIZE}, 2, color)
}

test_init_board_king_threatening_ray :: proc() -> Board {
	piece_types := [BOARD_LENGTH][BOARD_LENGTH]Piece_Type{
		{}, 
		{}, 
		{}, 
		{.None,.None,.None,.None,.King,.None, .None,.None}, 
		{.None,.None,.None,.Bishop,.None,.None, .None,.None}, 
		{}, 
		{}, 
		{.None,.None,.None,.King,.None,.None, .None,.None}, 
	}
	tiles := make_tiles_with_piece_types(piece_types)
	return make_board_from_tiles(tiles)
}

test_init_board_king_cannot_capture_check :: proc() -> Board {
	piece_types := [BOARD_LENGTH][BOARD_LENGTH]Piece_Type{
		{}, 
		{}, 
		{}, 
		{.None,.None,.None,.None,.King,.None, .None,.None}, 
		{.None,.None,.None,.Rook,.Bishop,.None, .None,.None}, 
		{}, 
		{}, 
		{.None,.None,.None,.King,.None,.None, .None,.None}, 
	}
	tiles := make_tiles_with_piece_types(piece_types)
	return make_board_from_tiles(tiles)
}

test_init_trapped_king_board :: proc() -> Board {
	piece_types := [BOARD_LENGTH][BOARD_LENGTH]Piece_Type{
		{.None,.None,.None,.None,.King,.None, .None,.None}, 
		{}, 
		{}, 
		{}, 
		{.None,.None,.Rook,.Rook,.Queen,.None, .None,.None}, 
		{}, 
		{}, 
		{.None,.None,.None,.King,.None,.None, .None,.None}, 
	}
	tiles := make_tiles_with_piece_types(piece_types)
	return make_board_from_tiles(tiles)
}

test_init_white_checked_board :: proc() -> Board {
	piece_types := [BOARD_LENGTH][BOARD_LENGTH]Piece_Type{
		{.None,.None,.None,.None,.King,.None, .None,.None}, 
		{}, 
		{}, 
		{}, 
		{.None,.None,.None,.None,.Queen,.None, .None,.None}, 
		{}, 
		{}, 
		{.None,.None,.None,.King,.None,.None, .None,.None}, 
	}
	tiles := make_tiles_with_piece_types(piece_types)
	return make_board_from_tiles(tiles)
}

test_init_black_checked_board :: proc() -> Board {
	piece_types := [BOARD_LENGTH][BOARD_LENGTH]Piece_Type{
		{.None,.None,.None,.None,.King,.None, .None,.None}, 
		{}, 
		{}, 
		{.None,.None,.None,.Queen,.None,.None, .None,.None}, 
		{}, 
		{}, 
		{}, 
		{.None,.None,.None,.King,.None,.None, .None,.None}, 
	}
	tiles := make_tiles_with_piece_types(piece_types)
	return make_board_from_tiles(tiles)
}

test_init_white_checkmated_board :: proc() -> Board {
	piece_types := [BOARD_LENGTH][BOARD_LENGTH]Piece_Type{
		{.None,.None,.None,.None,.King,.None, .None,.None}, 
		{}, 
		{}, 
		{}, 
		{.None,.None,.None,.Rook,.Queen,.Rook, .None,.None}, 
		{}, 
		{}, 
		{}, 
	}
	tiles := make_tiles_with_piece_types(piece_types)
	return make_board_from_tiles(tiles)
}

test_init_board_sparse :: proc() -> Board {
	piece_types := [BOARD_LENGTH][BOARD_LENGTH]Piece_Type{
		{.None,.None,.None,.None,.King,.None, .None,.None}, 
		{}, 
		{}, 
		{}, 
		{.None,.None,.None,.None,.None,.None, .None,.None}, 
		{}, 
		{}, 
		{.None,.None,.None,.None,.King,.None, .None,.None}, 
	}
	tiles := make_tiles_with_piece_types(piece_types)
	return make_board_from_tiles(tiles)
}

test_init_board_castle_allow :: proc() -> Board {
	piece_types := [BOARD_LENGTH][BOARD_LENGTH]Piece_Type{
		{.Rook,.None,.None,.None,.King,.None, .None,.Rook}, 
		{}, 
		{}, 
		{}, 
		{.None,.None,.None,.None,.None,.None, .None,.None}, 
		{}, 
		{}, 
		{.Rook,.None,.None,.None,.King,.None, .None,.Rook}, 
	}
	tiles := make_tiles_with_piece_types(piece_types)
	return make_board_from_tiles(tiles)
}

test_init_board_castle_threatened :: proc() -> Board {
	piece_types := [BOARD_LENGTH][BOARD_LENGTH]Piece_Type{
		{.Rook,.None,.None,.None,.King,.None, .None,.Rook}, 
		{.None,.None,.None,.None,.None,.None, .None,.None}, 
		{.None,.None,.None,.None,.None,.None, .None,.None}, 
		{.None,.None,.None,.None,.Queen,.None, .None,.None}, 
		{.None,.None,.Queen,.None,.None,.None, .None,.None}, 
		{.None,.None,.None,.None,.None,.None, .None,.None}, 
		{.None,.None,.None,.None,.None,.None, .None,.None}, 
		{.Rook,.None,.None,.None,.King,.None, .None,.Rook}, 
	}
	tiles := make_tiles_with_piece_types(piece_types)
	return make_board_from_tiles(tiles)
}

test_init_board_castle_blocked :: proc() -> Board {
	piece_types := [BOARD_LENGTH][BOARD_LENGTH]Piece_Type{
		{.Rook,.None,.Bishop,.None,.King,.Bishop, .None,.Rook}, 
		{.None,.None,.None,.None,.None,.None, .None,.None}, 
		{.None,.None,.None,.None,.None,.None, .None,.None}, 
		{.None,.None,.None,.None,.Queen,.None, .None,.None}, 
		{.None,.None,.Queen,.None,.None,.None, .None,.None}, 
		{.None,.None,.None,.None,.None,.None, .None,.None}, 
		{.None,.None,.None,.None,.None,.None, .None,.None}, 
		{.Rook,.None,.Bishop,.None,.King,.Bishop, .None,.Rook}, 
	}
	tiles := make_tiles_with_piece_types(piece_types)
	return make_board_from_tiles(tiles)
}

BLANK_TILES := [BOARD_LENGTH][BOARD_LENGTH]Piece_Type{
	{.None,.None,.None,.None,.None,.None,.None,.None,},
	{.None,.None,.None,.None,.None,.None,.None,.None,},
	{.None,.None,.None,.None,.None,.None,.None,.None,},
	{.None,.None,.None,.None,.None,.None,.None,.None,},
	{.None,.None,.None,.None,.None,.None,.None,.None,},
	{.None,.None,.None,.None,.None,.None,.None,.None,},
	{.None,.None,.None,.None,.None,.None,.None,.None,},
	{.None,.None,.None,.None,.None,.None,.None,.None,},
}

test_init_board_king_v_king :: proc() -> Board {
	piece_types := BLANK_TILES
	piece_types[0][4] = .King
	piece_types[7][4] = .King
	tiles := make_tiles_with_piece_types(piece_types)
	return make_board_from_tiles(tiles)
}

test_init_board_king_bishop_v_king :: proc() -> Board {
	piece_types := BLANK_TILES
	piece_types[0][4] = .King
	piece_types[0][5] = .Bishop
	piece_types[7][4] = .King
	tiles := make_tiles_with_piece_types(piece_types)
	return make_board_from_tiles(tiles)
}

test_init_board_king_v_king_bishop :: proc() -> Board {
	piece_types := BLANK_TILES
	piece_types[0][4] = .King
	piece_types[7][4] = .King
	piece_types[7][5] = .Bishop
	tiles := make_tiles_with_piece_types(piece_types)
	return make_board_from_tiles(tiles)
}

test_init_board_king_knight_v_king :: proc() -> Board {
	piece_types := BLANK_TILES
	piece_types[0][4] = .King
	piece_types[0][6] = .Knight
	piece_types[7][4] = .King
	tiles := make_tiles_with_piece_types(piece_types)
	return make_board_from_tiles(tiles)
}

test_init_board_king_v_king_knight :: proc() -> Board {
	piece_types := BLANK_TILES
	piece_types[0][4] = .King
	piece_types[0][6] = .Knight
	piece_types[7][4] = .King
	tiles := make_tiles_with_piece_types(piece_types)
	return make_board_from_tiles(tiles)
}

test_init_board_king_bishop_v_king_bishop_same_color_bishop_black :: proc() -> Board {
	piece_types := BLANK_TILES
	piece_types[0][4] = .King
	piece_types[0][2] = .Bishop
	piece_types[7][4] = .King
	piece_types[7][5] = .Bishop
	tiles := make_tiles_with_piece_types(piece_types)
	return make_board_from_tiles(tiles)
}

test_init_board_king_bishop_v_king_bishop_same_color_bishop_white :: proc() -> Board {
	piece_types := BLANK_TILES
	piece_types[0][4] = .King
	piece_types[0][5] = .Bishop
	piece_types[7][4] = .King
	piece_types[7][2] = .Bishop
	tiles := make_tiles_with_piece_types(piece_types)
	return make_board_from_tiles(tiles)
}

make_board_from_tiles :: proc(tiles: Tiles) -> Board {
	return Board{
		tiles = tiles,
		n_turns = 1,
		current_player = .White,
	}
}

update_mouse_transform :: proc() {
	offx, offy := get_viewport_offset()
	scale := get_viewport_scale()
	rl.SetMouseOffset(i32(offx), i32(offy))
	rl.SetMouseScale(1/scale, 1/scale)
}

test_init_board_promotion_white :: proc() -> Board {
	piece_types := BLANK_TILES
	piece_types[0][4] = .King
	piece_types[7][4] = .King
	tiles := make_tiles_with_piece_types(piece_types)
	tiles[6][0] = Piece{
		type = .Pawn,
		color = .White,
		has_moved = true,
	}
	return make_board_from_tiles(tiles)
}

test_init_board_promotion_black :: proc() -> Board {
	piece_types := BLANK_TILES
	piece_types[0][4] = .King
	piece_types[7][4] = .King
	tiles := make_tiles_with_piece_types(piece_types)
	tiles[1][0] = Piece{
		type = .Pawn,
		color = .Black,
		has_moved = true,
	}
	return make_board_from_tiles(tiles)
}

get_texture_by_piece_type :: proc(piece_type: Piece_Type) -> rl.Texture2D {
	switch piece_type {
	case .King:
		return get_texture(.King)
	case .Queen:
		return get_texture(.Queen)
	case .Pawn:
		return get_texture(.Pawn)
	case .Rook:
		return get_texture(.Rook)
	case .Bishop:
		return get_texture(.Bishop)
	case .Knight:
		return get_texture(.Knight)
	case .None:
		return {}
	}
	return {}
}

// Draw window to select promotion piece type
Promotion_Piece_Data :: struct {
	piece_type: Piece_Type,
	rect: Rec,
}

setup_promotion_piece_data :: proc(data: []Promotion_Piece_Data) {
	PROMOTION_PIECES := [?]Piece_Type{.Queen,.Rook,.Bishop,.Knight}

	x0 :f32= (LOGICAL_SCREEN_WIDTH / 2) - (2 * TILE_SIZE * 1.1)
	y0 :f32= LOGICAL_SCREEN_HEIGHT / 2

	for type, i in PROMOTION_PIECES {
		data[i] = Promotion_Piece_Data{
			piece_type = type,
			rect = {
				x = x0 + (f32(i) * TILE_SIZE * 1.1),
				y = y0,
				width = TILE_SIZE,
				height = TILE_SIZE,
			}
		}
	}
}

TOPBAR_HEIGHT :: 40
BOARD_RENDER_LENGTH: f32 : f32(LOGICAL_SCREEN_HEIGHT) - f32(TOPBAR_HEIGHT)

BOARD_BOUNDS :: Rec{
	(LOGICAL_SCREEN_WIDTH - BOARD_RENDER_LENGTH) / 2,
	TOPBAR_HEIGHT,
	BOARD_RENDER_LENGTH,
	BOARD_RENDER_LENGTH,
}

PANEL_Y :: TOPBAR_HEIGHT
PANEL_WIDTH :: BOARD_BOUNDS.x - 1
PANEL_HEIGHT :: BOARD_RENDER_LENGTH
LEFT_PANEL_BOUNDS :: Rec{
	0,
	PANEL_Y,
	PANEL_WIDTH,
	PANEL_HEIGHT,
}
RIGHT_PANEL_BOUNDS :: Rec{
	BOARD_BOUNDS.x + BOARD_RENDER_LENGTH + 1,
	PANEL_Y,
	PANEL_WIDTH,
	PANEL_HEIGHT,
}

TILE_SIZE: f32 = BOARD_RENDER_LENGTH / BOARD_LENGTH

draw_board_tiles :: proc() {
	for y in 0..<BOARD_LENGTH {
		for x in 0..< BOARD_LENGTH {
			color: rl.Color
			if ((y*BOARD_LENGTH) + x) % 2 == 0 {
				color = y % 2 == 1 ? DARK_TILE_COLOR : LIGHT_TILE_COLOR
			} else {
				color = y % 2 == 1 ? LIGHT_TILE_COLOR :  DARK_TILE_COLOR
			}
			rl.DrawRectangle(i32(math.round(BOARD_BOUNDS.x + f32(x) * TILE_SIZE)),
							 i32(math.round(BOARD_BOUNDS.y + f32(y) * TILE_SIZE)),
							 i32(math.round(TILE_SIZE)),
							 i32(math.round(TILE_SIZE)),
							 color)
		}
	}
}

draw_pieces_to_board :: proc(tiles: Tiles) {
	for row, y in g.board.tiles {
		for tile, x in row {
			if piece, is_piece := tile.(Piece); is_piece {
				// get sprite render origin
				render_pos := board_tile_pos_to_sprite_logical_render_pos(i32(x), i32(y))

				// scale: f32 = 1
				scale: f32 = 32/TILE_SIZE

				// center
				center_delta := (TILE_SIZE - (scale * TILE_SIZE)) / 2
				render_pos_center_x := render_pos.x + center_delta
				render_pos_center_y := render_pos.y + center_delta
				tile_render_pos_x := i32(math.round(render_pos_center_x))
				tile_render_pos_y := i32(math.round(render_pos_center_y))

				draw_piece_sprite({tile_render_pos_x ,tile_render_pos_y}, scale, piece.type, piece.color)
			}
		}
	}
}

draw_selected_piece_move_overlay :: proc(selected_piece: ^Selected_Piece_Data) {
	for legal_move in sa.slice(&selected_piece.legal_moves) {
		sprite_origin := board_tile_pos_to_sprite_logical_render_pos(legal_move.new_position.x, legal_move.new_position.y)
		rl.DrawRectangleLinesEx({sprite_origin.x, sprite_origin.y, TILE_SIZE, TILE_SIZE},2, rl.GRAY)
		rl.DrawRectangle(i32(sprite_origin.x+1), i32(sprite_origin.y+1), i32(TILE_SIZE-2), i32(TILE_SIZE-2), rl.BLUE)
	}
}

draw_check_overlay :: proc(tiles: Tiles, player: Player_Color) {
	// Highlight king in check or checkmate
	king_pos := get_king_position(g.board.tiles, g.current_player)
	draw_tile_border(king_pos, rl.RED)
}

draw_debug_board_overlay :: proc() {
	// draw tile borders via grid
	for y in 0..=BOARD_LENGTH {
		rl.DrawLine(
			i32(math.floor(BOARD_BOUNDS.x + 0)), 
			i32(BOARD_BOUNDS.y + f32(y) * TILE_SIZE), 
			i32(math.floor(BOARD_BOUNDS.x + BOARD_BOUNDS.width)), // for error: cannot be rep w/o truncate/round as type i32
			i32(BOARD_BOUNDS.y + f32(y) * TILE_SIZE), 
			rl.BLUE,
		)
	}
	for x in 0..=BOARD_LENGTH {
		rl.DrawLine(
			i32(BOARD_BOUNDS.x + f32(x) * TILE_SIZE), 
			i32(BOARD_BOUNDS.y + 0), 
			i32(BOARD_BOUNDS.x + f32(x) * TILE_SIZE), 
			i32(BOARD_BOUNDS.y + BOARD_BOUNDS.height), 
			rl.BLUE,
		)
	}

	for y in 0..=BOARD_LENGTH {
		for x in 0..=BOARD_LENGTH {
			render_pos := board_tile_pos_to_sprite_logical_render_pos(i32(x), i32(y))
			render_pos.x += 2
			tile_render_pos_x := i32(math.round(render_pos.x))
			tile_render_pos_y := i32(math.round(render_pos.y))
			rl.DrawText(fmt.ctprintf("%v,%v", x,y), 
						tile_render_pos_x,
						tile_render_pos_y,
						10,
						rl.BLUE)
		}
	}

	// indicate center of viewport
	xc :i32= LOGICAL_SCREEN_WIDTH/2
	yc :i32= LOGICAL_SCREEN_HEIGHT/2
	rl.DrawLine(xc - 2, yc, xc + 2, yc, rl.ORANGE)
	rl.DrawLine(xc, yc - 2, xc, yc + 2, rl.ORANGE)
	rl.DrawRectangleLines(
		i32((math.round(BOARD_BOUNDS.x-1))),
		i32(math.round(BOARD_BOUNDS.y-1)),
		i32(math.round(BOARD_BOUNDS.width+2)),
		i32(math.round(BOARD_BOUNDS.height+2)),
		rl.GREEN,
	)

	// Identify threatened positions
	for tp in sa.slice(&g.board.threatened_positions) {
		render_pos := board_tile_pos_to_sprite_logical_render_pos(tp.x, tp.y)
		render_pos.y += TILE_SIZE * 0.75
		tile_render_pos_x := i32(math.round(render_pos.x))
		tile_render_pos_y := i32(math.round(render_pos.y))
		rl.DrawText("T", tile_render_pos_x, tile_render_pos_y, 10, rl.RED)
	}
}

draw_promotion_piece_frame :: proc() {
	rl.DrawRectangle(i32(g.promotion_piece_data[0].rect.x),i32(g.promotion_piece_data[0].rect.y), i32(TILE_SIZE * 1.1 * len(g.promotion_piece_data)), i32(TILE_SIZE * 1.1), rl.LIGHTGRAY)

	for data, i in g.promotion_piece_data {
		tex := get_texture_by_piece_type(data.piece_type)
		x := data.rect.x
		y := data.rect.y
		src_rect := Rec{0,0,f32(tex.width), f32(tex.height)}
		dst_rect := Rec{f32(x), f32(y), f32(data.rect.width), f32(data.rect.height)}
		tint := g.current_player == .White ? WHITE_PIECE_COLOR : BLACK_PIECE_COLOR
		rl.DrawTexturePro(tex, src_rect, dst_rect, {}, 0, tint)
	}
}

draw_debug_overlay :: proc() {
	// Debug overlay
	debug_overlay_text_column :: proc(x,y: ^i32, slice_cstr: []string) {
		gy: i32 = 20
		for s in slice_cstr {
			cstr := strings.clone_to_cstring(s)
			rl.DrawText(cstr, x^, y^, 20, rl.WHITE)
			y^ += gy
		}
	}
	{
		x: i32 = 5
		y: i32 = 40
		arr := [?]string{
			fmt.tprintf("game_duration: %v", 
						make_duration_display_string(get_game_duration())),
			fmt.tprintf("turn_duration: %v", 
						make_duration_display_string(get_turn_duration())),
			fmt.tprintf("white running: %v", 
						make_duration_display_string(g.time.players_duration[.White])),
			fmt.tprintf("black running: %v", 
						make_duration_display_string(g.time.players_duration[.Black])),
			fmt.tprintf("game_start_datetime: %v", 
						make_datetime_display_string(g.time.game_start_datetime)),
			fmt.tprintf("game_end_datetime: %v", 
						make_datetime_display_string(g.time.game_end_datetime)),
		}
		debug_overlay_text_column(&x, &y, arr[:])

		arr2 := [?]string{
			fmt.tprintf("mouse_pos: %v", 
						rl.GetMousePosition()),
			fmt.tprintf("mouse_tile_pos: %v", 
						get_tile_position_from_mouse_already_over_board()),
			fmt.tprintf("check: %v", 
						g.board.is_check),
			fmt.tprintf("white_kingside_castle: %v", 
						g.board.can_kingside_castle[.White]),
			fmt.tprintf("white_queenside_castle: %v", 
						g.board.can_queenside_castle[.White]),
			fmt.tprintf("black_kingside_castle: %v", 
						g.board.can_kingside_castle[.Black]),
			fmt.tprintf("black_queenside_castle: %v", 
						g.board.can_queenside_castle[.Black]),
		}
		y += 40
		debug_overlay_text_column(&x, &y, arr2[:])

		make_string_from_value :: proc(v: any) -> string {
			return fmt.tprintf("%v", v)
		}

		selected_piece_type_text: string
		sp_has_moved: string
		if try_move_data, is_phase_try_move := g.board.turn_phase.(Try_Move); is_phase_try_move {
			if selected_piece, selected_piece_ok := try_move_data.selected_piece.?; selected_piece_ok {
				piece, is_piece := get_piece_by_position(g.board.tiles, selected_piece.position)
				selected_piece_type_text = make_string_from_value(piece.type)
				sp_has_moved = make_string_from_value(piece.has_moved)
			} else {
				selected_piece_type_text = "nil"
				sp_has_moved = "nil"
			}
		}

		arr3 := [?]string{
			fmt.tprintf("n_turns: %v", 
						g.n_turns),
			fmt.tprintf("curr_player: %v", 
						g.current_player),
			fmt.tprintf("points-white: %v", 
						g.points[.White]),
			fmt.tprintf("points-black: %v", 
						g.points[.Black]),
			fmt.tprintf("n-captures-white: %v", 
						sa.len(g.board.captures[.White])),
			fmt.tprintf("n-captures-black: %v", 
						sa.len(g.board.captures[.Black])),
			fmt.tprintf("selected_piece type: %v", 
						selected_piece_type_text),
			fmt.tprintf("selected_piece type: %v", 
						selected_piece_type_text),
			fmt.tprintf("selected_piece has_moved: %v", 
						sp_has_moved),
			fmt.tprintf("draw_offered_white: %v", 
						g.draw_offered[.White]),
			fmt.tprintf("draw_offered_black: %v", 
						g.draw_offered[.Black]),
		}
		y += 40
		debug_overlay_text_column(&x, &y, arr3[:])
	}
}

draw_help_modal :: proc() {
    // Semi-transparent dark background
    rl.DrawRectangle(0, 0, LOGICAL_SCREEN_WIDTH, LOGICAL_SCREEN_HEIGHT, {0, 0, 0, 150})
    
    // Main panel background
    panel_width :: LOGICAL_SCREEN_WIDTH * 0.7
    panel_height := i32(math.round(f32(LOGICAL_SCREEN_HEIGHT * 0.7)))
    panel_x := i32((LOGICAL_SCREEN_WIDTH - panel_width) / 2)
    panel_y := i32( math.round(f32(LOGICAL_SCREEN_HEIGHT - panel_height) / 2) )
    
    // Panel shadow
    // rl.DrawRectangle(panel_x + 5, panel_y + 5, panel_width, panel_height, {0, 0, 0, 100})
    
    // Panel background
    rl.DrawRectangle(panel_x, panel_y, panel_width, panel_height, {40, 40, 50, 255})
    rl.DrawRectangleLines(panel_x, panel_y, panel_width, panel_height, rl.WHITE)
    
    // Title
    title := "Help"
	title_font_size: i32 = 20
    title_width := rl.MeasureText(fmt.ctprint(title), title_font_size)
    rl.DrawText(fmt.ctprint(title), panel_x + i32((panel_width - title_width) / 2), panel_y + 20, title_font_size, rl.WHITE)
    
    // Draw stats in columns
    col1_x := panel_x + 30
    col2_x := panel_x + 160
    y_start := panel_y + 60
    
	header_font_size: i32 = 14
    // Column 1: Option keys
    y := y_start
    rl.DrawText("Options", col1_x, y, header_font_size, rl.LIGHTGRAY)

    y += 25
    rl.DrawText("? : Toggle Help", col1_x, y, 8, rl.WHITE)
	y += 15
    rl.DrawText("M : Show Move Overlay", col1_x, y, 8, rl.WHITE)
	y += 15
    rl.DrawText("Esc : Exit Program", col1_x, y, 8, rl.WHITE)

	// Column 2: Time
	y = y_start
    rl.DrawText("Times", col2_x, y, header_font_size, rl.LIGHTGRAY)

	y += 25
	game_start_string := make_datetime_display_string(g.time.game_start_datetime)
	game_start_display := fmt.ctprintf("Game start: %v", game_start_string)
    rl.DrawText(game_start_display , col2_x, y, 8, rl.WHITE)
	y += 15
	game_duration_string := make_duration_display_string(g.time.game_duration)
	game_duration_display := fmt.ctprintf("Game duration: %v", game_duration_string)
    rl.DrawText(game_duration_display , col2_x, y, 8, rl.WHITE)
	y += 15
	timezone_string := g.time.local_timezone.name
	timezone_display := fmt.ctprintf("Timezone: %v", timezone_string)
    rl.DrawText(timezone_display , col2_x, y, 8, rl.WHITE)
	y += 20
	turn_duration_string := make_duration_display_string(g.time.turn_duration)
	turn_duration_display := fmt.ctprintf("Current turn: %v", turn_duration_string)
    rl.DrawText(turn_duration_display , col2_x, y, 8, rl.WHITE)
	y += 15
	white_turn_duration_string := make_duration_display_string(g.time.players_duration[.White])
	white_turn_duration_display := fmt.ctprintf("White total duration: %v", white_turn_duration_string)
    rl.DrawText(white_turn_duration_display , col2_x, y, 8, rl.WHITE)
	y += 15
	black_turn_duration_string := make_duration_display_string(g.time.players_duration[.Black])
	black_turn_duration_display := fmt.ctprintf("Black total duration: %v", black_turn_duration_string)
    rl.DrawText(black_turn_duration_display , col2_x, y, 8, rl.WHITE)

    // Performance info at bottom
    // perf_y := panel_y + panel_height - 80
    // rl.DrawLine(panel_x + 20, perf_y - 10, panel_x + panel_width - 20, perf_y - 10, rl.DARKGRAY)
    //
    // rl.DrawText(
    //     fmt.ctprintf("Sample Rate: Every %d frames (%.2fs) | Press 5-7 to adjust", 
    //         stats.sample_interval, 
    //         f32(stats.sample_interval) / 60.0), 
    //     panel_x + 40, perf_y, 14, rl.GRAY)
    //
    // rl.DrawText(
    //     fmt.ctprintf("Last Update: %d frames ago", stats.frames_since_sample), 
    //     panel_x + 40, perf_y + 20, 14, rl.GRAY)
    

    // Close instruction
	close_text_x := panel_x + i32((panel_width - 200) / 2)
	close_text_y := panel_y + panel_height - 40
    rl.DrawText("Press  ?  to close this window", close_text_x, close_text_y, 14, rl.LIGHTGRAY)
	if rl.GuiButton({f32(close_text_x + 47), f32(close_text_y - 1),15,15}, "#193#") {
		log.debug("Player click: close help modal")
		g.show_help = false
	}
	// draw close button
	if rl.GuiButton({f32(panel_x + panel_width - 22), f32(panel_y + 3), 18, 18}, "x") {
		log.debug("Player click: close help modal")
		g.show_help = false
	}
}

init_test_captures :: proc() {
	sa.push(&g.board.captures[.White],
		Piece_Type.Pawn, Piece_Type.Pawn, Piece_Type.Pawn, Piece_Type.Pawn,
		Piece_Type.Pawn, Piece_Type.Pawn, Piece_Type.Pawn, Piece_Type.Pawn,
		Piece_Type.Pawn, Piece_Type.Pawn, Piece_Type.Pawn, Piece_Type.Pawn,
		Piece_Type.Pawn, Piece_Type.Pawn, Piece_Type.Pawn,
	)
	sa.push(&g.board.captures[.Black],
		Piece_Type.Pawn, Piece_Type.Pawn, Piece_Type.Pawn, Piece_Type.Pawn,
		Piece_Type.Pawn, Piece_Type.Pawn, Piece_Type.Pawn, Piece_Type.Pawn,
		Piece_Type.Pawn, Piece_Type.Pawn, Piece_Type.Pawn, Piece_Type.Pawn,
		Piece_Type.Pawn, Piece_Type.Pawn, Piece_Type.Pawn,
	)
}


handle_board_click :: proc() {
	// Selected Piece Logic
	clicked_tile_position := get_tile_position_from_mouse_already_over_board()
	try_move_turn_phase_data := g.turn_phase.(Try_Move)
	clicked_piece, is_piece_clicked := get_piece_by_position(g.board.tiles, clicked_tile_position)

	// Click on a friendly piece to run selection logic, no move possible from this action
	if is_piece_clicked && clicked_piece.color == g.board.current_player {
		handle_friendly_piece_click(clicked_tile_position, try_move_turn_phase_data)

	// Try move with selected piece
	} else if try_move_turn_phase_data.selected_piece != nil {
		handle_move_attempt(clicked_tile_position, try_move_turn_phase_data)

	// No piece selected and click on empty position or enemy piece, no move possible from this action
	} else {
		log.debug("No action")
		play_sfx(.Empty)
	}
}

handle_friendly_piece_click :: proc(clicked_tile_position: Position, try_move_data: Try_Move) {
	selected_piece, is_piece_selected := try_move_data.selected_piece.?
	if is_piece_selected {
		if selected_piece.position != clicked_tile_position {
			select_piece(clicked_tile_position)
			log.debug("Action: Select_Another_Piece")
		} else {
			deselect_piece()
			log.debug("DeSelect_Piece")
		}
	} else {
		select_piece(clicked_tile_position)
		log.debug("Action: Select_Piece")
	}
}

deselect_piece :: proc() {
	g.board.turn_phase = Try_Move{}
	play_sfx(.Empty)
}

select_piece :: proc(clicked_tile_position: Position) {
	legal_moves := g.board.legal_moves
	selected_legal_moves := get_legal_moves_for_position(sa.slice(&legal_moves), clicked_tile_position)
	new_selected_piece := Selected_Piece_Data{
		position = clicked_tile_position,
		legal_moves = selected_legal_moves,
	}
	g.turn_phase = Try_Move{
		selected_piece = new_selected_piece,
	}
	play_sfx(.Piece_Select)
}

handle_move_attempt :: proc(clicked_tile_position: Position, try_move_data: Try_Move) {
	selected_piece, is_piece_selected := try_move_data.selected_piece.?

	proposed_move := Move_Data{
		old_position = selected_piece.position,
		new_position = clicked_tile_position,
		piece_action = .None,
	}

	// if it's within current legal moves, add the piece action (identify as legal)
	for legal_move in sa.slice(&g.board.legal_moves) {
		if legal_move.old_position == selected_piece.position && legal_move.new_position == clicked_tile_position {
			proposed_move.piece_action = legal_move.piece_action
		}
	}

	// legality via piece_action
	if proposed_move.piece_action != .None {
		make_move(&g.board, proposed_move)
		log.debug("Move, data:", proposed_move)
		if proposed_move.piece_action == .Travel {
			play_sfx(.Piece_Travel)
		} else {
			play_sfx(.Piece_Capture)
		}

		if promotion_available := eval_promotion(&g.board); promotion_available {
				g.board.turn_phase = Choose_Promotion_Piece{}
				play_sfx(.Piece_Promote)
		} else {
			g.board.turn_phase = End{}
		}

	// if illegal, evaluate the move and say why
	} else {
		g.message = get_message_for_illegal_move(g.board, proposed_move)
	}
}
