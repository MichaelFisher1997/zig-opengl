//! Terrain generator using noise functions.

const std = @import("std");
const Noise = @import("noise.zig").Noise;
const Chunk = @import("../chunk.zig").Chunk;
const CHUNK_SIZE_X = @import("../chunk.zig").CHUNK_SIZE_X;
const CHUNK_SIZE_Y = @import("../chunk.zig").CHUNK_SIZE_Y;
const CHUNK_SIZE_Z = @import("../chunk.zig").CHUNK_SIZE_Z;
const BlockType = @import("../block.zig").BlockType;

pub const TerrainGenerator = struct {
    noise: Noise,

    // Terrain parameters
    sea_level: u32 = 62,
    base_height: u32 = 64,
    height_scale: f32 = 32,
    noise_scale: f32 = 64,

    pub fn init(seed: u64) TerrainGenerator {
        return .{
            .noise = Noise.init(seed),
        };
    }

    /// Generate terrain for a chunk
    pub fn generate(self: *const TerrainGenerator, chunk: *Chunk) void {
        const world_x = chunk.getWorldX();
        const world_z = chunk.getWorldZ();

        var local_z: u32 = 0;
        while (local_z < CHUNK_SIZE_Z) : (local_z += 1) {
            var local_x: u32 = 0;
            while (local_x < CHUNK_SIZE_X) : (local_x += 1) {
                const wx: f32 = @floatFromInt(world_x + @as(i32, @intCast(local_x)));
                const wz: f32 = @floatFromInt(world_z + @as(i32, @intCast(local_z)));

                // Get height from noise
                const height_noise = self.noise.getHeight(wx, wz, self.noise_scale);
                const terrain_height: u32 = @intFromFloat(@as(f32, @floatFromInt(self.base_height)) + height_noise * self.height_scale);

                // Fill column
                var y: u32 = 0;
                while (y < CHUNK_SIZE_Y) : (y += 1) {
                    const block = self.getBlockAt(local_x, y, local_z, terrain_height);
                    chunk.setBlock(local_x, y, local_z, block);
                }
            }
        }

        chunk.generated = true;
        chunk.dirty = true;
    }

    fn getBlockAt(self: *const TerrainGenerator, x: u32, y: u32, z: u32, terrain_height: u32) BlockType {
        _ = x;
        _ = z;

        if (y == 0) {
            return .bedrock;
        } else if (y < terrain_height - 4) {
            return .stone;
        } else if (y < terrain_height) {
            return .dirt;
        } else if (y == terrain_height) {
            if (y < self.sea_level) {
                return .sand; // Beach/underwater
            } else {
                return .grass;
            }
        } else if (y <= self.sea_level) {
            return .water;
        } else {
            return .air;
        }
    }
};
