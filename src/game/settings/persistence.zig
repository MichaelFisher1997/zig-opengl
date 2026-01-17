const std = @import("std");
const data = @import("data.zig");
const Settings = data.Settings;

const CONFIG_DIR = ".config/zigcraft";
const CONFIG_FILE = "settings.json";

/// Load settings from ~/.config/zigcraft/settings.json
/// Returns default settings if file doesn't exist or is invalid
pub fn load(allocator: std.mem.Allocator) Settings {
    const home = std.posix.getenv("HOME") orelse return .{};

    // Open home directory
    var home_dir = std.fs.openDirAbsolute(home, .{}) catch return .{};
    defer home_dir.close();

    // Try to open the config file relative to home
    const config_path = CONFIG_DIR ++ "/" ++ CONFIG_FILE;
    const content = home_dir.readFileAlloc(config_path, allocator, @enumFromInt(16 * 1024)) catch return .{};
    defer allocator.free(content);

    const parsed = std.json.parseFromSlice(Settings, allocator, content, .{
        .ignore_unknown_fields = true,
    }) catch return .{};
    defer parsed.deinit();

    var settings = parsed.value;
    // Deep copy the texture pack string so it survives deinit
    if (std.mem.eql(u8, settings.texture_pack, "default")) {
        settings.texture_pack = "default";
    } else {
        settings.texture_pack = allocator.dupe(u8, settings.texture_pack) catch "default";
    }

    if (std.mem.eql(u8, settings.environment_map, "default")) {
        settings.environment_map = "default";
    } else {
        settings.environment_map = allocator.dupe(u8, settings.environment_map) catch "default";
    }

    std.log.info("Settings loaded from ~/{s}", .{config_path});
    return settings;
}

pub fn deinit(settings: *Settings, allocator: std.mem.Allocator) void {
    if (!std.mem.eql(u8, settings.texture_pack, "default")) {
        allocator.free(settings.texture_pack);
    }
    if (!std.mem.eql(u8, settings.environment_map, "default")) {
        allocator.free(settings.environment_map);
    }
}

pub fn setTexturePack(settings: *Settings, allocator: std.mem.Allocator, name: []const u8) !void {
    if (std.mem.eql(u8, settings.texture_pack, name)) return;
    if (!std.mem.eql(u8, settings.texture_pack, "default")) allocator.free(settings.texture_pack);
    if (std.mem.eql(u8, name, "default")) {
        settings.texture_pack = "default";
    } else {
        settings.texture_pack = try allocator.dupe(u8, name);
    }
}

pub fn setEnvironmentMap(settings: *Settings, allocator: std.mem.Allocator, name: []const u8) !void {
    if (std.mem.eql(u8, settings.environment_map, name)) return;
    if (!std.mem.eql(u8, settings.environment_map, "default")) allocator.free(settings.environment_map);
    if (std.mem.eql(u8, name, "default")) {
        settings.environment_map = "default";
    } else {
        settings.environment_map = try allocator.dupe(u8, name);
    }
}

/// Save settings to ~/.config/zigcraft/settings.json
pub fn save(settings: *const Settings, allocator: std.mem.Allocator) void {
    const home = std.posix.getenv("HOME") orelse {
        std.log.warn("Cannot save settings: HOME not set", .{});
        return;
    };

    // Open home directory
    var home_dir = std.fs.openDirAbsolute(home, .{}) catch |err| {
        std.log.warn("Cannot open home directory: {}", .{err});
        return;
    };
    defer home_dir.close();

    // Create config directory if it doesn't exist
    home_dir.makePath(CONFIG_DIR) catch |err| {
        std.log.warn("Failed to create config directory: {}", .{err});
        return;
    };

    // Open/create the settings file
    const config_path = CONFIG_DIR ++ "/" ++ CONFIG_FILE;
    const file = home_dir.createFile(config_path, .{}) catch |err| {
        std.log.warn("Failed to create settings file: {}", .{err});
        return;
    };
    defer file.close();

    // Serialize settings to JSON and write to file
    const json_str = std.json.Stringify.valueAlloc(allocator, settings.*, .{ .whitespace = .indent_2 }) catch |err| {
        std.log.warn("Failed to serialize settings: {}", .{err});
        return;
    };
    defer allocator.free(json_str);

    // Write to file
    _ = file.writeAll(json_str) catch |err| {
        std.log.warn("Failed to write settings: {}", .{err});
        return;
    };

    std.log.info("Settings saved to ~/{s}", .{config_path});
}
