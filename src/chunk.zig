const std = @import("std");
const block = @import("block.zig");
const Block = block.Block;
const BlockType = block.BlockType;

pub const CHUNK_SIZE_X = 16;
pub const CHUNK_SIZE_Y = 256;
pub const CHUNK_SIZE_Z = 16;

pub const Chunk = struct {
    blocks: [CHUNK_SIZE_X][CHUNK_SIZE_Y][CHUNK_SIZE_Z]Block,

    pub fn init() Chunk {
        var chunk = Chunk{
            .blocks = undefined,
        };
        chunk.fill(.Air);
        return chunk;
    }

    pub fn fill(self: *Chunk, block_type: BlockType) void {
        for (0..CHUNK_SIZE_X) |x| {
            for (0..CHUNK_SIZE_Y) |y| {
                for (0..CHUNK_SIZE_Z) |z| {
                    self.blocks[x][y][z] = Block{ .type = block_type };
                }
            }
        }
    }

    pub fn setBlock(self: *Chunk, x: usize, y: usize, z: usize, type_val: BlockType) void {
        if (x >= CHUNK_SIZE_X or y >= CHUNK_SIZE_Y or z >= CHUNK_SIZE_Z) return;
        self.blocks[x][y][z] = Block{ .type = type_val };
    }

    pub fn getBlock(self: Chunk, x: usize, y: usize, z: usize) Block {
        if (x >= CHUNK_SIZE_X or y >= CHUNK_SIZE_Y or z >= CHUNK_SIZE_Z) return Block{ .type = .Air };
        return self.blocks[x][y][z];
    }
};
