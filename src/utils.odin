package game

import rl "vendor:raylib"

// Wraps os.read_entire_file and os.write_entire_file, but they also work with emscripten.
@(require_results)
read_entire_file :: proc(name: string, allocator := context.allocator, loc := #caller_location) -> (data: []byte, success: bool) {
	return _read_entire_file(name, allocator, loc)
}

write_entire_file :: proc(name: string, data: []byte, truncate := true) -> (success: bool) {
	return _write_entire_file(name, data, truncate)
}

pr_span :: proc(msg: Maybe(string)) {
    pr("-----------------------", msg.? or_else "", "-----------------------")
}

vec2_from_vec2i :: proc(v: Vec2i) -> Vec2 {
    return Vec2{f32(v.x), f32(v.y)}
}

vec2i_from_vec2 :: proc(v: Vec2) -> Vec2i {
    return Vec2i{i32(v.x), i32(v.y)}
}

is_set_fully_flagged :: proc(set: bit_set[$E]) -> bool {
    return card(set) == len(E)
}

get_mouse_position :: proc() -> Vec2 {
	return rl.GetMousePosition()
}

is_mouse_over_rect :: proc(x,y,w,h: f32) -> bool {
	mouse_pos := get_mouse_position()
	return mouse_pos.x >= x && mouse_pos.x <= x + w &&
	       mouse_pos.y >= y && mouse_pos.y <= y + h
}
