const std = @import("std");
const testing = std.testing;
const c = @import("c.zig").c;

pub fn main() !void {
    std.debug.print("Running integration tests...\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Find the robust-demo executable
    // Typically in zig-out/bin/robust-demo or similar
    const robust_demo_path = try findExecutable(allocator, "robust-demo");
    defer allocator.free(robust_demo_path);

    std.debug.print("Found robust-demo at: {s}\n", .{robust_demo_path});

    // Run the demo
    var child = std.process.Child.init(&[_][]const u8{robust_demo_path}, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    const result = try child.wait();

    // Check exit code
    switch (result) {
        .Exited => |code| {
            if (code != 0) {
                std.debug.print("robust-demo failed with exit code {d}\n", .{code});
                return error.DemoFailed;
            }
        },
        else => {
            std.debug.print("robust-demo crashed or was signaled\n", .{});
            return error.DemoCrashed;
        },
    }

    std.debug.print("robust-demo exited successfully.\n", .{});
}

fn findExecutable(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    // Try current directory, zig-out/bin, etc.
    const paths = [_][]const u8{
        "./zig-out/bin",
        "./zig-cache/bin",
        ".",
    };

    for (paths) |path| {
        const full_path = try std.fs.path.join(allocator, &[_][]const u8{ path, name });
        const file = std.fs.cwd().openFile(full_path, .{}) catch {
            allocator.free(full_path);
            continue;
        };
        file.close();
        return full_path;
    }
    return error.FileNotFound;
}
