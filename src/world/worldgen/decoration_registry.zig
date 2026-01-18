//! Registry of all available decorations and their placement rules.
//! Configures the specific decorations (both simple and schematic) that populate the world.
//! Re-exports decoration types for consumers like the generator.

const std = @import("std");
const BlockType = @import("../block.zig").BlockType;
const BiomeId = @import("biome.zig").BiomeId;
const biome_mod = @import("biome.zig");
const tree_registry = @import("tree_registry.zig");

// Import types and schematics
pub const types = @import("decoration_types.zig");
pub const schematics = @import("schematics.zig");

// Re-export types for consumers (like generator.zig)
pub const Rotation = types.Rotation;
pub const SimpleDecoration = types.SimpleDecoration;
pub const SchematicBlock = types.SchematicBlock;
pub const Schematic = types.Schematic;
pub const SchematicDecoration = types.SchematicDecoration;
pub const Decoration = types.Decoration;
pub const DecorationProvider = @import("decoration_provider.zig").DecorationProvider;

pub const DECORATIONS = [_]Decoration{
    // === Grass ===
    .{ .simple = .{
        .block = .tall_grass,
        .place_on = &.{.grass},
        .biomes = &.{ .plains, .forest, .savanna, .swamp, .jungle, .taiga },
        .probability = 0.5,
    } },

    // === Flowers (Standard) ===
    .{
        .simple = .{
            .block = .flower_red,
            .place_on = &.{.grass},
            .biomes = &.{ .plains, .forest },
            .probability = 0.02,
            .variant_min = -0.6, // Normal distribution
        },
    },

    // === Flower Patches (Variant < -0.6) ===
    .{
        .simple = .{
            .block = .flower_yellow,
            .place_on = &.{.grass},
            .biomes = &.{ .plains, .forest },
            .probability = 0.4, // Dense!
            .variant_max = -0.6,
        },
    },

    // === Dead Bush ===
    .{ .simple = .{
        .block = .dead_bush,
        .place_on = &.{ .sand, .red_sand },
        .biomes = &.{ .desert, .badlands },
        .probability = 0.02,
    } },

    // === Cacti ===
    .{ .simple = .{
        .block = .cactus,
        .place_on = &.{.sand},
        .biomes = &.{.desert},
        .probability = 0.01,
    } },

    // === Boulders (Rocky Patches: Variant > 0.6) ===
    .{
        .simple = .{
            .block = .cobblestone,
            .place_on = &.{.grass},
            .biomes = &.{ .plains, .mountains, .taiga },
            .probability = 0.05,
            .variant_min = 0.6,
        },
    },
};

const Chunk = @import("../chunk.zig").Chunk;

pub const StandardDecorationProvider = struct {
    pub fn provider() DecorationProvider {
        return .{
            .ptr = null, // Stateless
            .vtable = &VTABLE,
        };
    }

    const VTABLE = DecorationProvider.VTable{
        .decorate = decorate,
    };

    fn decorate(
        ptr: ?*anyopaque,
        chunk: *Chunk,
        local_x: u32,
        local_z: u32,
        surface_y: i32,
        surface_block: BlockType,
        biome: BiomeId,
        variant: f32,
        allow_subbiomes: bool,
        veg_mult: f32,
        random: std.Random,
    ) void {
        _ = ptr;

        // 1. Apply simple decorations (grass, flowers, etc.)
        for (DECORATIONS) |deco| {
            switch (deco) {
                .simple => |s| {
                    if (!s.isAllowed(biome, surface_block)) continue;

                    if (!allow_subbiomes) {
                        if (s.variant_min != -1.0 or s.variant_max != 1.0) continue;
                    } else {
                        if (variant < s.variant_min or variant > s.variant_max) continue;
                    }

                    const prob = @min(1.0, s.probability * veg_mult);
                    if (random.float(f32) >= prob) continue;

                    chunk.setBlock(local_x, @intCast(surface_y + 1), local_z, s.block);
                    // Don't break, allow trying other non-conflicting decorations?
                    // Original code broke here. Let's keep it consistent: one simple decoration per block.
                    break;
                },
                .schematic => {}, // No longer used in static list
            }
        }

        // 2. Apply trees from registry based on biome
        const biome_def = biome_mod.getBiomeDefinition(biome);
        const vegetation = biome_def.vegetation;

        if (vegetation.tree_types.len > 0) {
            for (vegetation.tree_types) |tree_type| {
                if (tree_registry.getTreeDefinition(tree_type)) |tree_def| {
                    // Check surface block
                    var valid_surface = false;
                    for (tree_def.place_on) |valid_block| {
                        if (surface_block == valid_block) {
                            valid_surface = true;
                            break;
                        }
                    }
                    if (!valid_surface) continue;

                    // Check variant noise
                    if (allow_subbiomes) {
                        if (variant < tree_def.variant_min or variant > tree_def.variant_max) continue;
                    } else {
                        // Strict mode? Or just ignore variant requirements?
                        // Original code: if (!allow_subbiomes) check if range is default (-1 to 1).
                        if (tree_def.variant_min != -1.0 or tree_def.variant_max != 1.0) continue;
                    }

                    // Check probability
                    const prob = @min(1.0, tree_def.probability * veg_mult);
                    if (random.float(f32) >= prob) continue;

                    // Place tree
                    tree_def.schematic.place(chunk, local_x, @intCast(surface_y + 1), local_z, random);

                    // If a tree is placed, stop trying other trees?
                    // Usually yes, we don't want trees on top of each other.
                    break;
                }
            }
        }
    }
};
