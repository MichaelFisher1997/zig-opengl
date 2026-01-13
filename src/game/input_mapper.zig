//! Input mapper - abstracts raw input into game actions with configurable bindings.
//!
//! This module provides a hardware-agnostic input abstraction layer that:
//! - Maps physical inputs (keys, mouse buttons) to logical game actions
//! - Supports runtime key rebinding
//! - Enables settings persistence for user-customized controls

const std = @import("std");
const interfaces = @import("../engine/core/interfaces.zig");
const Key = interfaces.Key;
const MouseButton = interfaces.MouseButton;
const Input = @import("../engine/input/input.zig").Input;

/// All logical game actions that can be triggered by input.
/// Gameplay code should query these actions instead of specific keys.
pub const GameAction = enum(u8) {
    // Movement (held/continuous)
    move_forward,
    move_backward,
    move_left,
    move_right,
    jump,
    crouch,
    sprint,
    fly,

    // Interaction (triggers)
    interact_primary, // Left click - break block
    interact_secondary, // Right click - place block

    // UI/Menu toggles
    inventory,
    tab_menu,
    pause,

    // Hotbar slots
    slot_1,
    slot_2,
    slot_3,
    slot_4,
    slot_5,
    slot_6,
    slot_7,
    slot_8,
    slot_9,

    // Debug/toggles
    toggle_wireframe,
    toggle_textures,
    toggle_vsync,
    toggle_fps,
    toggle_block_info,
    toggle_shadows,
    cycle_cascade,
    toggle_time_scale,
    toggle_creative,

    // Map controls
    toggle_map,
    map_zoom_in,
    map_zoom_out,
    map_center,

    // UI navigation
    ui_confirm,
    ui_back,

    pub const count = @typeInfo(GameAction).@"enum".fields.len;
};

/// Represents a physical input that can be bound to an action.
/// Supports keyboard keys, mouse buttons, and future gamepad support.
pub const InputBinding = union(enum) {
    key: Key,
    mouse_button: MouseButton,
    /// Alternative key binding (e.g., numpad + for zoom)
    key_alt: Key,
    none: void,

    pub fn eql(self: InputBinding, other: InputBinding) bool {
        return switch (self) {
            .key => |k| switch (other) {
                .key => |ok| k == ok,
                else => false,
            },
            .mouse_button => |mb| switch (other) {
                .mouse_button => |omb| mb == omb,
                else => false,
            },
            .key_alt => |k| switch (other) {
                .key_alt => |ok| k == ok,
                else => false,
            },
            .none => switch (other) {
                .none => true,
                else => false,
            },
        };
    }

    /// Get a human-readable name for this binding (for UI display)
    pub fn getName(self: InputBinding) []const u8 {
        return switch (self) {
            .key, .key_alt => |k| keyToString(k),
            .mouse_button => |mb| switch (mb) {
                .left => "Left Click",
                .middle => "Middle Click",
                .right => "Right Click",
                _ => "Mouse Button",
            },
            .none => "Unbound",
        };
    }

    fn keyToString(key: Key) []const u8 {
        return switch (key) {
            .a => "A",
            .b => "B",
            .c => "C",
            .d => "D",
            .e => "E",
            .f => "F",
            .g => "G",
            .h => "H",
            .i => "I",
            .j => "J",
            .k => "K",
            .l => "L",
            .m => "M",
            .n => "N",
            .o => "O",
            .p => "P",
            .q => "Q",
            .r => "R",
            .s => "S",
            .t => "T",
            .u => "U",
            .v => "V",
            .w => "W",
            .x => "X",
            .y => "Y",
            .z => "Z",
            .@"0" => "0",
            .@"1" => "1",
            .@"2" => "2",
            .@"3" => "3",
            .@"4" => "4",
            .@"5" => "5",
            .@"6" => "6",
            .@"7" => "7",
            .@"8" => "8",
            .@"9" => "9",
            .space => "Space",
            .escape => "Escape",
            .enter => "Enter",
            .tab => "Tab",
            .backspace => "Backspace",
            .plus => "+",
            .minus => "-",
            .kp_plus => "Numpad +",
            .kp_minus => "Numpad -",
            .up => "Up",
            .down => "Down",
            .left_arrow => "Left",
            .right_arrow => "Right",
            .left_shift => "Left Shift",
            .right_shift => "Right Shift",
            .left_ctrl => "Left Ctrl",
            .right_ctrl => "Right Ctrl",
            .f1 => "F1",
            .f2 => "F2",
            .f3 => "F3",
            .f4 => "F4",
            .f5 => "F5",
            .f6 => "F6",
            .f7 => "F7",
            .f8 => "F8",
            .f9 => "F9",
            .f10 => "F10",
            .f11 => "F11",
            .f12 => "F12",
            else => "Unknown",
        };
    }
};

/// Binding entry with primary and optional alternate binding
pub const ActionBinding = struct {
    primary: InputBinding,
    alternate: InputBinding,

    pub fn init(primary: InputBinding) ActionBinding {
        return .{ .primary = primary, .alternate = .{ .none = {} } };
    }

    pub fn initWithAlt(primary: InputBinding, alternate: InputBinding) ActionBinding {
        return .{ .primary = primary, .alternate = alternate };
    }
};

/// Input mapper that translates physical inputs to logical game actions.
/// Supports configurable key bindings that can be saved/loaded.
pub const InputMapper = struct {
    /// Current bindings for all actions
    bindings: [GameAction.count]ActionBinding,

    /// Initialize with default bindings
    pub fn init() InputMapper {
        var mapper: InputMapper = undefined;
        mapper.resetToDefaults();
        return mapper;
    }

    /// Reset all bindings to their default values
    pub fn resetToDefaults(self: *InputMapper) void {
        // Movement
        self.bindings[@intFromEnum(GameAction.move_forward)] = ActionBinding.init(.{ .key = .w });
        self.bindings[@intFromEnum(GameAction.move_backward)] = ActionBinding.init(.{ .key = .s });
        self.bindings[@intFromEnum(GameAction.move_left)] = ActionBinding.init(.{ .key = .a });
        self.bindings[@intFromEnum(GameAction.move_right)] = ActionBinding.init(.{ .key = .d });
        self.bindings[@intFromEnum(GameAction.jump)] = ActionBinding.init(.{ .key = .space });
        self.bindings[@intFromEnum(GameAction.crouch)] = ActionBinding.init(.{ .key = .left_shift });
        self.bindings[@intFromEnum(GameAction.sprint)] = ActionBinding.init(.{ .key = .left_ctrl });
        self.bindings[@intFromEnum(GameAction.fly)] = ActionBinding.init(.{ .none = {} }); // No default binding

        // Interaction
        self.bindings[@intFromEnum(GameAction.interact_primary)] = ActionBinding.init(.{ .mouse_button = .left });
        self.bindings[@intFromEnum(GameAction.interact_secondary)] = ActionBinding.init(.{ .mouse_button = .right });

        // UI/Menu
        self.bindings[@intFromEnum(GameAction.inventory)] = ActionBinding.init(.{ .key = .i });
        self.bindings[@intFromEnum(GameAction.tab_menu)] = ActionBinding.init(.{ .key = .tab });
        self.bindings[@intFromEnum(GameAction.pause)] = ActionBinding.init(.{ .key = .escape });

        // Hotbar slots
        self.bindings[@intFromEnum(GameAction.slot_1)] = ActionBinding.init(.{ .key = .@"1" });
        self.bindings[@intFromEnum(GameAction.slot_2)] = ActionBinding.init(.{ .key = .@"2" });
        self.bindings[@intFromEnum(GameAction.slot_3)] = ActionBinding.init(.{ .key = .@"3" });
        self.bindings[@intFromEnum(GameAction.slot_4)] = ActionBinding.init(.{ .key = .@"4" });
        self.bindings[@intFromEnum(GameAction.slot_5)] = ActionBinding.init(.{ .key = .@"5" });
        self.bindings[@intFromEnum(GameAction.slot_6)] = ActionBinding.init(.{ .key = .@"6" });
        self.bindings[@intFromEnum(GameAction.slot_7)] = ActionBinding.init(.{ .key = .@"7" });
        self.bindings[@intFromEnum(GameAction.slot_8)] = ActionBinding.init(.{ .key = .@"8" });
        self.bindings[@intFromEnum(GameAction.slot_9)] = ActionBinding.init(.{ .key = .@"9" });

        // Debug toggles
        self.bindings[@intFromEnum(GameAction.toggle_wireframe)] = ActionBinding.init(.{ .key = .f });
        self.bindings[@intFromEnum(GameAction.toggle_textures)] = ActionBinding.init(.{ .key = .t });
        self.bindings[@intFromEnum(GameAction.toggle_vsync)] = ActionBinding.init(.{ .key = .v });
        self.bindings[@intFromEnum(GameAction.toggle_fps)] = ActionBinding.init(.{ .key = .f2 });
        self.bindings[@intFromEnum(GameAction.toggle_block_info)] = ActionBinding.init(.{ .key = .f5 });
        self.bindings[@intFromEnum(GameAction.toggle_shadows)] = ActionBinding.init(.{ .key = .u });
        self.bindings[@intFromEnum(GameAction.cycle_cascade)] = ActionBinding.init(.{ .key = .k });
        self.bindings[@intFromEnum(GameAction.toggle_time_scale)] = ActionBinding.init(.{ .key = .n });
        self.bindings[@intFromEnum(GameAction.toggle_creative)] = ActionBinding.init(.{ .key = .f3 });

        // Map controls (with alternate bindings for numpad)
        self.bindings[@intFromEnum(GameAction.toggle_map)] = ActionBinding.init(.{ .key = .m });
        self.bindings[@intFromEnum(GameAction.map_zoom_in)] = ActionBinding.initWithAlt(.{ .key = .plus }, .{ .key_alt = .kp_plus });
        self.bindings[@intFromEnum(GameAction.map_zoom_out)] = ActionBinding.initWithAlt(.{ .key = .minus }, .{ .key_alt = .kp_minus });
        self.bindings[@intFromEnum(GameAction.map_center)] = ActionBinding.init(.{ .key = .space });

        // UI navigation
        self.bindings[@intFromEnum(GameAction.ui_confirm)] = ActionBinding.init(.{ .key = .enter });
        self.bindings[@intFromEnum(GameAction.ui_back)] = ActionBinding.init(.{ .key = .escape });
    }

    /// Set a new binding for an action
    pub fn setBinding(self: *InputMapper, action: GameAction, binding: InputBinding) void {
        self.bindings[@intFromEnum(action)].primary = binding;
    }

    /// Set an alternate binding for an action
    pub fn setAlternateBinding(self: *InputMapper, action: GameAction, binding: InputBinding) void {
        self.bindings[@intFromEnum(action)].alternate = binding;
    }

    /// Get the current binding for an action
    pub fn getBinding(self: *const InputMapper, action: GameAction) ActionBinding {
        return self.bindings[@intFromEnum(action)];
    }

    /// Check if a binding matches the current input state (for held actions)
    fn isBindingActive(self: *const InputMapper, input: *const Input, action: GameAction) bool {
        const binding = self.bindings[@intFromEnum(action)];

        // Check primary binding
        const primary_active = switch (binding.primary) {
            .key, .key_alt => |k| input.isKeyDown(k),
            .mouse_button => |mb| input.isMouseButtonDown(mb),
            .none => false,
        };
        if (primary_active) return true;

        // Check alternate binding
        return switch (binding.alternate) {
            .key, .key_alt => |k| input.isKeyDown(k),
            .mouse_button => |mb| input.isMouseButtonDown(mb),
            .none => false,
        };
    }

    /// Check if a binding was pressed this frame (for trigger actions)
    fn isBindingPressed(self: *const InputMapper, input: *const Input, action: GameAction) bool {
        const binding = self.bindings[@intFromEnum(action)];

        // Check primary binding
        const primary_pressed = switch (binding.primary) {
            .key, .key_alt => |k| input.isKeyPressed(k),
            .mouse_button => |mb| input.isMouseButtonPressed(mb),
            .none => false,
        };
        if (primary_pressed) return true;

        // Check alternate binding
        return switch (binding.alternate) {
            .key, .key_alt => |k| input.isKeyPressed(k),
            .mouse_button => |mb| input.isMouseButtonPressed(mb),
            .none => false,
        };
    }

    /// Check if a binding was released this frame
    fn isBindingReleased(self: *const InputMapper, input: *const Input, action: GameAction) bool {
        const binding = self.bindings[@intFromEnum(action)];

        // Check primary binding
        const primary_released = switch (binding.primary) {
            .key, .key_alt => |k| input.isKeyReleased(k),
            .mouse_button => false, // Mouse button release not currently tracked per-frame
            .none => false,
        };
        if (primary_released) return true;

        // Check alternate binding
        return switch (binding.alternate) {
            .key, .key_alt => |k| input.isKeyReleased(k),
            .mouse_button => false,
            .none => false,
        };
    }

    // ========================================================================
    // Public Query API - These match the original interface for compatibility
    // ========================================================================

    /// Check if a continuous/held action is currently active (e.g., movement)
    pub fn isActionActive(self: *const InputMapper, input: *const Input, action: GameAction) bool {
        return self.isBindingActive(input, action);
    }

    /// Check if a trigger action was pressed this frame (e.g., jump, toggle)
    pub fn isActionPressed(self: *const InputMapper, input: *const Input, action: GameAction) bool {
        return self.isBindingPressed(input, action);
    }

    /// Check if an action was released this frame
    pub fn isActionReleased(self: *const InputMapper, input: *const Input, action: GameAction) bool {
        return self.isBindingReleased(input, action);
    }

    /// Get movement vector based on current bindings
    pub fn getMovementVector(self: *const InputMapper, input: *const Input) struct { x: f32, z: f32 } {
        var x: f32 = 0;
        var z: f32 = 0;
        if (self.isActionActive(input, .move_forward)) z += 1;
        if (self.isActionActive(input, .move_backward)) z -= 1;
        if (self.isActionActive(input, .move_left)) x -= 1;
        if (self.isActionActive(input, .move_right)) x += 1;
        return .{ .x = x, .z = z };
    }

    // ========================================================================
    // Serialization for settings persistence
    // ========================================================================

    /// Serialize bindings to a JSON-compatible format
    pub fn serialize(self: *const InputMapper, allocator: std.mem.Allocator) ![]u8 {
        var buffer = std.ArrayListUnmanaged(u8){};
        errdefer buffer.deinit(allocator);

        try buffer.appendSlice(allocator, "{\n");

        var first = true;
        inline for (@typeInfo(GameAction).@"enum".fields, 0..) |field, idx| {
            const action: GameAction = @enumFromInt(field.value);
            const binding = self.bindings[idx];

            if (!first) try buffer.appendSlice(allocator, ",\n");
            first = false;

            try buffer.appendSlice(allocator, "  \"");
            try buffer.appendSlice(allocator, field.name);
            try buffer.appendSlice(allocator, "\": { \"primary\": ");
            try serializeBinding(&buffer, allocator, binding.primary);
            try buffer.appendSlice(allocator, ", \"alternate\": ");
            try serializeBinding(&buffer, allocator, binding.alternate);
            try buffer.appendSlice(allocator, " }");
            _ = action;
        }

        try buffer.appendSlice(allocator, "\n}");
        return buffer.toOwnedSlice(allocator);
    }

    fn serializeBinding(buffer: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, binding: InputBinding) !void {
        switch (binding) {
            .key => |k| {
                try buffer.appendSlice(allocator, "{ \"type\": \"key\", \"value\": ");
                var val_buf: [32]u8 = undefined;
                const val_str = try std.fmt.bufPrint(&val_buf, "{d}", .{@intFromEnum(k)});
                try buffer.appendSlice(allocator, val_str);
                try buffer.appendSlice(allocator, " }");
            },
            .key_alt => |k| {
                try buffer.appendSlice(allocator, "{ \"type\": \"key_alt\", \"value\": ");
                var val_buf: [32]u8 = undefined;
                const val_str = try std.fmt.bufPrint(&val_buf, "{d}", .{@intFromEnum(k)});
                try buffer.appendSlice(allocator, val_str);
                try buffer.appendSlice(allocator, " }");
            },
            .mouse_button => |mb| {
                try buffer.appendSlice(allocator, "{ \"type\": \"mouse\", \"value\": ");
                var val_buf: [32]u8 = undefined;
                const val_str = try std.fmt.bufPrint(&val_buf, "{d}", .{@intFromEnum(mb)});
                try buffer.appendSlice(allocator, val_str);
                try buffer.appendSlice(allocator, " }");
            },
            .none => {
                try buffer.appendSlice(allocator, "null");
            },
        }
    }

    /// Deserialize bindings from JSON data
    pub fn deserialize(self: *InputMapper, data: []const u8) !void {
        // Simple JSON parser for our specific format
        var i: usize = 0;
        while (i < data.len) {
            // Find action name
            if (std.mem.indexOfPos(u8, data, i, "\"")) |quote_start| {
                if (std.mem.indexOfPos(u8, data, quote_start + 1, "\"")) |quote_end| {
                    const action_name = data[quote_start + 1 .. quote_end];

                    // Find the action enum
                    const maybe_action = stringToAction(action_name);
                    if (maybe_action) |action| {
                        // Parse primary binding
                        if (std.mem.indexOfPos(u8, data, quote_end, "\"primary\":")) |primary_start| {
                            const primary_binding = parseBindingAt(data, primary_start + 10);
                            self.bindings[@intFromEnum(action)].primary = primary_binding;
                        }

                        // Parse alternate binding
                        if (std.mem.indexOfPos(u8, data, quote_end, "\"alternate\":")) |alt_start| {
                            const alt_binding = parseBindingAt(data, alt_start + 12);
                            self.bindings[@intFromEnum(action)].alternate = alt_binding;
                        }
                    }
                    i = quote_end + 1;
                } else break;
            } else break;
        }
    }

    fn parseBindingAt(data: []const u8, start: usize) InputBinding {
        // Skip whitespace
        var i = start;
        while (i < data.len and (data[i] == ' ' or data[i] == '\n' or data[i] == '\t')) : (i += 1) {}

        if (i >= data.len) return .{ .none = {} };

        // Check for null
        if (i + 4 <= data.len and std.mem.eql(u8, data[i .. i + 4], "null")) {
            return .{ .none = {} };
        }

        // Parse object
        if (std.mem.indexOfPos(u8, data, i, "\"type\":")) |type_start| {
            // Find type value
            if (std.mem.indexOfPos(u8, data, type_start + 7, "\"")) |tq_start| {
                if (std.mem.indexOfPos(u8, data, tq_start + 1, "\"")) |tq_end| {
                    const type_str = data[tq_start + 1 .. tq_end];

                    // Find value
                    if (std.mem.indexOfPos(u8, data, tq_end, "\"value\":")) |val_start| {
                        var val_i = val_start + 8;
                        while (val_i < data.len and (data[val_i] == ' ' or data[val_i] == '\n')) : (val_i += 1) {}

                        // Parse number
                        var val_end = val_i;
                        while (val_end < data.len and data[val_end] >= '0' and data[val_end] <= '9') : (val_end += 1) {}

                        if (val_end > val_i) {
                            const value = std.fmt.parseInt(u32, data[val_i..val_end], 10) catch return .{ .none = {} };

                            if (std.mem.eql(u8, type_str, "key")) {
                                return .{ .key = @enumFromInt(value) };
                            } else if (std.mem.eql(u8, type_str, "key_alt")) {
                                return .{ .key_alt = @enumFromInt(value) };
                            } else if (std.mem.eql(u8, type_str, "mouse")) {
                                return .{ .mouse_button = @enumFromInt(@as(u8, @truncate(value))) };
                            }
                        }
                    }
                }
            }
        }

        return .{ .none = {} };
    }

    fn stringToAction(name: []const u8) ?GameAction {
        inline for (@typeInfo(GameAction).@"enum".fields) |field| {
            if (std.mem.eql(u8, name, field.name)) {
                return @enumFromInt(field.value);
            }
        }
        return null;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "InputMapper default bindings" {
    const mapper = InputMapper.init();

    // Check some default bindings
    const forward_binding = mapper.getBinding(.move_forward);
    try std.testing.expect(forward_binding.primary.key == .w);

    const jump_binding = mapper.getBinding(.jump);
    try std.testing.expect(jump_binding.primary.key == .space);

    const primary_binding = mapper.getBinding(.interact_primary);
    try std.testing.expect(primary_binding.primary.mouse_button == .left);
}

test "InputMapper rebinding" {
    var mapper = InputMapper.init();

    // Rebind forward to up arrow
    mapper.setBinding(.move_forward, .{ .key = .up });

    const binding = mapper.getBinding(.move_forward);
    try std.testing.expect(binding.primary.key == .up);
}

test "InputMapper serialization roundtrip" {
    const allocator = std.testing.allocator;

    var original = InputMapper.init();
    original.setBinding(.move_forward, .{ .key = .up });
    original.setBinding(.jump, .{ .key = .w });

    const json = try original.serialize(allocator);
    defer allocator.free(json);

    var restored = InputMapper.init();
    try restored.deserialize(json);

    // Check that custom bindings were restored
    try std.testing.expect(restored.getBinding(.move_forward).primary.key == .up);
    try std.testing.expect(restored.getBinding(.jump).primary.key == .w);
}
