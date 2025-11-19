const std = @import("std");

pub fn main() void {
    const info = @typeInfo(std.Build.ExecutableOptions);
    switch (info) {
        .@"struct" => |s| {
            inline for (s.fields) |field| {
                std.debug.print("{s}\n", .{field.name});
            }
        },
        else => {},
    }
}
