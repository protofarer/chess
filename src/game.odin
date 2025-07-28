package game

import "core:fmt"
import "core:log"
import "core:math/linalg"
import "core:math"
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

WINDOW_W :: 1600
WINDOW_H :: 900
TICK_RATE :: 60

BACKGROUND_COLOR :: rl.GRAY

DARK_TILE_COLOR :: rl.LIGHTGRAY
LIGHT_TILE_COLOR :: rl.WHITE

PIECE_POINTS := [Piece_Type]i32{
	.None = 0,
	.Pawn = 1,
	.Knight = 3,
	.Bishop = 3,
	.Rook = 5,
	.Queen = 9,
	.King = 0,
}

Game_Memory :: struct {
	app_state: App_State,
	scene: Scene,
	resman: ^Resource_Manager,
	audman: Audio_Manager,
	is_music_enabled: bool,
	debug: bool,
	render_texture: rl.RenderTexture,
	using board: Board,
	selected_piece: Maybe(Selected_Piece_Data),
	is_white_bottom: bool,
}

Player_Color :: Piece_Color

Selected_Piece_Data :: struct {
	position: Position,
	tile: Tile,
	possible_moves: Move_Results,
}

App_State :: enum {
	Running,
	Exit
}

Scene :: union {
	// Menu_Scene,
	Play_Scene,
	// Game_Over_Scene,
	// Win_Scene,
}

Play_Scene :: struct {
	is_paused: bool,
}

should_game_over :: proc() -> bool {
	return false
}

Entity :: struct {
	pos: Position,
	size: Vec2,
	rotation: f32,
	color: rl.Color,
}

Sprite :: struct {
	texture_id: Texture_ID,
}

g: ^Game_Memory

ui_camera :: proc() -> rl.Camera2D {
	return {
		zoom = RENDER_TEXTURE_SCALE,
	}
}

update :: proc() {
	process_global_input()

	// next_scene: Maybe(Scene) = nil
	switch &s in g.scene {
	case Play_Scene:
		process_play_input(&s)
		if !s.is_paused {
			if should_game_over() {
				unreachable()
				// next_scene = Game_Over_Scene{}
			}
		}
	case:
	}
}


// TODO: rename, more descriptive, render_logical?
topbar_height :: 20
board_topleft_x: f32 : f32(LOGICAL_SCREEN_WIDTH * (f32(1) - f32(0.66))) / 2
board_topleft_y: f32 : f32(topbar_height)
board_width: f32 : f32(LOGICAL_SCREEN_HEIGHT) - f32(topbar_height)
board_height: f32 : board_width

board_bounds :: Rec{
	board_topleft_x, board_topleft_y, board_width, board_height
}

tile_size: f32 = f32(board_width) / 8

board_tile_pos_to_sprite_logical_render_pos :: proc(x, y: i32) -> Vec2 {
	// origin is bottom left of board
	pos := Vec2{board_bounds.x + f32(x) * tile_size, board_bounds.y + board_bounds.height - f32(y+1) * tile_size}
	return pos
}


draw :: proc() {
	begin_letterbox_rendering()

	switch &s in g.scene {
	case Play_Scene:
		rl.DrawRectangle(0, 0, LOGICAL_SCREEN_WIDTH, i32(topbar_height), rl.BLUE)

		for y in 0..<8 {
			for x in 0..< 8 {
				color: rl.Color
				if ((y*8) + x) % 2 == 0 {
					color = y % 2 == 1 ? LIGHT_TILE_COLOR :  DARK_TILE_COLOR
				} else {
					color = y % 2 == 1 ? DARK_TILE_COLOR : LIGHT_TILE_COLOR
				}
				rl.DrawRectangle(i32(math.round(board_bounds.x + f32(x) * tile_size)), i32(math.round(board_bounds.y + f32(y) * tile_size)), i32(math.round(tile_size)), i32(math.round(tile_size)), color)
			}
		}

		for row, y in g.board.tiles {
			for tile, x in row {
				text: cstring
				color := tile.piece_color == .White ? rl.BEIGE : rl.BROWN
				switch tile.piece_type {
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
				// get top left corner of tile in render (render logical) coords from game logical coords board tile pos
				render_pos := board_tile_pos_to_sprite_logical_render_pos(i32(x), i32(y))
				tile_render_pos := Vec2i{i32(math.round(render_pos.x)), i32(math.round(render_pos.y))}
				rl.DrawText(text, tile_render_pos.x, tile_render_pos.y, 28, color)

				if g.debug {
					// top left of tile :: sprite container origin
					rl.DrawRectangle(i32(tile_render_pos.x), i32(tile_render_pos.y), 1, 1, rl.RED)
				}
			}
		}

		// TODO: draw selected piece visuals: highlight piece, show moves, get moves (calc collisions, captures)
		if g.selected_piece != nil {
			selected_piece := g.selected_piece.?
			selected_piece_tile_pos := selected_piece.position

			// border tile for now
			sprite_origin := board_tile_pos_to_sprite_logical_render_pos(selected_piece_tile_pos.x, selected_piece_tile_pos.y)
			rl.DrawRectangleLinesEx({sprite_origin.x, sprite_origin.y, tile_size, tile_size}, 2, rl.GREEN)

			// draw possible moves
			move_results := selected_piece.possible_moves
			for move_result in sa.slice(&move_results) {
				move_origin := board_tile_pos_to_sprite_logical_render_pos(move_result.position.x, move_result.position.y)
				rl.DrawRectangleLinesEx({move_origin.x, move_origin.y, tile_size, tile_size}, 2, rl.PURPLE)
			}
		}

		if g.debug {
			// tile "grid"
			for y in 0..<9 {
				rl.DrawLine(
					i32(math.floor(board_bounds.x + 0)), 
					i32(board_bounds.y + f32(y) * tile_size), 
					i32(math.floor(board_bounds.x + board_bounds.width)), // for error: cannot be rep w/o truncate/round as type i32
					i32(board_bounds.y + f32(y) * tile_size), 
					rl.BLUE,
				)
			}
			for x in 0..<9 {
				rl.DrawLine(
					i32(board_bounds.x + f32(x) * tile_size), 
					i32(board_bounds.y + 0), 
					i32(board_bounds.x + f32(x) * tile_size), 
					i32(board_bounds.y + board_bounds.height), 
					rl.BLUE,
				)
			}

			// draw debug center
			rl.DrawRectangle(LOGICAL_SCREEN_WIDTH/2, LOGICAL_SCREEN_HEIGHT/2, 3, 3, rl.ORANGE)
			rl.DrawRectangleLines(i32((math.round(board_bounds.x))), i32(math.round(board_bounds.y)), i32(math.round(board_bounds.width)), i32(math.round(board_bounds.height)), rl.GREEN)
		}
		if s.is_paused {
			rl.DrawRectangle(0, 0, 90, 90, {0, 0, 0, 180})
			rl.DrawText("PAUSED", 90, 90, 30, rl.WHITE)
		}
	}

	rl.BeginMode2D(ui_camera())
	rl.DrawText(fmt.ctprintf("NEW GAME"), 5, 5, 8, rl.WHITE)
	rl.DrawText(fmt.ctprintf("DRAW"), 100, 5, 8, rl.WHITE)
	rl.DrawText(fmt.ctprintf("TIME"), 200, 5, 8, rl.WHITE)
	rl.DrawText(fmt.ctprintf("EXIT"), 300, 5, 8, rl.WHITE)
	rl.EndMode2D()

	end_letterbox_rendering()
}
 
// Run once: allocate, set global variable immutable values
setup :: proc() {
	context.logger = log.create_console_logger(nil, {
        // .Level,
        // .Terminal_Color,
        // .Short_File_Path,
        // .Line,
        // .Procedure,
        .Time,
	})

	rl.InitAudioDevice()
	audman := init_audio_manager()

	resman := new(Resource_Manager)
	setup_resource_manager(resman)
	load_all_assets(resman)

	g = new(Game_Memory)
	g^ = Game_Memory {
		resman = resman,
		audman = audman,
		render_texture = rl.LoadRenderTexture(LOGICAL_SCREEN_WIDTH * RENDER_TEXTURE_SCALE, LOGICAL_SCREEN_HEIGHT * RENDER_TEXTURE_SCALE),
	}
}

// clear collections, set initial values, Game_Memory already "setup"
init :: proc() {
	g.app_state = .Running
	g.debug = false
	g.scene = Play_Scene{}
	g.is_music_enabled = true

	g.board = init_board()

	// TODO: depends on roll. In local play (same machine) Player A is always bot.
	g.is_white_bottom = true
	// play_music(.Music, true)
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
	rl.InitWindow(WINDOW_W, WINDOW_H, "Odin Gamejam Template")
	rl.SetWindowPosition(10, 125)
	rl.SetTargetFPS(TICK_RATE )
	rl.SetExitKey(nil)
}

@(export)
game_init :: proc() {
	log.info("Initializing game...")
	setup() // run once
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
	free(g)
}

@(export)
game_shutdown_window :: proc() {
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
	Reset,
	Toggle_Music,
}

GLOBAL_INPUT_LOOKUP := [Global_Input]rl.KeyboardKey{
	.Toggle_Debug = .GRAVE,
	.Exit = .ESCAPE,
	.Reset = .R,
	.Toggle_Music = .M,
}

process_global_input :: proc() {
	input: bit_set[Global_Input]
	for key, input_ in GLOBAL_INPUT_LOOKUP {
		switch input_ {
		case .Toggle_Debug, .Exit, .Toggle_Music, .Reset:
			if rl.IsKeyPressed(key) {
				input += {input_}
			}
		}
	}
    if .Toggle_Debug in input {
        g.debug = !g.debug
    } else if .Exit in input {
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

Play_Action :: enum {
	Left_Click_Board,
}

// NB: do reverse, offset, then scale
transform_screen_position_to_viewport_position :: proc(pos: Vec2) -> Vec2 {
	offx, offy := get_viewport_offset()
	scale := get_viewport_scale()
	pos := pos
	pos.x += offx
	pos.y += offy
	pos /= scale
	return pos
}

is_mouse_over_board :: proc() -> bool {
	return is_mouse_over_rect(board_bounds.x, board_bounds.y, board_bounds.width, board_bounds.height)
}

EMPTY_TILE :: Tile{piece_type = .None}
process_play_input :: proc(s: ^Play_Scene) {
	// actions: bit_set[Play_Action]

	for action_ in Play_Action {
		action_switch: switch action_ {
		case .Left_Click_Board:
			if mouse_condition := is_mouse_over_board() && rl.IsMouseButtonPressed(.LEFT); !mouse_condition {
				break
			}

			pr("Detected Left Click Board")
			mouse_tile_pos := get_tile_position_from_mouse_already_over_board()

			// if friendly piece, toggle select piece
			clicked_tile, _ := get_tile_by_position(mouse_tile_pos)
			if clicked_tile.piece_type != .None && clicked_tile.piece_color == g.current_player {
				// if clicked tile pos corresponds to current selected piece
				if val := g.selected_piece; val != nil && mouse_tile_pos == g.selected_piece.?.position{
					g.selected_piece = nil
					pr("Action: DeSelect_Piece")
				} else {
					selected_piece := Selected_Piece_Data{
						position = mouse_tile_pos,
						tile = clicked_tile,
						possible_moves = get_possible_moves(mouse_tile_pos),
					}
					g.selected_piece = selected_piece
					pr("Action: Select_Piece")
				}
				break
			}

			// if a piece is already selected:
			if g.selected_piece != nil {
				selected_piece := g.selected_piece.?

				is_possible_move: bool
				// A. If it is a possible move, do it
				for move_result in sa.slice(&selected_piece.possible_moves) {
					if mouse_tile_pos == move_result.position {
						is_possible_move = true
						pr("Action: Piece_Action")

						switch move_result.piece_action {
						case .Travel:
							pr("TRAVEL")
							// Update the selected piece and store in new position
							selected_piece_tile := selected_piece.tile

							// update double move data before has_piece_moved is flagged
							if selected_piece_tile.piece_type == .Pawn && !selected_piece_tile.has_piece_moved && abs(move_result.position.y - selected_piece.position.y) == 2 {
								g.board.last_double_move_turn = g.n_turns
								g.board.last_double_move_end_position = move_result.position
							}

							curr_pos := selected_piece.position
							set_tile(curr_pos, EMPTY_TILE)

							new_tile := selected_piece_tile
							new_tile.has_piece_moved = true
							new_pos := mouse_tile_pos
							set_tile(new_pos, new_tile)

							end_turn()

						case .En_Passant:
							// Captured piece in special position
							pr("EN PASSANT")
							selected_piece_tile := selected_piece.tile

							curr_pos := selected_piece.position
							set_tile(curr_pos, EMPTY_TILE)

							new_pos := mouse_tile_pos

							captured_position := g.last_double_move_end_position
							captured_tile, _ := get_tile_by_position(captured_position)
							if g.current_player == .White {
								sa.push(&g.board.white_captures, captured_tile.piece_type)
							} else {
								sa.push(&g.board.black_captures, captured_tile.piece_type)
							}
							set_tile(captured_position, EMPTY_TILE)

							new_tile := selected_piece_tile
							new_tile.has_piece_moved = true
							set_tile(new_pos, new_tile)

							update_points(g.current_player, captured_tile.piece_type)

							end_turn()

						case .Capture:
							// Captured piece in new position
							// Update the selected piece and store in new position
							pr("CAPTURE")
							selected_piece_tile := selected_piece.tile

							curr_pos := selected_piece.position
							set_tile(curr_pos, EMPTY_TILE)

							new_pos := mouse_tile_pos

							captured_tile, _ := get_tile_by_position(new_pos)
							if g.current_player == .White {
								sa.push(&g.board.white_captures, captured_tile.piece_type)
							} else {
								sa.push(&g.board.black_captures, captured_tile.piece_type)
							}

							new_tile := selected_piece_tile
							new_tile.has_piece_moved = true
							set_tile(new_pos, new_tile)

							end_turn()

						case .Kingside_Castle:
							pr("KINGSIDE CASTLE")
						case .Queenside_Castle:
							pr("QUEENSIDE CASTLE")
						case .None:
							unreachable()
						}
						break action_switch // TODO: test can this break to the switch?
					}
				}

				// B. If not a possible move (and not friendly), deselect
				if !is_possible_move {
					g.selected_piece = nil
					pr("Action: Deselect_Piece")
				}
			}
		}
	}

	if rl.IsKeyPressed(.P) do s.is_paused = !s.is_paused
	if s.is_paused do return
}

draw_sprite :: proc(texture_id: Texture_ID, pos: Vec2, size: Vec2, rotation: f32 = 0, scale: f32 = 1, tint: rl.Color = rl.WHITE) {
	tex := get_texture(texture_id)
	src_rect := rl.Rectangle {
		0, 0, f32(tex.width), f32(tex.height),
	}
	dst_rect := rl.Rectangle {
		pos.x, pos.y, size.x, size.y,
	}
	rl.DrawTexturePro(tex, src_rect, dst_rect, {}, rotation, tint)
}

aabb_intersects :: proc(a_x, a_y, a_w, a_h: f32, b_x, b_y, b_w, b_h: f32) -> bool {
    return !(a_x + a_w < b_x ||
           b_x + b_w < a_x ||
           a_y + a_h < b_y ||
           b_y + b_h < a_y)
}

circle_intersects:: proc(a_pos: Vec2, a_radius: f32, b_pos: Vec2, b_radius: f32) -> bool {
	return linalg.length2(a_pos - b_pos) < (a_radius + b_radius) * (a_radius + b_radius)
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
	src := rl.Rectangle{0, 0, render_texture_width, -render_texture_height} // negative height flips texture
	dst := rl.Rectangle{-offset_x, -offset_y, viewport_width, viewport_height}
	rl.DrawTexturePro(g.render_texture.texture, src, dst, {}, 0, rl.WHITE)
	rl.EndDrawing()
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

Piece_Type :: enum {
	None,
	Pawn,
	Rook,
	Knight,
	Bishop,
	Queen,
	King,
}

Tile :: struct {
	piece_type: Piece_Type,
	piece_color: Piece_Color,
	has_piece_moved: bool,
}

Piece_Color :: enum u8 {
	White, Black,
}

// corresponds to [a-h][1-8]
// contains board-specific gameplay state
Board :: struct {
	tiles: [8][8]Tile,
	n_turns: i32,
	current_player: Player_Color,

	last_double_move_end_position: Position,
	last_double_move_turn: i32,

	is_white_king_checked: bool,
	is_black_king_checked: bool,
	white_captures: sa.Small_Array(15, Piece_Type),
	black_captures: sa.Small_Array(15, Piece_Type),
	points: [Player_Color]i32
}

// Also tests for board boundary
get_tile_by_position :: proc(pos: Position) -> (tile: Tile, in_bounds: bool) {
	if pos.x < 0 || pos.x > 7 || pos.y < 0 || pos.y > 7 {
		return {}, false
	}
	return g.board.tiles[pos.y][pos.x], true
}

init_board :: proc() -> Board {
	positions_with_pieces := [8][8]Piece_Type{
		{.Rook, .Knight, .Bishop, .Queen, .King, .Bishop, .Knight, .Rook},
		{.Pawn,.Pawn,.Pawn,.Pawn,.Pawn,.Pawn,.Pawn,.Pawn,},
		{}, {}, {}, {},
		{.Pawn,.Pawn,.Pawn,.Pawn,.Pawn,.Pawn,.Pawn,.Pawn,},
		{.Rook, .Knight, .Bishop, .Queen, .King, .Bishop, .Knight, .Rook},
	}
	tiles: [8][8]Tile
	for row, y in positions_with_pieces {
		for piece_type, x in row {
			tiles[y][x] = {
				piece_type = piece_type,
				piece_color = y <= 1 ? .White : .Black
			}
		}
	}
	return {
		tiles = tiles,
		n_turns = 1,
		current_player = .White,
	}
}

Move_Result :: struct {
	position: Position,
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
MAX_ELEMENTS_FOR_MOVE_RESULTS :: 64
Move_Results :: sa.Small_Array(MAX_ELEMENTS_FOR_MOVE_RESULTS, Move_Result)

get_possible_moves :: proc(pos: Position) -> Move_Results {
	tile, _ := get_tile_by_position(pos)
	// TODO: special moves
	// NB: moves beyond captures or beyond board
	// assume white bottom unless false
	// Either check landing spots (knight) or cast a ray (stop at collision)

	color_and_side_factor: i32 = tile.piece_color == .White ? 1 : -1
	color_and_side_factor *= g.is_white_bottom ? 1 : -1

	arr: Move_Results
	#partial switch tile.piece_type {
	case .Pawn:
		// CASE pawn en passants, forced move: if possible then this is player's only move
		// TODO: refactor this to precede selection/move logic (for now keep here for testing)
		// Must run this code before player selects a piece and notify him (highlight / tooltip / flashing piece / "En Passant Triggered")

		// this pawn is on 5th rank (white) or 4th rank (black)
		is_pawn_on_passant_row_condition_satisfied: bool
		if (pos.y == 4 && g.current_player == .White) || (pos.y == 3 && g.current_player == .Black) {
			is_pawn_on_passant_row_condition_satisfied = true
		}

		// last double move was previous turn and is adjacent to this pawn
		is_double_move_condition_satisfied: bool
		if (g.last_double_move_turn == g.board.n_turns - 1) && (g.last_double_move_end_position.x == pos.x - 1 || g.last_double_move_end_position.x == pos.x + 1) {
			is_double_move_condition_satisfied = true
		}

		if is_pawn_on_passant_row_condition_satisfied && is_double_move_condition_satisfied {
			// capture end position is effectively behind the double moved pawn
			capture_position := g.board.last_double_move_end_position 
			capture_offset_y: i32 = g.board.current_player == .White ? 1 : -1
			capture_position.y += capture_offset_y
			sa.push(&arr, Move_Result{position = capture_position, piece_action = .En_Passant})
			return arr
		}

		// CASE pawn basic move
		move_direction := Position{0,1} * color_and_side_factor

		// cast ray of length 1 for basic move
		pos_0 := pos + move_direction
		if tile_0, in_bounds := get_tile_by_position(pos_0); tile_0.piece_type == .None && in_bounds {
			sa.push(&arr, Move_Result{position = pos_0, piece_action = .Travel})
		} 

		// cast ray of length 2 for first move
		if !tile.has_piece_moved {
			pos_1 := pos + move_direction * 2
			if tile_1, in_bounds := get_tile_by_position(pos_1); tile_1.piece_type == .None && in_bounds {
				sa.push(&arr, Move_Result{position = pos_1, piece_action = .Travel})
			}
		}

		// CASE pawn captures
		// TODO: redo capture logic, only do the move if it's enemy
		capture_position_right_1 := pos + Position{1,1} * color_and_side_factor
		tile_cap_right_1, _ := get_tile_by_position(capture_position_right_1)
		if tile_cap_right_1.piece_type != .None && tile_cap_right_1.piece_color != g.current_player {
			sa.push(&arr, Move_Result{position = capture_position_right_1, piece_action = .Capture})
		}

		capture_position_left_1 := pos + Position{-1,1} * color_and_side_factor
		tile_cap_left_1, _ := get_tile_by_position(capture_position_left_1)
		if tile_cap_left_1.piece_type != .None && tile_cap_left_1.piece_color != g.current_player {
			sa.push(&arr, Move_Result{position = capture_position_left_1, piece_action = .Capture})
		}

	}
	return arr
}

get_tile_position_from_mouse_already_over_board :: proc() -> Position {
	mouse_pos := get_mouse_position()

	// from tile coords origin (bot left board)
	dx := math.round(mouse_pos.x - board_bounds.x)
	dy := math.round(board_bounds.y + board_bounds.height - mouse_pos.y)

	return {i32(math.floor(dx / tile_size)), i32(math.floor(dy / tile_size))}
}

set_tile :: proc(pos: Position, tile: Tile) {
	pr("set board tile to this", tile)
	g.board.tiles[pos.y][pos.x] = tile
}

end_turn :: proc() {
	g.selected_piece = nil
	g.n_turns += 1
	switch g.current_player {
	case .Black: g.current_player = .White
	case .White: g.current_player = .Black
	}
}

update_points :: proc(current_player: Player_Color, piece_type: Piece_Type) {
	g.board.points[current_player] += PIECE_POINTS[piece_type]
}
