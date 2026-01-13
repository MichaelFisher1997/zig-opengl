//! Input mapper - abstracts raw input into game actions.

const std = @import("std");
const interfaces = @import("../engine/core/interfaces.zig");
const Key = interfaces.Key;
const MouseButton = interfaces.MouseButton;
const Input = @import("../engine/input/input.zig").Input;

pub const GameAction = enum {
    move_forward,
    move_backward,
    move_left,
    move_right,
    jump,
    crouch,
    sprint,
    fly,

    interact_primary, // Left click
    interact_secondary, // Right click

    inventory,
    tab_menu,
    pause,

    slot_1,
    slot_2,
    slot_3,
    slot_4,
    slot_5,
    slot_6,
    slot_7,
    slot_8,
    slot_9,

    toggle_wireframe,
    toggle_textures,
    toggle_vsync,
    toggle_fps,
    toggle_block_info,
    toggle_shadows,
    cycle_cascade,
    toggle_time_scale,
    toggle_creative,
};

pub const InputMapper = struct {
    pub fn isActionActive(input: *const Input, action: GameAction) bool {
        return switch (action) {
            .move_forward => input.isKeyDown(.w),
            .move_backward => input.isKeyDown(.s),
            .move_left => input.isKeyDown(.a),
            .move_right => input.isKeyDown(.d),
            .jump => input.isKeyDown(.space),
            .crouch => input.isKeyDown(.left_shift),
            .sprint => input.isKeyDown(.left_ctrl),
            else => false,
        };
    }

    pub fn isActionPressed(input: *const Input, action: GameAction) bool {
        return switch (action) {
            .inventory => input.isKeyPressed(.i),
            .tab_menu => input.isKeyPressed(.tab),
            .pause => input.isKeyPressed(.escape),

            .slot_1 => input.isKeyPressed(.@"1"),
            .slot_2 => input.isKeyPressed(.@"2"),
            .slot_3 => input.isKeyPressed(.@"3"),
            .slot_4 => input.isKeyPressed(.@"4"),
            .slot_5 => input.isKeyPressed(.@"5"),
            .slot_6 => input.isKeyPressed(.@"6"),
            .slot_7 => input.isKeyPressed(.@"7"),
            .slot_8 => input.isKeyPressed(.@"8"),
            .slot_9 => input.isKeyPressed(.@"9"),

            .toggle_wireframe => input.isKeyPressed(.f),
            .toggle_textures => input.isKeyPressed(.t),
            .toggle_vsync => input.isKeyPressed(.v),
            .toggle_fps => input.isKeyPressed(.f2),
            .toggle_block_info => input.isKeyPressed(.f5),
            .toggle_shadows => input.isKeyPressed(.u),
            .cycle_cascade => input.isKeyPressed(.k),
            .toggle_time_scale => input.isKeyPressed(.n),
            .toggle_creative => input.isKeyPressed(.f3),

            .interact_primary => input.isMouseButtonPressed(.left),
            .interact_secondary => input.isMouseButtonPressed(.right),

            .jump => input.isKeyPressed(.space),

            else => false,
        };
    }

    pub fn isActionReleased(input: *const Input, action: GameAction) bool {
        return switch (action) {
            .jump => input.isKeyReleased(.space),
            else => false,
        };
    }

    pub fn getMovementVector(input: *const Input) struct { x: f32, z: f32 } {
        var x: f32 = 0;
        var z: f32 = 0;
        if (input.isKeyDown(.w)) z += 1;
        if (input.isKeyDown(.s)) z -= 1;
        if (input.isKeyDown(.a)) x -= 1;
        if (input.isKeyDown(.d)) x += 1;
        return .{ .x = x, .z = z };
    }
};
