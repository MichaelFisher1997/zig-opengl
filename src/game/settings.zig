//! Settings system for persisting user preferences.
//!
//! Handles loading and saving of game settings including:
//! - Key bindings
//! - Graphics options (future)
//! - Audio options (future)
//!
//! Settings are stored in a platform-appropriate location:
//! - Linux: ~/.local/share/zigcraft/settings.json
//! - Windows: %APPDATA%/zigcraft/settings.json (future)
//! - macOS: ~/Library/Application Support/zigcraft/settings.json (future)

const std = @import("std");
const builtin = @import("builtin");
const InputMapper = @import("input_mapper.zig").InputMapper;

pub const Settings = struct {
    allocator: std.mem.Allocator,
    input_mapper: InputMapper,

    // Future settings can be added here:
    // graphics: GraphicsSettings,
    // audio: AudioSettings,

    const SETTINGS_FILENAME = "settings.json";
    const APP_NAME = "zigcraft";

    pub fn init(allocator: std.mem.Allocator) Settings {
        return .{
            .allocator = allocator,
            .input_mapper = InputMapper.init(),
        };
    }

    /// Load settings from disk. If file doesn't exist or is invalid, uses defaults.
    pub fn load(allocator: std.mem.Allocator) Settings {
        var settings = Settings.init(allocator);

        const path = getSettingsPath(allocator) catch return settings;
        defer allocator.free(path);

        const data = std.fs.cwd().readFileAlloc(path, allocator, @enumFromInt(1024 * 1024)) catch return settings;
        defer allocator.free(data);

        // Parse and apply settings
        settings.parseJson(data) catch return settings;

        return settings;
    }

    /// Save current settings to disk.
    pub fn save(self: *const Settings) !void {
        const path = try getSettingsPath(self.allocator);
        defer self.allocator.free(path);

        // Ensure directory exists
        const dir_path = std.fs.path.dirname(path) orelse return error.InvalidPath;
        std.fs.makeDirAbsolute(dir_path) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        // Serialize settings
        const json = try self.toJson();
        defer self.allocator.free(json);

        // Write to file
        const file = try std.fs.createFileAbsolute(path, .{});
        defer file.close();

        try file.writeAll(json);
    }

    /// Reset all settings to defaults
    pub fn resetToDefaults(self: *Settings) void {
        self.input_mapper.resetToDefaults();
    }

    /// Get the platform-specific settings file path
    fn getSettingsPath(allocator: std.mem.Allocator) ![]u8 {
        if (builtin.os.tag == .linux) {
            // Use XDG_DATA_HOME or fallback to ~/.local/share
            const home = std.posix.getenv("HOME") orelse return error.NoHomeDir;
            const xdg_data = std.posix.getenv("XDG_DATA_HOME");

            if (xdg_data) |data_dir| {
                return std.fmt.allocPrint(allocator, "{s}/{s}/{s}", .{ data_dir, APP_NAME, SETTINGS_FILENAME });
            } else {
                return std.fmt.allocPrint(allocator, "{s}/.local/share/{s}/{s}", .{ home, APP_NAME, SETTINGS_FILENAME });
            }
        } else if (builtin.os.tag == .macos) {
            const home = std.posix.getenv("HOME") orelse return error.NoHomeDir;
            return std.fmt.allocPrint(allocator, "{s}/Library/Application Support/{s}/{s}", .{ home, APP_NAME, SETTINGS_FILENAME });
        } else if (builtin.os.tag == .windows) {
            const appdata = std.posix.getenv("APPDATA") orelse return error.NoAppDataDir;
            return std.fmt.allocPrint(allocator, "{s}\\{s}\\{s}", .{ appdata, APP_NAME, SETTINGS_FILENAME });
        } else {
            return error.UnsupportedPlatform;
        }
    }

    /// Serialize all settings to JSON
    fn toJson(self: *const Settings) ![]u8 {
        var buffer = std.ArrayListUnmanaged(u8){};
        errdefer buffer.deinit(self.allocator);

        try buffer.appendSlice(self.allocator, "{\n");
        try buffer.appendSlice(self.allocator, "  \"version\": 1,\n");
        try buffer.appendSlice(self.allocator, "  \"bindings\": ");

        // Serialize keybindings
        const bindings_json = try self.input_mapper.serialize(self.allocator);
        defer self.allocator.free(bindings_json);

        // Indent the bindings JSON
        var lines = std.mem.splitScalar(u8, bindings_json, '\n');
        var first_line = true;
        while (lines.next()) |line| {
            if (!first_line) {
                try buffer.appendSlice(self.allocator, "\n  ");
            }
            try buffer.appendSlice(self.allocator, line);
            first_line = false;
        }

        try buffer.appendSlice(self.allocator, "\n}");

        return buffer.toOwnedSlice(self.allocator);
    }

    /// Parse JSON settings data
    fn parseJson(self: *Settings, data: []const u8) !void {
        // Find bindings section
        if (std.mem.indexOf(u8, data, "\"bindings\":")) |bindings_start| {
            // Find the opening brace of bindings object
            if (std.mem.indexOfPos(u8, data, bindings_start, "{")) |obj_start| {
                // Find matching closing brace (simple approach - count braces)
                var depth: usize = 0;
                var obj_end: usize = obj_start;
                for (data[obj_start..], obj_start..) |c, idx| {
                    if (c == '{') depth += 1;
                    if (c == '}') {
                        depth -= 1;
                        if (depth == 0) {
                            obj_end = idx + 1;
                            break;
                        }
                    }
                }

                if (obj_end > obj_start) {
                    try self.input_mapper.deserialize(data[obj_start..obj_end]);
                }
            }
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Settings init creates default bindings" {
    const settings = Settings.init(std.testing.allocator);
    const binding = settings.input_mapper.getBinding(.move_forward);
    try std.testing.expect(binding.primary.key == .w);
}

test "Settings JSON roundtrip" {
    const allocator = std.testing.allocator;

    var settings = Settings.init(allocator);
    settings.input_mapper.setBinding(.move_forward, .{ .key = .up });

    const json = try settings.toJson();
    defer allocator.free(json);

    // Verify JSON contains expected content
    try std.testing.expect(std.mem.indexOf(u8, json, "\"version\": 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"bindings\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "move_forward") != null);
}
