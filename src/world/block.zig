//! Block types and their properties.

const std = @import("std");

/// Biome types for terrain generation
/// NOTE: This enum is kept for compatibility. See worldgen/biome.zig for
/// the data-driven BiomeDefinition system.
/// Per worldgen-revamp.md: includes transition micro-biomes
pub const Biome = enum(u8) {
    deep_ocean = 0,
    ocean = 1,
    beach = 2,
    plains = 3,
    forest = 4,
    taiga = 5,
    desert = 6,
    snow_tundra = 7,
    mountains = 8,
    snowy_mountains = 9,
    river = 10,
    swamp = 11,
    mangrove_swamp = 12,
    jungle = 13,
    savanna = 14,
    badlands = 15,
    mushroom_fields = 16,
    // Per worldgen-revamp.md Section 4.3: Transition micro-biomes
    foothills = 17,
    marsh = 18,
    dry_plains = 19,
    coastal_plains = 20,

    /// Get surface block for this biome
    /// Prefer using BiomeDefinition.surface from worldgen/biome.zig
    pub fn getSurfaceBlock(self: Biome) BlockType {
        return switch (self) {
            .deep_ocean, .ocean => .gravel,
            .beach => .sand,
            .plains, .forest, .swamp, .jungle, .savanna, .foothills, .marsh, .dry_plains, .coastal_plains => .grass,
            .taiga => .grass,
            .desert => .sand,
            .snow_tundra, .snowy_mountains => .snow_block,
            .mountains => .stone,
            .river => .sand,
            .mangrove_swamp => .mud,
            .badlands => .red_sand,
            .mushroom_fields => .mycelium,
        };
    }

    /// Get filler block (subsurface) for this biome
    /// Prefer using BiomeDefinition.surface from worldgen/biome.zig
    pub fn getFillerBlock(self: Biome) BlockType {
        return switch (self) {
            .deep_ocean => .gravel,
            .ocean => .sand,
            .beach, .desert, .river => .sand,
            .plains, .forest, .taiga, .swamp, .jungle, .savanna, .foothills, .marsh, .dry_plains, .coastal_plains => .dirt,
            .snow_tundra => .dirt,
            .mountains, .snowy_mountains => .stone,
            .mangrove_swamp => .mud,
            .badlands => .terracotta,
            .mushroom_fields => .dirt,
        };
    }

    /// Get ocean floor block for this biome
    pub fn getOceanFloorBlock(self: Biome, depth: f32) BlockType {
        _ = self;
        if (depth > 30) return .gravel; // Deep ocean floor
        if (depth > 15) return .clay; // Mid-depth
        return .sand; // Shallow
    }
};

pub const BlockType = enum(u8) {
    air = 0,
    stone = 1,
    dirt = 2,
    grass = 3,
    sand = 4,
    water = 5,
    wood = 6,
    leaves = 7,
    cobblestone = 8,
    bedrock = 9,
    gravel = 10,
    glass = 11,
    snow_block = 12,
    cactus = 13,
    coal_ore = 14,
    iron_ore = 15,
    gold_ore = 16,
    clay = 17,
    glowstone = 18,
    mud = 19,
    mangrove_log = 20,
    mangrove_leaves = 21,
    mangrove_roots = 22,
    jungle_log = 23,
    jungle_leaves = 24,
    melon = 25,
    bamboo = 26,
    acacia_log = 27,
    acacia_leaves = 28,
    acacia_sapling = 29,
    terracotta = 30,
    red_sand = 31,
    mycelium = 32,
    mushroom_stem = 33,
    red_mushroom_block = 34,
    brown_mushroom_block = 35,
    tall_grass = 36,
    flower_red = 37,
    flower_yellow = 38,
    dead_bush = 39,
    birch_log = 40,
    birch_leaves = 41,
    spruce_log = 42,
    spruce_leaves = 43,
    vine = 44,

    _,
};

pub const Face = enum(u3) {
    top = 0, // +Y
    bottom = 1, // -Y
    north = 2, // -Z
    south = 3, // +Z
    east = 4, // +X
    west = 5, // -X

    /// Get ambient occlusion-style shading multiplier
    pub fn getShade(self: Face) f32 {
        return switch (self) {
            .top => 1.0,
            .bottom => 0.5,
            .north, .south => 0.8,
            .east, .west => 0.7,
        };
    }

    /// Get normal vector for this face
    pub fn getNormal(self: Face) [3]i8 {
        return switch (self) {
            .top => .{ 0, 1, 0 },
            .bottom => .{ 0, -1, 0 },
            .north => .{ 0, 0, -1 },
            .south => .{ 0, 0, 1 },
            .east => .{ 1, 0, 0 },
            .west => .{ -1, 0, 0 },
        };
    }

    /// Get offset to neighboring block for this face
    pub fn getOffset(self: Face) struct { x: i32, y: i32, z: i32 } {
        const n = self.getNormal();
        return .{ .x = n[0], .y = n[1], .z = n[2] };
    }
};

/// All 6 faces for iteration
pub const ALL_FACES = [_]Face{ .top, .bottom, .north, .south, .east, .west };
