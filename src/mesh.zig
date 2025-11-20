const std = @import("std");
const chunk_mod = @import("chunk.zig");
const Chunk = chunk_mod.Chunk;
const BlockType = @import("block.zig").BlockType;

pub const ChunkMesh = struct {
    vertices: []f32,
    allocator: std.mem.Allocator,

    pub fn deinit(self: ChunkMesh) void {
        self.allocator.free(self.vertices);
    }
};

pub fn generateMesh(allocator: std.mem.Allocator, chunk: *const Chunk) !ChunkMesh {
    var vertices = std.ArrayList(f32).empty;
    errdefer vertices.deinit(allocator);

    for (0..chunk_mod.CHUNK_SIZE_X) |x| {
        for (0..chunk_mod.CHUNK_SIZE_Y) |y| {
            for (0..chunk_mod.CHUNK_SIZE_Z) |z| {
                const block = chunk.getBlock(x, y, z);
                if (!block.isActive()) continue;

                const fx = @as(f32, @floatFromInt(x));
                const fy = @as(f32, @floatFromInt(y));
                const fz = @as(f32, @floatFromInt(z));

                const color = getColor(block.type);

                // Check neighbors (simple bounds check: treat outside as air)

                // Right (+X)
                if (x + 1 >= chunk_mod.CHUNK_SIZE_X or !chunk.getBlock(x + 1, y, z).isActive()) {
                    try addFace(allocator, &vertices, fx, fy, fz, color, .Right);
                }
                // Left (-X)
                if (x == 0 or !chunk.getBlock(x - 1, y, z).isActive()) {
                    try addFace(allocator, &vertices, fx, fy, fz, color, .Left);
                }

                // Top (+Y)
                if (y + 1 >= chunk_mod.CHUNK_SIZE_Y or !chunk.getBlock(x, y + 1, z).isActive()) {
                    try addFace(allocator, &vertices, fx, fy, fz, color, .Top);
                }
                // Bottom (-Y)
                if (y == 0 or !chunk.getBlock(x, y - 1, z).isActive()) {
                    try addFace(allocator, &vertices, fx, fy, fz, color, .Bottom);
                }

                // Front (+Z)
                if (z + 1 >= chunk_mod.CHUNK_SIZE_Z or !chunk.getBlock(x, y, z + 1).isActive()) {
                    try addFace(allocator, &vertices, fx, fy, fz, color, .Front);
                }
                // Back (-Z)
                if (z == 0 or !chunk.getBlock(x, y, z - 1).isActive()) {
                    try addFace(allocator, &vertices, fx, fy, fz, color, .Back);
                }
            }
        }
    }

    // Ensure we actually generated some vertices, otherwise the slice operations later might fail or GL draw calls with 0 count
    if (vertices.items.len == 0) {
        return ChunkMesh{
            .vertices = &[_]f32{},
            .allocator = allocator,
        };
    }

    return ChunkMesh{
        .vertices = try vertices.toOwnedSlice(allocator),
        .allocator = allocator,
    };
}

const FaceDir = enum { Right, Left, Top, Bottom, Front, Back };

fn getColor(btype: BlockType) [3]f32 {
    return switch (btype) {
        .Grass => .{ 0.1, 0.8, 0.1 },
        .Dirt => .{ 0.5, 0.3, 0.1 },
        .Stone => .{ 0.5, 0.5, 0.5 },
        .Air => .{ 1.0, 0.0, 1.0 }, // Should not happen
        _ => .{ 1.0, 0.0, 0.0 }, // Handle potential corruption
    };
}

fn addFace(allocator: std.mem.Allocator, list: *std.ArrayList(f32), x: f32, y: f32, z: f32, color: [3]f32, dir: FaceDir) !void {
    const r = color[0];
    const g = color[1];
    const b = color[2];

    // Vertices format: x, y, z, r, g, b
    switch (dir) {
        .Back => { // -Z
            try list.appendSlice(allocator, &.{ x + 0.0, y + 0.0, z + 0.0, r, g, b });
            try list.appendSlice(allocator, &.{ x + 1.0, y + 1.0, z + 0.0, r, g, b });
            try list.appendSlice(allocator, &.{ x + 1.0, y + 0.0, z + 0.0, r, g, b });
            try list.appendSlice(allocator, &.{ x + 1.0, y + 1.0, z + 0.0, r, g, b });
            try list.appendSlice(allocator, &.{ x + 0.0, y + 0.0, z + 0.0, r, g, b });
            try list.appendSlice(allocator, &.{ x + 0.0, y + 1.0, z + 0.0, r, g, b });
        },
        .Front => { // +Z
            try list.appendSlice(allocator, &.{ x + 0.0, y + 0.0, z + 1.0, r, g, b });
            try list.appendSlice(allocator, &.{ x + 1.0, y + 0.0, z + 1.0, r, g, b });
            try list.appendSlice(allocator, &.{ x + 1.0, y + 1.0, z + 1.0, r, g, b });
            try list.appendSlice(allocator, &.{ x + 1.0, y + 1.0, z + 1.0, r, g, b });
            try list.appendSlice(allocator, &.{ x + 0.0, y + 1.0, z + 1.0, r, g, b });
            try list.appendSlice(allocator, &.{ x + 0.0, y + 0.0, z + 1.0, r, g, b });
        },
        .Left => { // -X
            try list.appendSlice(allocator, &.{ x + 0.0, y + 1.0, z + 1.0, r, g, b });
            try list.appendSlice(allocator, &.{ x + 0.0, y + 1.0, z + 0.0, r, g, b });
            try list.appendSlice(allocator, &.{ x + 0.0, y + 0.0, z + 0.0, r, g, b });
            try list.appendSlice(allocator, &.{ x + 0.0, y + 0.0, z + 0.0, r, g, b });
            try list.appendSlice(allocator, &.{ x + 0.0, y + 0.0, z + 1.0, r, g, b });
            try list.appendSlice(allocator, &.{ x + 0.0, y + 1.0, z + 1.0, r, g, b });
        },
        .Right => { // +X
            try list.appendSlice(allocator, &.{ x + 1.0, y + 1.0, z + 1.0, r, g, b });
            try list.appendSlice(allocator, &.{ x + 1.0, y + 0.0, z + 0.0, r, g, b });
            try list.appendSlice(allocator, &.{ x + 1.0, y + 1.0, z + 0.0, r, g, b });
            try list.appendSlice(allocator, &.{ x + 1.0, y + 0.0, z + 0.0, r, g, b });
            try list.appendSlice(allocator, &.{ x + 1.0, y + 1.0, z + 1.0, r, g, b });
            try list.appendSlice(allocator, &.{ x + 1.0, y + 0.0, z + 1.0, r, g, b });
        },
        .Bottom => { // -Y
            try list.appendSlice(allocator, &.{ x + 0.0, y + 0.0, z + 0.0, r, g, b });
            try list.appendSlice(allocator, &.{ x + 1.0, y + 0.0, z + 0.0, r, g, b });
            try list.appendSlice(allocator, &.{ x + 1.0, y + 0.0, z + 1.0, r, g, b });
            try list.appendSlice(allocator, &.{ x + 1.0, y + 0.0, z + 1.0, r, g, b });
            try list.appendSlice(allocator, &.{ x + 0.0, y + 0.0, z + 1.0, r, g, b });
            try list.appendSlice(allocator, &.{ x + 0.0, y + 0.0, z + 0.0, r, g, b });
        },
        .Top => { // +Y
            try list.appendSlice(allocator, &.{ x + 0.0, y + 1.0, z + 0.0, r, g, b });
            try list.appendSlice(allocator, &.{ x + 0.0, y + 1.0, z + 1.0, r, g, b });
            try list.appendSlice(allocator, &.{ x + 1.0, y + 1.0, z + 1.0, r, g, b });
            try list.appendSlice(allocator, &.{ x + 1.0, y + 1.0, z + 1.0, r, g, b });
            try list.appendSlice(allocator, &.{ x + 1.0, y + 1.0, z + 0.0, r, g, b });
            try list.appendSlice(allocator, &.{ x + 0.0, y + 1.0, z + 0.0, r, g, b });
        },
    }
}
