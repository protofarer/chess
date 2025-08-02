package game

import "core:fmt"
import "core:log"
import "core:math/linalg"
import "core:math"
import "core:time"
import "core:time/datetime"
import "core:time/timezone"
import "core:strings"
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

BOARD_LENGTH :: 8
EMPTY_TILE :: Tile{piece_type = .None, piece_color = .None}

Game_Memory :: struct {
	app_state: App_State,
	debug: bool,
	resman: ^Resource_Manager,
	render_texture: rl.RenderTexture,
	scene: Scene,
	audman: Audio_Manager,
	is_music_enabled: bool,
	using board: Board,
	time: struct {
		local_timezone: ^datetime.TZ_Region,
		game_start_datetime: datetime.DateTime,
		game_end_datetime: datetime.DateTime,
		game_start: time.Tick,
		game_duration: time.Duration,
		turn_start: time.Tick,
		turn_duration: time.Duration,
		players_duration: [Player_Color]time.Duration,
	},
}

MAX_SMALL_ARRAY_CAPTURE_COUNT :: 16
// corresponds to [a-h][1-8]
// contains board-specific gameplay state
Board :: struct {
	tiles: [BOARD_LENGTH][BOARD_LENGTH]Tile,
	n_turns: i32,
	current_player: Player_Color,
	is_white_bottom: bool, // predom for multiplayer

	selected_piece: Maybe(Selected_Piece_Data),

	last_double_move_end_position: Position,
	last_double_move_turn: i32,

	is_white_king_checked: bool,
	is_black_king_checked: bool,
	captures: [Player_Color]sa.Small_Array(MAX_SMALL_ARRAY_CAPTURE_COUNT, Piece_Type),
	points: [Player_Color]i32,

	threatened_positions: sa.Small_Array(BOARD_LENGTH * BOARD_LENGTH, Move_Result),
	is_check: bool,
	message: cstring,
}

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
	is_paused: bool,
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

Tile :: struct {
	piece_type: Piece_Type,
	piece_color: Piece_Color,
	has_piece_moved: bool,
}

Piece_Color :: enum u8 {
	None, White, Black,
}


Player_Color :: Piece_Color

Selected_Piece_Data :: struct {
	position: Position,
	tile: Tile,
	possible_moves: Move_Results,
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

g: ^Game_Memory

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

	// rl.InitAudioDevice()
	// audman := init_audio_manager()

	resman := new(Resource_Manager)
	setup_resource_manager(resman)
	load_all_assets(resman)
	rl.GuiLoadStyle("assets/style_amber.rgs")

	g = new(Game_Memory)
	g^ = Game_Memory {
		resman = resman,
		render_texture = rl.LoadRenderTexture(LOGICAL_SCREEN_WIDTH * RENDER_TEXTURE_SCALE, LOGICAL_SCREEN_HEIGHT * RENDER_TEXTURE_SCALE),
		// audman = audman,
	}

	offx, offy := get_viewport_offset()
	scale := get_viewport_scale()
	rl.SetMouseOffset(i32(offx), i32(offy))
	rl.SetMouseScale(1/scale, 1/scale)
}

// clear collections, set initial values, Game_Memory already "setup"
init :: proc() {
	g.app_state = .Running
	g.debug = false
	g.scene = Play_Scene{}
	g.is_music_enabled = true

	g.board = init_board()

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

	// TODO: depends on roll. In local play (same machine) Player White is always bot.
	g.is_white_bottom = true
	// play_music(.Music, true)
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

update :: proc() {
	process_global_input()

	// next_scene: Maybe(Scene) = nil
	switch &s in g.scene {
	case Play_Scene:
		action := process_play_input(&s)

		proposed_move_result, is_move_proposed := propose_move(action)
		if is_move_proposed do pr("IS MOVE PROPOSED", is_move_proposed)

		if is_move_proposed {
			move_result, is_legal := eval_move(proposed_move_result)
			if is_legal {
				update_board(move_result)
				end_turn()
				eval_board()
			}
		}


		g.time.game_duration = time.tick_since(g.time.game_start)
		g.time.turn_duration = time.tick_since(g.time.turn_start)
	}
}

eval_move :: proc(proposed_move_result: Move_Result) -> (move_result: Move_Result, is_legal: bool) {
	// TODO: test for legality, if illegal emit message
	// use get_actual_possible_moves_for_player, restricts moves:
	// - check
	// - checkmate
	// - en passant force
	// TODO: need to emit illegal move message. Get_actual_possible_moves or someone needs to determine what kind of illegal move was made
	// - when current player is_check, 
	return proposed_move_result, true
}

propose_move :: proc(action: Play_Action) -> (move_result: Move_Result, is_move_proposed: bool) {
	// First, position and existence changes are made: move, capture, special move initiation
	// Second, "Subsequent state resolution": promotion, followup submoves (castling), check, 
	action_switch: switch action {
	case .Left_Click_Board:
		mouse_tile_pos := get_tile_position_from_mouse_already_over_board()
		
		selected_piece, is_piece_selected := g.selected_piece.?
		if !is_piece_selected {
			// Select a friendly piece
			clicked_tile, _ := get_tile_by_position(mouse_tile_pos)
			if clicked_tile.piece_type != .None && clicked_tile.piece_color == g.current_player {
				new_selected_piece := Selected_Piece_Data{
					position = mouse_tile_pos,
					tile = clicked_tile,
					possible_moves = get_possible_moves(mouse_tile_pos, g.current_player),
				}
				g.selected_piece = new_selected_piece
				pr("Action: Select_Piece")
			} else {
				pr("Action: None")
			}
			move_result = {}
			is_move_proposed = false
			return

		} else {
			// Since a piece already selected: deselect if clicked selected piece else select new piece
			// aka toggle selection friendly piece
			clicked_tile, _ := get_tile_by_position(mouse_tile_pos)
			if clicked_tile.piece_type != .None && clicked_tile.piece_color == g.current_player {
				if selected_piece.position == mouse_tile_pos {
					g.selected_piece = nil
					pr("Action: DeSelect_Piece")
				} else {
					new_selected_piece := Selected_Piece_Data{
						position = mouse_tile_pos,
						tile = clicked_tile,
						possible_moves = get_possible_moves(mouse_tile_pos, g.current_player),
					}
					g.selected_piece = new_selected_piece
					pr("Action: Select_Piece")
				}
				move_result = {}
				is_move_proposed = false
				return
			}

			// Either clicked on: 
			// - tile that's not movable to
			// - tile that's movable to (possible move)
			// This results in any:
			// - basic move aka travel
			// - capture
			// - special move

			// A. If it is a possible move, do it
			for possible_move in sa.slice(&selected_piece.possible_moves) {
				if mouse_tile_pos == possible_move.position {
					move_result = possible_move
					is_move_proposed = true
					return
				}
			}

			// B. If clicked tile not a possible move
			g.selected_piece = nil
			pr("Action: Deselect_Piece")
			is_move_proposed = false
			return
		}

		is_move_proposed = false
		return
	case .None:
		is_move_proposed = false
		return
	}
	unreachable()

}

update_board :: proc(move_result: Move_Result) {
	if move_result.piece_action == .None {
		return
	}
	pr("Action: Piece_Action")

	selected_piece := g.selected_piece.?

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
		new_pos := move_result.position
		set_tile(new_pos, new_tile)

	case .En_Passant:
		// Captured piece is in en passant capture position
		pr("EN PASSANT")
		curr_pos := selected_piece.position
		set_tile(curr_pos, EMPTY_TILE)

		new_pos := move_result.position

		captured_position := g.last_double_move_end_position
		captured_tile, _ := get_tile_by_position(captured_position)
		sa.push(&g.board.captures[g.current_player], captured_tile.piece_type)
		set_tile(captured_position, EMPTY_TILE)

		new_tile := selected_piece.tile
		new_tile.has_piece_moved = true
		set_tile(new_pos, new_tile)

		update_points(g.current_player, captured_tile.piece_type)

	case .Capture:
		// Captured piece is in selected piece's new position
		pr("CAPTURE")
		curr_pos := selected_piece.position
		set_tile(curr_pos, EMPTY_TILE)

		new_pos := move_result.position

		captured_tile, _ := get_tile_by_position(new_pos)
		sa.push(&g.board.captures[g.current_player], captured_tile.piece_type)

		new_tile := selected_piece.tile
		new_tile.has_piece_moved = true
		set_tile(new_pos, new_tile)

		update_points(g.current_player, captured_tile.piece_type)

	case .Kingside_Castle:
		pr("KINGSIDE CASTLE")
	case .Queenside_Castle:
		pr("QUEENSIDE CASTLE")
	case .None:

	}
}

// All this does is flag check or checkmate
// This is called at start of next player's turn
eval_board :: proc() {
	pr("EVAL BOARD for player", g.current_player)
	if is_king_threatened(g.current_player) {
		pr("SET CHECK TRUE")
		g.board.is_check = true
	}
}

is_king_threatened :: proc(player_color: Player_Color) -> bool {
	// does any enemy piece threaten current king?
	positions_threatened := get_threatened_positions(player_color)
	pr("N positions threatened", sa.len(positions_threatened))
	king_pos := get_king_position(player_color)
	for pos in sa.slice(&positions_threatened) {
		pr("pos threated", pos)
		if king_pos == pos {
			pr("KING iS THREATENED YES")
			return true
		}
	}
	return false
}

get_king_position :: proc(player_color: Player_Color) -> Position {
	for row, y in g.board.tiles {
		for tile, x in row {
			if tile.piece_type == .King && tile.piece_color == player_color {
				return Position{i32(x),i32(y)}
			}
		}
	}
	log.error("Failed to get king position, no king exists for player:", player_color)
	return {}
}

get_threatened_positions :: proc(player_being_threatened: Player_Color) -> (threatened_positions: sa.Small_Array(BOARD_LENGTH * BOARD_LENGTH, Position)) {
	// for every possible move, just keep position
	actual_possible_moves := get_actual_possible_moves_for_player(get_other_player_color(player_being_threatened))
	for actual_possible_move in sa.slice(&actual_possible_moves) {
		if actual_possible_move.piece_action == .En_Passant {
			captured_position := g.last_double_move_end_position
			sa.push(&threatened_positions, captured_position)
			return
		} else if actual_possible_move.piece_action == .Capture {
			sa.push(&threatened_positions, actual_possible_move.position)
		}
	}
	return
}

// Filtered moves aka only moves player can take, as opposed to all possible moves without restriction
get_actual_possible_moves_for_player :: proc(player_color: Player_Color) -> (actual_possible_moves: sa.Small_Array(BOARD_LENGTH * BOARD_LENGTH, Move_Result)) {
	tile_positions: sa.Small_Array(16, Position)
	for row, y in g.board.tiles {
		for tile, x in row {
			if tile.piece_type != .None && tile.piece_color == player_color {
				sa.push(&tile_positions, Position{i32(x), i32(y)})
			}
		}
	}

	for pos in sa.slice(&tile_positions) {
		possible_moves := get_possible_moves(pos, player_color)
		for move in sa.slice(&possible_moves) {
			// must be only move then
			if move.piece_action == .En_Passant {
				sa.clear(&actual_possible_moves)
				sa.push(&actual_possible_moves, move)
				return
			} else {
				sa.push(&actual_possible_moves, move)
			}
		}
	}
	return
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

draw :: proc() {
	begin_letterbox_rendering()

	switch &s in g.scene {
	case Play_Scene:
		// Draw board checkered tiles
		for y in 0..<BOARD_LENGTH {
			for x in 0..< BOARD_LENGTH {
				color: rl.Color
				if ((y*BOARD_LENGTH) + x) % 2 == 0 {
					color = y % 2 == 1 ? LIGHT_TILE_COLOR :  DARK_TILE_COLOR
				} else {
					color = y % 2 == 1 ? DARK_TILE_COLOR : LIGHT_TILE_COLOR
				}
				rl.DrawRectangle(i32(math.round(BOARD_BOUNDS.x + f32(x) * TILE_SIZE)), i32(math.round(BOARD_BOUNDS.y + f32(y) * TILE_SIZE)), i32(math.round(TILE_SIZE)), i32(math.round(TILE_SIZE)), color)
			}
		}

		// Draw pieces
		for row, y in g.board.tiles {
			for tile, x in row {
				draw_piece_on_board(tile.piece_type, tile.piece_color, {i32(x),i32(y)})
			}
		}

		if selected_piece, ok := g.selected_piece.?; ok {
			selected_piece_tile_pos := selected_piece.position

			// Highlight selected piece
			draw_tile_border(selected_piece_tile_pos, rl.GREEN)

			// Draw possible moves
			for move_result in sa.slice(&selected_piece.possible_moves) {
				draw_tile_border(move_result.position, rl.PURPLE)
			}
		}

		if g.board.is_check {
			// Highlight king in check or checkmate
			king_pos := get_king_position(g.current_player)
			draw_tile_border(king_pos, rl.RED)
		}

		// Debug text
		if g.debug {
			// draw tile borders via grid
			for y in 0..<9 {
				rl.DrawLine(
					i32(math.floor(BOARD_BOUNDS.x + 0)), 
					i32(BOARD_BOUNDS.y + f32(y) * TILE_SIZE), 
					i32(math.floor(BOARD_BOUNDS.x + BOARD_BOUNDS.width)), // for error: cannot be rep w/o truncate/round as type i32
					i32(BOARD_BOUNDS.y + f32(y) * TILE_SIZE), 
					rl.BLUE,
				)
			}
			for x in 0..<9 {
				rl.DrawLine(
					i32(BOARD_BOUNDS.x + f32(x) * TILE_SIZE), 
					i32(BOARD_BOUNDS.y + 0), 
					i32(BOARD_BOUNDS.x + f32(x) * TILE_SIZE), 
					i32(BOARD_BOUNDS.y + BOARD_BOUNDS.height), 
					rl.BLUE,
				)
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
		}
		if s.is_paused {
			rl.DrawRectangle(0, 0, 90, 90, {0, 0, 0, 180})
			rl.DrawText("PAUSED", 90, 90, 30, rl.WHITE)
		}
	}

	rl.BeginMode2D(ui_camera())
		// Transform mouse for gui
		// offx, offy := get_viewport_offset()
		// scale := get_viewport_scale()
		// rl.SetMouseOffset(i32(offx), i32(offy))
		// rl.SetMouseScale(1/scale, 1/scale)

		// Top Status Bar
		{
			rl.GuiStatusBar({0,0,LOGICAL_SCREEN_WIDTH, TOPBAR_HEIGHT}, "")
			y :f32= 4
			if rl.GuiButton({5,y,70,15}, "New Game") do pr("Click New Game")
			if rl.GuiButton({100,y,70,15}, "Draw") do pr("Click Draw")
			rl.DrawText(make_duration_display_string(get_game_duration()), 220, 7, 8, rl.WHITE)
			rl.DrawText(fmt.ctprintf("Turn: %v", g.board.n_turns), 300, 7, 8, rl.WHITE)
			if rl.GuiButton({450,y,70,15}, "Exit") {
				 pr("Click Exit")
				 g.app_state = .Exit
			}
			// TODO: draw text g.board.message (mostly illegal moves)
			// TODO: flash timer, then hold
			g.board.message = fmt.ctprintf("Illegal move, king is checked.......")
			rl.DrawText(g.board.message, 180, 27, 8, rl.RED)
		}

		// White Panel (Left)
		{
			white_panel_bounds := LEFT_PANEL_BOUNDS
			rl.GuiPanel(white_panel_bounds, nil)
			x0 := white_panel_bounds.x
			y0 := white_panel_bounds.y

			x := x0 + 3
			y := y0 + 3
			rl.GuiLabel({x, y, white_panel_bounds.width, 10}, "White")

			if g.current_player == .White {
				y += 15
				cstr := make_duration_display_string(get_turn_duration())
				rl.GuiLabel({x, y, 100, 10}, cstr)
			}

			// Show cap pieces from bottom up
			xcap :i32= i32(x0 + 10)
			ycap :i32= i32(white_panel_bounds.y + white_panel_bounds.height) - 30 * 9
			for piece_type,i in sa.slice(&g.board.captures[.White]) {
				if i % 8 == 0 && i > 0 {
					 xcap += 40
					 ycap -= 240
				}
				ycap += 30
				draw_piece(piece_type, .Black, xcap,ycap)
			}
		}
		
		// Black Panel (Right)
		{
			black_panel_bounds := RIGHT_PANEL_BOUNDS
			rl.GuiPanel(black_panel_bounds, nil)
			x0 := black_panel_bounds.x
			y0 := black_panel_bounds.y

			x := x0 + 3
			y := y0 + 3
			rl.GuiLabel({x, y, black_panel_bounds.width, 10}, "black")

			if g.current_player == .Black {
				y += 15
				cstr := make_duration_display_string(get_turn_duration())
				rl.GuiLabel({x, y, 100, 10}, cstr)
			}

			// Show cap pieces from bottom up
			xcap :i32= i32(x0 + 10)
			ycap :i32= i32(black_panel_bounds.y + black_panel_bounds.height) - 30 * 9
			for piece_type,i in sa.slice(&g.board.captures[.Black]) {
				if i % 8 == 0 && i > 0 {
					 xcap += 40
					 ycap -= 240
				}
				ycap += 30
				draw_piece(piece_type, .White, xcap,ycap)
			}
		}
	rl.EndMode2D()

	end_letterbox_rendering()

	// Debug overlay
	debug_overlay_text_block :: proc(x,y: ^i32, slice_cstr: []cstring) {
		gy: i32 = 20
		for s in slice_cstr {
			rl.DrawText(s, x^, y^, 20, rl.WHITE)
			y^ += gy
		}
	}
	if g.debug {
		{
			x: i32 = 5
			y: i32 = 40
			arr := [?]cstring{
				fmt.ctprintf("game_duration: %v", make_duration_display_string(get_game_duration())),
				fmt.ctprintf("turn_duration: %v", make_duration_display_string(get_turn_duration())),
				fmt.ctprintf("white running: %v", make_duration_display_string(g.time.players_duration[.White])),
				fmt.ctprintf("black running: %v", make_duration_display_string(g.time.players_duration[.Black])),
				fmt.ctprintf("game_start_datetime: %v", make_datetime_display_string(g.time.game_start_datetime)),
				fmt.ctprintf("game_end_datetime: %v", make_datetime_display_string(g.time.game_end_datetime)),
			}
			debug_overlay_text_block(&x, &y, arr[:])

			arr2 := [?]cstring{
				fmt.ctprintf("mouse_pos: %v", rl.GetMousePosition()),
				fmt.ctprintf("mouse_tile_pos: %v", get_tile_position_from_mouse_already_over_board()),
			}
			y += 40
			debug_overlay_text_block(&x, &y, arr2[:])
			// game start
			// game running
			// turn start
			// turn running
			// players running

			// curr player
			// points
			// captures
			// selected piece
			// num turns
		}
	}
	rl.EndDrawing()
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
// TODO: keyboard inputs: "?" for help modal, h toggle possible moves

Play_Action :: enum {
	None,
	Left_Click_Board,
}

is_mouse_over_board :: proc() -> bool {
	return is_mouse_over_rect(BOARD_BOUNDS.x, BOARD_BOUNDS.y, BOARD_BOUNDS.width, BOARD_BOUNDS.height)
}

process_play_input :: proc(s: ^Play_Scene) -> Play_Action {
	if is_mouse_over_board() && rl.IsMouseButtonPressed(.LEFT) {
		return .Left_Click_Board
	}
	return .None
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
	return fmt.ctprintf("%v %v, %v %v:%v:%v", get_month_by_seq(dt.month), dt.day, dt.year, dt.hour, dt.minute, dt.second)
}

// get position of top left corner of tile in render (render logical) coords from game logical coords board tile pos
board_tile_pos_to_sprite_logical_render_pos :: proc(x, y: i32) -> Vec2 {
	// origin is bottom left of board
	pos := Vec2{BOARD_BOUNDS.x + f32(x) * TILE_SIZE, BOARD_BOUNDS.y + BOARD_BOUNDS.height - f32(y+1) * TILE_SIZE}
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
	src := rl.Rectangle{0, 0, render_texture_width, -render_texture_height} // negative height flips texture
	dst := rl.Rectangle{-offset_x, -offset_y, viewport_width, viewport_height}
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
get_tile_by_position :: proc(pos: Position) -> (tile: Tile, in_bounds: bool) {
	if !is_in_bounds(pos.x, pos.y){
		return {}, false
	}
	return g.board.tiles[pos.y][pos.x], true
}

init_board :: proc() -> Board {
	positions_with_pieces := [BOARD_LENGTH][BOARD_LENGTH]Piece_Type{
		{.Rook, .Knight, .Bishop, .Queen, .King, .Bishop, .Knight, .Rook},
		{.Pawn,.Pawn,.Pawn,.Pawn,.Pawn,.Pawn,.Pawn,.Pawn,},
		{}, {}, {}, {},
		{.Pawn,.Pawn,.Pawn,.Pawn,.Pawn,.Pawn,.Pawn,.Pawn,},
		{.Rook, .Knight, .Bishop, .Queen, .King, .Bishop, .Knight, .Rook},
	}
	tiles: [BOARD_LENGTH][BOARD_LENGTH]Tile
	for row, y in positions_with_pieces {
		for piece_type, x in row {
			piece_color: Piece_Color = .None
			if y <= 1 {
				piece_color = .White
			} else if y >= 6 {
				piece_color = .Black
			}
			tiles[y][x] = {
				piece_type = piece_type,
				piece_color = piece_color,
			}
		}
	}
	return Board{
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

get_possible_moves :: proc(pos: Position, player_color: Player_Color) -> Move_Results {
	tile, _ := get_tile_by_position(pos)
	// NB: moves beyond captures or beyond board
	// assume standard board orientation, white bottom unless g.is_white_bottom false

	// aka color and side factor
	flip_factor: i32 = tile.piece_color == .White ? 1 : -1
	flip_factor *= g.is_white_bottom ? 1 : -1

	arr: Move_Results
	#partial top_switch: switch tile.piece_type {
	case .Pawn:
		// CASE pawn en passants, forced move: if possible then this is player's only move
		// TODO: refactor this to precede selection/move logic (for now keep here for testing)
		// Must run this code before player selects a piece and notify him (highlight / tooltip / flashing piece / "En Passant Triggered")

		// this pawn is on 5th rank (white) or 4th rank (black)
		is_pawn_on_passant_row_condition_satisfied: bool
		if (pos.y == 4 && player_color == .White) || (pos.y == 3 && player_color == .Black) {
			is_pawn_on_passant_row_condition_satisfied = true
		}

		// last double move was previous turn and is adjacent to this pawn
		is_double_move_condition_satisfied: bool
		// NB: move_turn >= n_turns - 1 because this fn is also used for checking for threatened positions, in which case the moveturn is +1
		if (g.last_double_move_turn >= g.board.n_turns - 1) && (g.last_double_move_end_position.x == pos.x - 1 || g.last_double_move_end_position.x == pos.x + 1) {
			is_double_move_condition_satisfied = true
		}

		if is_pawn_on_passant_row_condition_satisfied && is_double_move_condition_satisfied {
			// capture end position is effectively behind the double moved pawn
			capture_position := g.board.last_double_move_end_position 
			capture_offset_y: i32 = player_color == .White ? 1 : -1
			capture_position.y += capture_offset_y
			sa.push(&arr, Move_Result{position = capture_position, piece_action = .En_Passant})
			break top_switch
		}

		// CASE pawn basic move
		move_direction := Position{0,1} * flip_factor

		// cast ray of length 1 for basic move
		pos_0 := pos + move_direction
		tile_0, in_bounds := get_tile_by_position(pos_0)
		if tile_0.piece_type == .None && in_bounds {
			sa.push(&arr, Move_Result{position = pos_0, piece_action = .Travel})
		} 

		// cast ray of length 2 for first move
		if !tile.has_piece_moved {
			pos_1 := pos + move_direction * 2
			tile_1, ray2_in_bounds := get_tile_by_position(pos_1)
			if tile_0.piece_type == .None && tile_1.piece_type == .None && ray2_in_bounds {
				sa.push(&arr, Move_Result{position = pos_1, piece_action = .Travel})
			}
		}

		// CASE pawn captures
		capture_position_right_1 := pos + Position{1,1} * flip_factor
		tile_cap_right_1, _ := get_tile_by_position(capture_position_right_1)
		if tile_cap_right_1.piece_type != .None && tile_cap_right_1.piece_color != player_color {
			sa.push(&arr, Move_Result{position = capture_position_right_1, piece_action = .Capture})
		}

		capture_position_left_1 := pos + Position{-1,1} * flip_factor
		tile_cap_left_1, _ := get_tile_by_position(capture_position_left_1)
		if tile_cap_left_1.piece_type != .None && tile_cap_left_1.piece_color != player_color {
			sa.push(&arr, Move_Result{position = capture_position_left_1, piece_action = .Capture})
		}
		return arr

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
			if target_tile, in_bounds := get_tile_by_position(target_pos); in_bounds {
				if target_tile.piece_type == .None {
					sa.push(&arr, Move_Result{position = target_pos, piece_action = .Travel})
				} else if target_tile.piece_color != player_color {
					sa.push(&arr, Move_Result{position = target_pos, piece_action = .Capture})
				}
			}
		}

	case .Bishop:
		move_directions := DIAGONAL_DIRECTIONS
		for dir in move_directions {
			// cast ray until: intersect piece or out of bounds
			bishop_ray: for i in 1..<BOARD_LENGTH {
				// TODO: dont need flip_factor for biship, rook, queen, king, since moves are symmetric?
				target_pos := pos + (dir * i32(i))
				target_tile, in_bounds := get_tile_by_position(target_pos)
				if !in_bounds || target_tile.piece_color == player_color {
					break bishop_ray
				}
				if is_enemy_piece(target_tile, player_color) {
					sa.push(&arr, Move_Result{position = target_pos, piece_action = .Capture})
					break bishop_ray
				}
				// empty tile
				sa.push(&arr, Move_Result{position = target_pos, piece_action = .Travel})
			}
		}

	case .Rook:
		move_directions := CARDINAL_DIRECTIONS
		for dir in move_directions {
			rook_ray: for i in 1..<BOARD_LENGTH {
				// cast ray until: hit piece or out of bounds
				target_pos := pos + (dir * i32(i))
				target_tile, in_bounds := get_tile_by_position(target_pos)
				if !in_bounds || target_tile.piece_color == player_color {
					break rook_ray
				}
				if is_enemy_piece(target_tile, player_color){
					sa.push(&arr, Move_Result{position = target_pos, piece_action = .Capture})
					break rook_ray
				}
				// empty tile
				sa.push(&arr, Move_Result{position = target_pos, piece_action = .Travel})
			}
		}
	
	case .Queen:
		move_directions := ALL_DIRECTIONS
		for dir in move_directions {
			queen_ray: for i in 1..<BOARD_LENGTH {
				// cast ray until: hit piece or out of bounds
				target_pos := pos + (dir * i32(i))
				target_tile, in_bounds := get_tile_by_position(target_pos)
				if !in_bounds || target_tile.piece_color == player_color {
					break queen_ray
				}
				if is_enemy_piece(target_tile, player_color) {
					sa.push(&arr, Move_Result{position = target_pos, piece_action = .Capture})
					break queen_ray
				}
				// empty tile
				sa.push(&arr, Move_Result{position = target_pos, piece_action = .Travel})
			}
		}
	case .King:
		move_directions := ALL_DIRECTIONS
		for dir in move_directions {
			// cast ray until: hit piece or out of bounds
			target_pos := pos + dir
			target_tile, in_bounds := get_tile_by_position(target_pos)
			if !in_bounds {
				continue
			}
			if target_tile.piece_color == player_color  {
				continue
			}
			if target_tile.piece_color != player_color && target_tile.piece_type != .None {
				sa.push(&arr, Move_Result{position = target_pos, piece_action = .Capture})
				continue
			}
			// empty tile
			sa.push(&arr, Move_Result{position = target_pos, piece_action = .Travel})
		}
	}
	return arr
}

get_tile_position_from_mouse_already_over_board :: proc() -> Position {
	mouse_pos := get_mouse_position()

	// from tile coords origin (bot left board)
	dx := math.round(mouse_pos.x - BOARD_BOUNDS.x)
	dy := math.round(BOARD_BOUNDS.y + BOARD_BOUNDS.height - mouse_pos.y)

	return {i32(math.floor(dx / TILE_SIZE)), i32(math.floor(dy / TILE_SIZE))}
}

set_tile :: proc(pos: Position, tile: Tile) {
	g.board.tiles[pos.y][pos.x] = tile
}

end_turn :: proc() {
	g.selected_piece = nil
	g.n_turns += 1
	g.time.players_duration[g.current_player] += g.time.turn_duration
	g.time.turn_start = time.tick_now()
	switch g.current_player {
	case .Black: g.current_player = .White
	case .White: g.current_player = .Black
	case .None: unreachable()
	}
}

update_points :: proc(current_player: Player_Color, piece_type: Piece_Type) {
	g.board.points[current_player] += PIECE_POINTS[piece_type]
}

ui_camera :: proc() -> rl.Camera2D {
	return {
		zoom = RENDER_TEXTURE_SCALE,
	}
}

draw_piece_on_board :: proc(piece_type: Piece_Type, piece_color: Piece_Color, tile_pos: Position) {
	render_pos := board_tile_pos_to_sprite_logical_render_pos(tile_pos.x, tile_pos.y)
	tile_render_pos_x := i32(math.round(render_pos.x))
	tile_render_pos_y := i32(math.round(render_pos.y))
	draw_piece(piece_type, piece_color, tile_render_pos_x, tile_render_pos_y)
}

draw_piece :: proc(piece_type: Piece_Type, piece_color: Piece_Color, x,y: i32) {
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
	rl.DrawText(text, x, y, 28, color)

	if g.debug {
		rl.DrawRectangle(i32(x), i32(y), 1, 1, rl.RED)
	}
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

is_enemy_piece :: proc(target_tile: Tile, current_player: Player_Color) -> bool {
	if target_tile.piece_color != current_player && target_tile.piece_type != .None {
		return true
	}
	return false
}

get_other_player_color :: proc(player_color: Maybe(Player_Color)) -> Player_Color {
	_player_color: Player_Color

	if pc, ok := player_color.?; ok {
		_player_color = pc
	} else {
		_player_color = g.current_player

	}
	if _player_color == .White {
		return .Black
	} else if _player_color == .Black {
		return .White
	} else {
		return .None
	}
}

draw_tile_border :: proc(tile_pos: Position, color: rl.Color) {
	sprite_origin := board_tile_pos_to_sprite_logical_render_pos(tile_pos.x, tile_pos.y)
	rl.DrawRectangleLinesEx({sprite_origin.x, sprite_origin.y, TILE_SIZE, TILE_SIZE}, 2, color)
}
