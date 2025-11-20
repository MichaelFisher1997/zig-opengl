const std = @import("std");
const chunk_mod = @import("chunk.zig");
const mesh_mod = @import("mesh.zig");
const noise_mod = @import("noise.zig");
const block_mod = @import("block.zig");
const math = @import("math.zig");
const Vec3 = math.Vec3;

// Import C headers for GL types
const c = @cImport({
    @cDefine("_FORTIFY_SOURCE", "0");
    @cInclude("SDL3/SDL.h");
    @cInclude("GL/glew.h");
    @cInclude("SDL3/SDL_opengl.h");
});

pub const ChunkPos = struct {
    x: i32,
    z: i32,
};

const WorldChunk = struct {
    data: *chunk_mod.Chunk,
    mesh: ?mesh_mod.ChunkMesh,
    vao: c.GLuint,
    vbo: c.GLuint,
    vertex_count: c_int,

    pub fn deinit(self: *WorldChunk, allocator: std.mem.Allocator) void {
        if (self.mesh) |m| m.deinit();
        allocator.destroy(self.data);
        if (self.vao != 0) c.glDeleteVertexArrays().?(1, &self.vao);
        if (self.vbo != 0) c.glDeleteBuffers().?(1, &self.vbo);
    }
};

pub const World = struct {
    chunks: std.AutoHashMap(ChunkPos, *WorldChunk),
    allocator: std.mem.Allocator,
    noise: noise_mod.Perlin,
    render_distance: i32,

    pub fn init(allocator: std.mem.Allocator, seed: u32) World {
        return World{
            .chunks = std.AutoHashMap(ChunkPos, *WorldChunk).init(allocator),
            .allocator = allocator,
            .noise = noise_mod.Perlin.init(seed),
            .render_distance = 4,
        };
    }

    pub fn deinit(self: *World) void {
        var it = self.chunks.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.deinit(self.allocator);
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.chunks.deinit();
    }

    pub fn update(self: *World, player_pos: Vec3) !void {
        const chunk_x = @as(i32, @intFromFloat(@floor(player_pos.x / @as(f32, @floatFromInt(chunk_mod.CHUNK_SIZE_X)))));
        const chunk_z = @as(i32, @intFromFloat(@floor(player_pos.z / @as(f32, @floatFromInt(chunk_mod.CHUNK_SIZE_Z)))));

        // Load chunks in radius
        var x = -self.render_distance;
        while (x <= self.render_distance) : (x += 1) {
            var z = -self.render_distance;
            while (z <= self.render_distance) : (z += 1) {
                const pos = ChunkPos{ .x = chunk_x + x, .z = chunk_z + z };
                if (!self.chunks.contains(pos)) {
                    try self.loadChunk(pos);
                }
            }
        }

        // Ideally unload chunks too, but let's keep it simple for now (infinite memory!)
    }

    fn loadChunk(self: *World, pos: ChunkPos) !void {
        const chunk_data = try self.allocator.create(chunk_mod.Chunk);
        chunk_data.* = chunk_mod.Chunk.init();

        // Generate Terrain
        self.generateTerrain(chunk_data, pos);

        const world_chunk = try self.allocator.create(WorldChunk);
        world_chunk.data = chunk_data;
        world_chunk.mesh = null;
        world_chunk.vao = 0;
        world_chunk.vbo = 0;
        world_chunk.vertex_count = 0;

        // Generate Mesh immediately (not threaded yet)
        // Note: Mesh generation currently depends on neighbors for occlusion culling.
        // The current implementation in mesh.zig only looks at the passed chunk itself.
        // If we want inter-chunk culling, we need to pass neighbors or a "GetBlock" callback to generateMesh.
        // For Phase 5, let's stick to intra-chunk culling (faces at chunk borders will always be drawn).
        const mesh = try mesh_mod.generateMesh(self.allocator, chunk_data);
        world_chunk.mesh = mesh;
        world_chunk.vertex_count = @as(c_int, @intCast(mesh.vertices.len / 6));

        if (world_chunk.vertex_count > 0) {
            c.glGenVertexArrays().?(1, &world_chunk.vao);
            c.glGenBuffers().?(1, &world_chunk.vbo);

            c.glBindVertexArray().?(world_chunk.vao);
            c.glBindBuffer().?(c.GL_ARRAY_BUFFER, world_chunk.vbo);
            c.glBufferData().?(c.GL_ARRAY_BUFFER, @as(c.GLsizeiptr, @intCast(mesh.vertices.len * @sizeOf(f32))), mesh.vertices.ptr, c.GL_STATIC_DRAW);

            // Position
            c.glVertexAttribPointer().?(0, 3, c.GL_FLOAT, c.GL_FALSE, 6 * @sizeOf(f32), null);
            c.glEnableVertexAttribArray().?(0);
            // Color
            c.glVertexAttribPointer().?(1, 3, c.GL_FLOAT, c.GL_FALSE, 6 * @sizeOf(f32), @ptrFromInt(3 * @sizeOf(f32)));
            c.glEnableVertexAttribArray().?(1);
        }

        try self.chunks.put(pos, world_chunk);
    }

    fn generateTerrain(self: World, chunk: *chunk_mod.Chunk, pos: ChunkPos) void {
        for (0..chunk_mod.CHUNK_SIZE_X) |lx| {
            for (0..chunk_mod.CHUNK_SIZE_Z) |lz| {
                // Global coordinates
                const gx = @as(f32, @floatFromInt(pos.x * chunk_mod.CHUNK_SIZE_X)) + @as(f32, @floatFromInt(lx));
                const gz = @as(f32, @floatFromInt(pos.z * chunk_mod.CHUNK_SIZE_Z)) + @as(f32, @floatFromInt(lz));

                // Noise parameters
                const scale = 0.01;
                const amplitude = 64.0;
                const base_height = 32.0;

                const n = self.noise.noise2d(gx * scale, gz * scale);
                const height = @as(i32, @intFromFloat(base_height + n * amplitude));

                const h = std.math.clamp(height, 0, chunk_mod.CHUNK_SIZE_Y - 1);
                const y_max = @as(usize, @intCast(h));

                for (0..y_max + 1) |y| {
                    var block_type = block_mod.BlockType.Stone;
                    if (y == y_max) {
                        block_type = .Grass;
                    } else if (y > y_max - 4) {
                        block_type = .Dirt;
                    }
                    chunk.setBlock(lx, y, lz, block_type);
                }
            }
        }
    }

    pub fn render(self: World, transform_loc: c.GLint, view_proj: math.Mat4) void {
        var it = self.chunks.iterator();
        while (it.next()) |entry| {
            const pos = entry.key_ptr.*;
            const chunk = entry.value_ptr.*;

            if (chunk.vertex_count == 0) continue;

            // Model matrix for chunk translation
            const model = math.Mat4.translate(@as(f32, @floatFromInt(pos.x * chunk_mod.CHUNK_SIZE_X)), 0.0, @as(f32, @floatFromInt(pos.z * chunk_mod.CHUNK_SIZE_Z)));

            const mvp = math.Mat4.multiply(view_proj, model);

            c.glUniformMatrix4fv().?(transform_loc, 1, c.GL_TRUE, &mvp.data[0][0]);

            c.glBindVertexArray().?(chunk.vao);
            c.glDrawArrays(c.GL_TRIANGLES, 0, chunk.vertex_count);
        }
    }
};
