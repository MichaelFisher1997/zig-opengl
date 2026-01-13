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
    // Movement
    /// Move player forward
    move_forward,
    /// Move player backward
    move_backward,
    /// Strafe player left
    move_left,
    /// Strafe player right
    move_right,
    /// Jump or fly up
    jump,
    /// Crouch or fly down
    crouch,
    /// Sprint (increase speed)
    sprint,
    /// Toggle fly mode (detected via double-tap jump usually)
    fly,

    // Interaction
    /// Primary action (e.g., mine block)
    interact_primary,
    /// Secondary action (e.g., place block)
    interact_secondary,

    // UI/Menu toggles
    /// Open/close inventory
    inventory,
    /// Toggle mouse capture or menu
    tab_menu,
    /// Pause the game
    pause,

    // Hotbar slots
    /// Select hotbar slot 1
    slot_1,
    /// Select hotbar slot 2
    slot_2,
    /// Select hotbar slot 3
    slot_3,
    /// Select hotbar slot 4
    slot_4,
    /// Select hotbar slot 5
    slot_5,
    /// Select hotbar slot 6
    slot_6,
    /// Select hotbar slot 7
    slot_7,
    /// Select hotbar slot 8
    slot_8,
    /// Select hotbar slot 9
    slot_9,

    // Debug/toggles
    /// Toggle wireframe rendering
    toggle_wireframe,
    /// Toggle textures
    toggle_textures,
    /// Toggle VSync
    toggle_vsync,
    /// Toggle FPS counter
    toggle_fps,
    /// Toggle block information overlay
    toggle_block_info,
    /// Toggle shadow debug view
    toggle_shadows,
    /// Cycle through shadow cascades
    cycle_cascade,
    /// Pause/resume time
    toggle_time_scale,
    /// Toggle creative mode
    toggle_creative,

    // Map controls
    /// Open/close world map
    toggle_map,
    /// Zoom in on map
    map_zoom_in,
    /// Zoom out on map
    map_zoom_out,
    /// Center map on player
    map_center,

    // UI navigation
    /// Confirm menu selection
    ui_confirm,
    /// Go back in menu or close
    ui_back,

    pub const count = @typeInfo(GameAction).@"enum".fields.len;
};

/// Represents a physical input that can be bound to an action.
pub const InputBinding = union(enum) {
    key: Key,
    mouse_button: MouseButton,
    /// Alternative key binding (e.g., numpad + for zoom)
    key_alt: Key,
    none: void,

    /// Returns true if both bindings represent the same physical input
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
        self.bindings[@intFromEnum(GameAction.fly)] = ActionBinding.init(.{ .none = {} });

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

        // Map controls
        self.bindings[@intFromEnum(GameAction.toggle_map)] = ActionBinding.init(.{ .key = .m });
        self.bindings[@intFromEnum(GameAction.map_zoom_in)] = ActionBinding.initWithAlt(.{ .key = .plus }, .{ .key_alt = .kp_plus });
        self.bindings[@intFromEnum(GameAction.map_zoom_out)] = ActionBinding.initWithAlt(.{ .key = .minus }, .{ .key_alt = .kp_minus });
        self.bindings[@intFromEnum(GameAction.map_center)] = ActionBinding.init(.{ .key = .space });

        // UI navigation
        self.bindings[@intFromEnum(GameAction.ui_confirm)] = ActionBinding.init(.{ .key = .enter });
        self.bindings[@intFromEnum(GameAction.ui_back)] = ActionBinding.init(.{ .key = .escape });
    }

    /// Reset an individual action to its default value
    pub fn resetAction(self: *InputMapper, action: GameAction) void {
        const defaults = init();
        self.bindings[@intFromEnum(action)] = defaults.bindings[@intFromEnum(action)];
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

    /// Check if a continuous/held action is currently active (e.g., movement)
    pub fn isActionActive(self: *const InputMapper, input: *const Input, action: GameAction) bool {
        const binding = self.bindings[@intFromEnum(action)];
        return self.isBindingStateActive(input, binding.primary) or self.isBindingStateActive(input, binding.alternate);
    }

    /// Check if a trigger action was pressed this frame (e.g., jump, toggle)
    pub fn isActionPressed(self: *const InputMapper, input: *const Input, action: GameAction) bool {
        const binding = self.bindings[@intFromEnum(action)];
        return self.isBindingStatePressed(input, binding.primary) or self.isBindingStatePressed(input, binding.alternate);
    }

    /// Check if an action was released this frame
    pub fn isActionReleased(self: *const InputMapper, input: *const Input, action: GameAction) bool {
        const binding = self.bindings[@intFromEnum(action)];
        return self.isBindingStateReleased(input, binding.primary) or self.isBindingStateReleased(input, binding.alternate);
    }

    fn isBindingStateActive(self: *const InputMapper, input: *const Input, binding: InputBinding) bool {
        _ = self;
        return switch (binding) {
            .key, .key_alt => |k| input.isKeyDown(k),
            .mouse_button => |mb| input.isMouseButtonDown(mb),
            .none => false,
        };
    }

    fn isBindingStatePressed(self: *const InputMapper, input: *const Input, binding: InputBinding) bool {
        _ = self;
        return switch (binding) {
            .key, .key_alt => |k| input.isKeyPressed(k),
            .mouse_button => |mb| input.isMouseButtonPressed(mb),
            .none => false,
        };
    }

    fn isBindingStateReleased(self: *const InputMapper, input: *const Input, binding: InputBinding) bool {
        _ = self;
        return switch (binding) {
            .key, .key_alt => |k| input.isKeyReleased(k),
            .mouse_button => false, // Mouse button release not currently tracked per-frame in Input
            .none => false,
        };
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
    // Serialization
    // ========================================================================

    /// Serialize bindings to a JSON string
    pub fn serialize(self: *const InputMapper, allocator: std.mem.Allocator) ![]u8 {
        var buffer = std.ArrayList(u8).empty;
        var aw = std.Io.Writer.Allocating.fromArrayList(allocator, &buffer);
        defer aw.deinit();

        try std.json.Stringify.value(self.bindings, .{}, &aw.writer);
        return aw.toOwnedSlice();
    }

    /// Deserialize bindings from JSON data
    pub fn deserialize(self: *InputMapper, allocator: std.mem.Allocator, data: []const u8) !void {
        var parsed = try std.json.parseFromSlice([GameAction.count]ActionBinding, allocator, data, .{
            .ignore_unknown_fields = true,
        });
        defer parsed.deinit();

        self.bindings = parsed.value;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "InputMapper serialization" {
    const allocator = std.testing.allocator;
    var mapper = InputMapper.init();
    mapper.setBinding(.jump, .{ .key = .up });

    const json = try mapper.serialize(allocator);
    defer allocator.free(json);

    var restored = InputMapper.init();
    try restored.deserialize(allocator, json);

    try std.testing.expect(restored.getBinding(.jump).primary.key == .up);
}
