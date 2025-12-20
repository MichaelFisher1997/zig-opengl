//! World manager - handles chunk loading, unloading, and access.

const std = @import("std");
const Chunk = @import("chunk.zig").Chunk;
const ChunkMesh = @import("chunk_mesh.zig").ChunkMesh;
const BlockType = @import("block.zig").BlockType;
const worldToChunk = @import("chunk.zig").worldToChunk;
const worldToLocal = @import("chunk.zig").worldToLocal;
const CHUNK_SIZE_X = @import("chunk.zig").CHUNK_SIZE_X;
const CHUNK_SIZE_Z = @import("chunk.zig").CHUNK_SIZE_Z;
const TerrainGenerator = @import("worldgen/generator.zig").TerrainGenerator;

const Mat4 = @import("../engine/math/mat4.zig").Mat4;
const Vec3 = @import("../engine/math/vec3.zig").Vec3;
const Frustum = @import("../engine/math/frustum.zig").Frustum;
const Shader = @import("../engine/graphics/shader.zig").Shader;

pub const ChunkKey = struct {
    x: i32,
    z: i32,

    pub fn hash(self: ChunkKey) u64 {
        // Combine x and z into a single hash
        const ux: u64 = @bitCast(@as(i64, self.x));
        const uz: u64 = @bitCast(@as(i64, self.z));
        return ux ^ (uz *% 0x9e3779b97f4a7c15);
    }

    pub fn eql(a: ChunkKey, b: ChunkKey) bool {
        return a.x == b.x and a.z == b.z;
    }
};

const ChunkKeyContext = struct {
    pub fn hash(self: @This(), key: ChunkKey) u64 {
        _ = self;
        return key.hash();
    }

    pub fn eql(self: @This(), a: ChunkKey, b: ChunkKey) bool {
        _ = self;
        return a.eql(b);
    }
};

pub const ChunkData = struct {
    chunk: Chunk,
    mesh: ChunkMesh,
};

/// Render statistics
pub const RenderStats = struct {
    chunks_total: u32 = 0,
    chunks_rendered: u32 = 0,
    chunks_culled: u32 = 0,
    vertices_rendered: u64 = 0,
};

pub const World = struct {
    chunks: std.HashMap(ChunkKey, *ChunkData, ChunkKeyContext, 80),
    allocator: std.mem.Allocator,
    generator: TerrainGenerator,
    render_distance: i32,
    last_render_stats: RenderStats,

    pub fn init(allocator: std.mem.Allocator, render_distance: i32, seed: u64) World {
        return .{
            .chunks = std.HashMap(ChunkKey, *ChunkData, ChunkKeyContext, 80).init(allocator),
            .allocator = allocator,
            .render_distance = render_distance,
            .generator = TerrainGenerator.init(seed),
            .last_render_stats = .{},
        };
    }

    pub fn deinit(self: *World) void {
        var iter = self.chunks.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.*.mesh.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.chunks.deinit();
    }

    /// Get or create a chunk at the given chunk coordinates
    pub fn getOrCreateChunk(self: *World, chunk_x: i32, chunk_z: i32) !*ChunkData {
        const key = ChunkKey{ .x = chunk_x, .z = chunk_z };

        if (self.chunks.get(key)) |data| {
            return data;
        }

        // Create new chunk
        const data = try self.allocator.create(ChunkData);
        data.* = .{
            .chunk = Chunk.init(chunk_x, chunk_z),
            .mesh = ChunkMesh.init(self.allocator),
        };

        // Generate terrain using noise
        self.generator.generate(&data.chunk);

        try self.chunks.put(key, data);
        return data;
    }

    /// Get chunk at coordinates (returns null if not loaded)
    pub fn getChunk(self: *World, chunk_x: i32, chunk_z: i32) ?*ChunkData {
        const key = ChunkKey{ .x = chunk_x, .z = chunk_z };
        return self.chunks.get(key);
    }

    /// Get block at world coordinates
    pub fn getBlock(self: *World, world_x: i32, world_y: i32, world_z: i32) BlockType {
        if (world_y < 0 or world_y >= 256) return .air;

        const chunk_pos = worldToChunk(world_x, world_z);
        const chunk_data = self.getChunk(chunk_pos.chunk_x, chunk_pos.chunk_z) orelse return .air;

        const local = worldToLocal(world_x, world_z);
        return chunk_data.chunk.getBlock(local.x, @intCast(world_y), local.z);
    }

    /// Set block at world coordinates
    pub fn setBlock(self: *World, world_x: i32, world_y: i32, world_z: i32, block: BlockType) !void {
        if (world_y < 0 or world_y >= 256) return;

        const chunk_pos = worldToChunk(world_x, world_z);
        const chunk_data = try self.getOrCreateChunk(chunk_pos.chunk_x, chunk_pos.chunk_z);

        const local = worldToLocal(world_x, world_z);
        chunk_data.chunk.setBlock(local.x, @intCast(world_y), local.z, block);
    }

    /// Update chunks around player position
    pub fn update(self: *World, player_pos: Vec3) !void {
        const player_chunk = worldToChunk(@intFromFloat(player_pos.x), @intFromFloat(player_pos.z));

        // Load chunks within render distance
        var cz = player_chunk.chunk_z - self.render_distance;
        while (cz <= player_chunk.chunk_z + self.render_distance) : (cz += 1) {
            var cx = player_chunk.chunk_x - self.render_distance;
            while (cx <= player_chunk.chunk_x + self.render_distance) : (cx += 1) {
                const data = try self.getOrCreateChunk(cx, cz);

                // Rebuild mesh if dirty
                if (data.chunk.dirty) {
                    try data.mesh.build(&data.chunk);
                    data.chunk.dirty = false;
                }
            }
        }
    }

    /// Render all loaded chunks with frustum culling
    pub fn render(self: *World, shader: *const Shader, view_proj: Mat4) void {
        shader.use();

        // Extract frustum from view-projection matrix
        const frustum = Frustum.fromViewProj(view_proj);

        self.last_render_stats = .{};

        var iter = self.chunks.iterator();
        while (iter.next()) |entry| {
            const key = entry.key_ptr.*;
            const data = entry.value_ptr.*;

            if (!data.mesh.ready) continue;

            self.last_render_stats.chunks_total += 1;

            // Frustum culling
            if (!frustum.intersectsChunk(key.x, key.z)) {
                self.last_render_stats.chunks_culled += 1;
                continue;
            }

            self.last_render_stats.chunks_rendered += 1;
            self.last_render_stats.vertices_rendered += data.mesh.vertex_count;

            // Model matrix is identity since chunk vertices are in world space
            shader.setMat4("transform", &view_proj.data);
            data.mesh.draw();
        }
    }

    /// Get render statistics from last frame
    pub fn getRenderStats(self: *const World) RenderStats {
        return self.last_render_stats;
    }

    /// Get statistics
    pub fn getStats(self: *World) struct { chunks_loaded: usize, total_vertices: u64 } {
        var total_verts: u64 = 0;
        var iter = self.chunks.iterator();
        while (iter.next()) |entry| {
            total_verts += entry.value_ptr.*.mesh.vertex_count;
        }
        return .{
            .chunks_loaded = self.chunks.count(),
            .total_vertices = total_verts,
        };
    }
};
