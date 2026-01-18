const std = @import("std");
const Settings = @import("data.zig").Settings;
const presets = @import("presets.zig");
const persistence = @import("persistence.zig");

test "Persistence Roundtrip" {
    const allocator = std.testing.allocator;
    var settings = Settings{};
    settings.shadow_quality = 3;
    settings.render_distance = 25;

    // Test save/load logic (mocking is hard here without extensive refactoring,
    // so we test the struct integrity and logic)

    // Test JSON serialization
    const json_str = try std.json.stringifyAlloc(allocator, settings, .{ .whitespace = .indent_2 });
    defer allocator.free(json_str);

    const parsed = try std.json.parseFromSlice(Settings, allocator, json_str, .{});
    defer parsed.deinit();

    try std.testing.expectEqual(settings.shadow_quality, parsed.value.shadow_quality);
    try std.testing.expectEqual(settings.render_distance, parsed.value.render_distance);
}

test "Preset Application" {
    var settings = Settings{};
    // Apply Low
    presets.apply(&settings, 0);
    try std.testing.expectEqual(@as(u32, 0), settings.shadow_quality);
    try std.testing.expectEqual(@as(i32, 6), settings.render_distance);

    // Apply Ultra
    presets.apply(&settings, 3);
    try std.testing.expectEqual(@as(u32, 3), settings.shadow_quality);
    try std.testing.expectEqual(@as(i32, 28), settings.render_distance);
}

test "Preset Matching" {
    var settings = Settings{};
    presets.apply(&settings, 1); // Medium
    try std.testing.expectEqual(@as(usize, 1), presets.getIndex(&settings));

    // Modify a value to make it Custom
    settings.shadow_quality = 3;
    try std.testing.expectEqual(presets.GRAPHICS_PRESETS.len, presets.getIndex(&settings));
}
