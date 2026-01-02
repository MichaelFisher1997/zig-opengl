//! World Classification Map - authoritative world layout for LOD
//!
//! Computed ONCE per region, deterministically
//! All LOD levels sample from this SAME map (no re-computation)
//!
//! LOD-INVARIANT: These values MUST be identical for all LODs:
//! - Biome ID
//! - Region Role / Mood
//! - Land vs water decision
//! - Sand vs grass vs rock surface type
//! - Lake existence (not shape detail)
//! - Path / valley / river masks

const std = @import("std");
const BiomeId = @import("biome.zig").BiomeId;

pub const CELL_SIZE: u32 = 8;

/// Surface types (what's on top at this position)
pub const SurfaceType = enum(u8) {
    grass,
    sand,
    rock,
    snow,
    water_deep,
    water_shallow,
    dirt,
    stone,
};

/// Region roles (from RegionMood system)
pub const RegionRole = enum(u8) {
    inland_low,
    inland_high,
    mountain_core,
    coast,
    deep_ocean,
};

/// Path types (from path system)
pub const PathType = enum(u8) {
    none,
    valley,
    river,
    plains_corridor,
};

/// Single classification cell
pub const ClassCell = struct {
    /// Main biome ID (from biome blending)
    biome_id: BiomeId,
    /// What surface material is on top
    surface_type: SurfaceType,
    /// Is this position water (boolean)
    is_water: bool,
    /// Region role for this area
    region_role: RegionRole,
    /// Path influence at this location
    path_type: PathType,
};

/// World Classification Map
pub const WorldClassMap = struct {
    /// Grid dimensions
    const GRID_SIZE_X: u32 = 10;
    const GRID_SIZE_Z: u32 = 10;
    const CELL_COUNT: u32 = GRID_SIZE_X * GRID_SIZE_Z;

    /// Classification grid (2D array of cells)
    cells: [CELL_COUNT]ClassCell,

    /// Initialize classification map
    pub fn init() WorldClassMap {
        return .{
            .cells = undefined,
        };
    }

    /// Get classification cell at local grid coordinates
    pub fn getCell(self: *const WorldClassMap, gx: u32, gz: u32) *const ClassCell {
        if (gx >= GRID_SIZE_X or gz >= GRID_SIZE_Z) {
            // Return default cell for out of bounds
            static const default_cell = ClassCell{
                .biome_id = .plains,
                .surface_type = .grass,
                .is_water = false,
                .region_role = .inland_low,
                .path_type = .none,
            };
            return &default_cell;
        }
        return &self.cells[gx + gz * GRID_SIZE_X];
    }
};
