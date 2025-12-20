//! Chunk mesh generation with visible face culling.
//! Only generates faces where a solid block meets air/transparent block.

const std = @import("std");
const c = @cImport({
    @cInclude("GL/glew.h");
});

const Chunk = @import("chunk.zig").Chunk;
const CHUNK_SIZE_X = @import("chunk.zig").CHUNK_SIZE_X;
const CHUNK_SIZE_Y = @import("chunk.zig").CHUNK_SIZE_Y;
const CHUNK_SIZE_Z = @import("chunk.zig").CHUNK_SIZE_Z;
const BlockType = @import("block.zig").BlockType;
const Face = @import("block.zig").Face;
const ALL_FACES = @import("block.zig").ALL_FACES;

pub const ChunkMesh = struct {
    vao: c.GLuint,
    vbo: c.GLuint,
    vertex_count: u32,

    /// Allocator for vertex data during mesh building
    allocator: std.mem.Allocator,

    /// Is the mesh ready to render?
    ready: bool = false,

    pub fn init(allocator: std.mem.Allocator) ChunkMesh {
        var vao: c.GLuint = undefined;
        var vbo: c.GLuint = undefined;

        c.glGenVertexArrays().?(1, &vao);
        c.glGenBuffers().?(1, &vbo);

        // Setup vertex format: position (3) + color (3) + normal (3) = 9 floats
        c.glBindVertexArray().?(vao);
        c.glBindBuffer().?(c.GL_ARRAY_BUFFER, vbo);

        const stride: c.GLsizei = 9 * @sizeOf(f32);

        // Position (location 0)
        c.glVertexAttribPointer().?(0, 3, c.GL_FLOAT, c.GL_FALSE, stride, null);
        c.glEnableVertexAttribArray().?(0);

        // Color (location 1)
        c.glVertexAttribPointer().?(1, 3, c.GL_FLOAT, c.GL_FALSE, stride, @ptrFromInt(3 * @sizeOf(f32)));
        c.glEnableVertexAttribArray().?(1);

        // Normal (location 2)
        c.glVertexAttribPointer().?(2, 3, c.GL_FLOAT, c.GL_FALSE, stride, @ptrFromInt(6 * @sizeOf(f32)));
        c.glEnableVertexAttribArray().?(2);

        c.glBindVertexArray().?(0);

        return .{
            .vao = vao,
            .vbo = vbo,
            .vertex_count = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ChunkMesh) void {
        c.glDeleteVertexArrays().?(1, &self.vao);
        c.glDeleteBuffers().?(1, &self.vbo);
    }

    /// Build mesh from chunk data with face culling
    pub fn build(self: *ChunkMesh, chunk: *const Chunk) !void {
        var vertices = std.ArrayListUnmanaged(f32){};
        defer vertices.deinit(self.allocator);

        // Reserve modest initial capacity (will grow as needed)
        try vertices.ensureTotalCapacity(self.allocator, 1024 * 9);

        // Iterate through all blocks
        var y: u32 = 0;
        while (y < CHUNK_SIZE_Y) : (y += 1) {
            var z: u32 = 0;
            while (z < CHUNK_SIZE_Z) : (z += 1) {
                var x: u32 = 0;
                while (x < CHUNK_SIZE_X) : (x += 1) {
                    const block = chunk.getBlock(x, y, z);

                    // Skip air blocks
                    if (block.isAir()) continue;

                    const world_x: f32 = @floatFromInt(@as(i32, @intCast(x)) + chunk.getWorldX());
                    const world_y: f32 = @floatFromInt(y);
                    const world_z: f32 = @floatFromInt(@as(i32, @intCast(z)) + chunk.getWorldZ());

                    // Check each face
                    for (ALL_FACES) |face| {
                        if (self.shouldRenderFace(chunk, x, y, z, face)) {
                            try self.addFace(&vertices, world_x, world_y, world_z, face, block);
                        }
                    }
                }
            }
        }

        // Upload to GPU
        self.uploadVertices(vertices.items);
    }

    /// Check if a face should be rendered (neighbor is air/transparent)
    fn shouldRenderFace(self: *ChunkMesh, chunk: *const Chunk, x: u32, y: u32, z: u32, face: Face) bool {
        _ = self;
        const offset = face.getOffset();
        const nx = @as(i32, @intCast(x)) + offset.x;
        const ny = @as(i32, @intCast(y)) + offset.y;
        const nz = @as(i32, @intCast(z)) + offset.z;

        const neighbor = chunk.getBlockSafe(nx, ny, nz);
        return neighbor.isTransparent();
    }

    /// Add a face (2 triangles, 6 vertices) to the vertex list
    fn addFace(self: *ChunkMesh, vertices: *std.ArrayListUnmanaged(f32), x: f32, y: f32, z: f32, face: Face, block: BlockType) !void {
        const color = block.getFaceColor(face);
        const normal = face.getNormal();
        const nf = [3]f32{
            @floatFromInt(normal[0]),
            @floatFromInt(normal[1]),
            @floatFromInt(normal[2]),
        };

        // Get the 4 corners of the face
        const corners = getFaceCorners(x, y, z, face);

        // Triangle 1: 0, 1, 2
        try addVertex(self.allocator, vertices, corners[0], color, nf);
        try addVertex(self.allocator, vertices, corners[1], color, nf);
        try addVertex(self.allocator, vertices, corners[2], color, nf);

        // Triangle 2: 0, 2, 3
        try addVertex(self.allocator, vertices, corners[0], color, nf);
        try addVertex(self.allocator, vertices, corners[2], color, nf);
        try addVertex(self.allocator, vertices, corners[3], color, nf);
    }

    fn addVertex(allocator: std.mem.Allocator, vertices: *std.ArrayListUnmanaged(f32), pos: [3]f32, color: [3]f32, normal: [3]f32) !void {
        try vertices.append(allocator, pos[0]);
        try vertices.append(allocator, pos[1]);
        try vertices.append(allocator, pos[2]);
        try vertices.append(allocator, color[0]);
        try vertices.append(allocator, color[1]);
        try vertices.append(allocator, color[2]);
        try vertices.append(allocator, normal[0]);
        try vertices.append(allocator, normal[1]);
        try vertices.append(allocator, normal[2]);
    }

    fn uploadVertices(self: *ChunkMesh, vertices: []const f32) void {
        c.glBindBuffer().?(c.GL_ARRAY_BUFFER, self.vbo);
        c.glBufferData().?(
            c.GL_ARRAY_BUFFER,
            @intCast(vertices.len * @sizeOf(f32)),
            vertices.ptr,
            c.GL_STATIC_DRAW,
        );
        self.vertex_count = @intCast(vertices.len / 9);
        self.ready = self.vertex_count > 0;
    }

    pub fn draw(self: *const ChunkMesh) void {
        if (!self.ready) return;

        c.glBindVertexArray().?(self.vao);
        c.glDrawArrays(c.GL_TRIANGLES, 0, @intCast(self.vertex_count));
    }
};

/// Get the 4 corners of a face (counter-clockwise winding)
fn getFaceCorners(x: f32, y: f32, z: f32, face: Face) [4][3]f32 {
    return switch (face) {
        .top => .{
            .{ x, y + 1, z },
            .{ x, y + 1, z + 1 },
            .{ x + 1, y + 1, z + 1 },
            .{ x + 1, y + 1, z },
        },
        .bottom => .{
            .{ x, y, z + 1 },
            .{ x, y, z },
            .{ x + 1, y, z },
            .{ x + 1, y, z + 1 },
        },
        .north => .{
            .{ x + 1, y, z },
            .{ x, y, z },
            .{ x, y + 1, z },
            .{ x + 1, y + 1, z },
        },
        .south => .{
            .{ x, y, z + 1 },
            .{ x + 1, y, z + 1 },
            .{ x + 1, y + 1, z + 1 },
            .{ x, y + 1, z + 1 },
        },
        .east => .{
            .{ x + 1, y, z + 1 },
            .{ x + 1, y, z },
            .{ x + 1, y + 1, z },
            .{ x + 1, y + 1, z + 1 },
        },
        .west => .{
            .{ x, y, z },
            .{ x, y, z + 1 },
            .{ x, y + 1, z + 1 },
            .{ x, y + 1, z },
        },
    };
}
