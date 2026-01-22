//! Texture Atlas for block textures.
//! Loads textures from resource packs with solid color fallback.
//! Supports HD texture packs (16x16 to 512x512) and PBR maps.

const std = @import("std");
const c = @import("../../c.zig").c;

const Texture = @import("texture.zig").Texture;
const FilterMode = @import("texture.zig").FilterMode;
const log = @import("../core/log.zig");
const resource_pack = @import("resource_pack.zig");
const BlockType = @import("../../world/block.zig").BlockType;
const block_registry = @import("../../world/block_registry.zig");
const PBRMapType = resource_pack.PBRMapType;

const rhi = @import("rhi.zig");

/// Default tile size in pixels (each block face texture)
pub const DEFAULT_TILE_SIZE: u32 = 16;

/// Number of tiles per row in the atlas
pub const TILES_PER_ROW: u32 = 16;

/// Supported tile sizes for HD texture packs
pub const SUPPORTED_TILE_SIZES = [_]u32{ 16, 32, 64, 128, 256, 512 };

/// Texture atlas for blocks with PBR support
pub const TextureAtlas = struct {
    /// Diffuse/albedo texture atlas
    texture: Texture,
    /// Normal map atlas (optional)
    normal_texture: ?Texture,
    /// Roughness map atlas (optional)
    roughness_texture: ?Texture,
    /// Displacement map atlas (optional)
    displacement_texture: ?Texture,

    allocator: std.mem.Allocator,
    pack_manager: ?*resource_pack.ResourcePackManager,
    tile_size: u32,
    atlas_size: u32,
    /// Whether PBR textures are available
    has_pbr: bool,

    tile_mappings: [256]BlockTiles,

    /// Tile indices for block faces [top, bottom, side]
    pub const BlockTiles = struct {
        top: u16,
        bottom: u16,
        side: u16,

        pub fn uniform(tile: u16) BlockTiles {
            return .{ .top = tile, .bottom = tile, .side = tile };
        }
    };

    /// Block type to tile mapping
    pub fn getTilesForBlock(self: *const TextureAtlas, block_id: u8) BlockTiles {
        return self.tile_mappings[block_id];
    }

    /// Detect tile size from the first valid texture in the pack
    fn detectTileSize(pack_manager: ?*resource_pack.ResourcePackManager, allocator: std.mem.Allocator, max_resolution: u32) u32 {
        if (pack_manager) |pm| {
            // Try to load any configured texture from the ACTIVE pack only
            // This ensures we detect the resolution of the custom pack, even if it's incomplete
            if (pm.getActivePackPath()) |pack_path| {
                const uses_pbr = pm.hasPBRSupport();

                for (block_registry.BLOCK_REGISTRY) |config| {
                    if (std.mem.eql(u8, config.name, "unknown")) continue;

                    const tex_names = [_][]const u8{ config.texture_top, config.texture_bottom, config.texture_side };
                    for (tex_names) |name| {
                        var loaded_tex: ?resource_pack.LoadedTexture = null;

                        if (uses_pbr) {
                            loaded_tex = pm.loadPBRTexture(pack_path, name, .diffuse);
                        }

                        if (loaded_tex == null) {
                            loaded_tex = pm.loadFlatTexture(pack_path, name);
                        }

                        if (loaded_tex) |tex| {
                            defer {
                                var t = tex;
                                t.deinit(allocator);
                            }
                            // Use the larger dimension and snap to nearest supported size
                            const size = @max(tex.width, tex.height);
                            return @min(snapToSupportedSize(size), max_resolution);
                        }
                    }
                }
            }
        }
        return DEFAULT_TILE_SIZE;
    }

    /// Snap a size to the nearest supported tile size
    fn snapToSupportedSize(size: u32) u32 {
        for (SUPPORTED_TILE_SIZES) |supported| {
            if (size <= supported) {
                return supported;
            }
        }
        // Cap at maximum supported size
        return SUPPORTED_TILE_SIZES[SUPPORTED_TILE_SIZES.len - 1];
    }

    pub fn init(allocator: std.mem.Allocator, rhi_instance: rhi.RHI, pack_manager: ?*resource_pack.ResourcePackManager, max_resolution: u32) !TextureAtlas {
        // Detect tile size from pack textures
        const tile_size = detectTileSize(pack_manager, allocator, max_resolution);
        const atlas_size = tile_size * TILES_PER_ROW;

        log.log.info("Texture atlas tile size: {}x{} (atlas: {}x{})", .{ tile_size, tile_size, atlas_size, atlas_size });

        const pixel_count = atlas_size * atlas_size * 4;

        // Allocate pixel buffers for all atlas types
        const diffuse_pixels = try allocator.alloc(u8, pixel_count);
        defer allocator.free(diffuse_pixels);
        @memset(diffuse_pixels, 255); // White default

        // Check if pack has PBR support
        const has_pbr = if (pack_manager) |pm| pm.hasPBRSupport() else false;

        var normal_pixels: ?[]u8 = null;
        var roughness_pixels: ?[]u8 = null;

        if (has_pbr) {
            normal_pixels = try allocator.alloc(u8, pixel_count);
            // Default normal: (128, 128, 255, 0) - Alpha 0 means no PBR
            var i: usize = 0;
            while (i < pixel_count) : (i += 4) {
                normal_pixels.?[i + 0] = 128;
                normal_pixels.?[i + 1] = 128;
                normal_pixels.?[i + 2] = 255;
                normal_pixels.?[i + 3] = 0; // PBR Flag: 0 = Off
            }

            roughness_pixels = try allocator.alloc(u8, pixel_count);
            // Default roughness: 1.0 (Rough), displacement: 0.0
            // Packed: R=Roughness, G=Displacement, B=0, A=255
            i = 0;
            while (i < pixel_count) : (i += 4) {
                roughness_pixels.?[i + 0] = 255; // Roughness (Max)
                roughness_pixels.?[i + 1] = 0; // Displacement
                roughness_pixels.?[i + 2] = 0;
                roughness_pixels.?[i + 3] = 255;
            }
        }
        defer if (normal_pixels) |p| allocator.free(p);
        defer if (roughness_pixels) |p| allocator.free(p);

        var loaded_count: u32 = 0;
        var pbr_count: u32 = 0;

        // Track unique textures and their assigned indices
        var texture_indices = std.StringHashMap(u16).init(allocator);
        defer texture_indices.deinit();

        var next_tile_index: u16 = 1; // 0 is reserved for fallback/unknown
        var tile_mappings = [_]BlockTiles{BlockTiles.uniform(0)} ** 256;

        for (&block_registry.BLOCK_REGISTRY) |*def| {
            if (std.mem.eql(u8, def.name, "unknown")) continue;
            if (def.id == .air) continue;

            const block_idx = @intFromEnum(def.id);
            const tex_names = [_][]const u8{ def.texture_top, def.texture_bottom, def.texture_side };
            var indices = [_]u16{0} ** 3;

            for (tex_names, 0..) |name, i| {
                if (texture_indices.get(name)) |idx| {
                    indices[i] = idx;
                    continue;
                }

                if (next_tile_index >= TILES_PER_ROW * TILES_PER_ROW) {
                    log.log.err("Texture atlas capacity exceeded (max {})", .{TILES_PER_ROW * TILES_PER_ROW});
                    indices[i] = 0;
                    continue;
                }

                const current_idx = next_tile_index;
                next_tile_index += 1;
                try texture_indices.put(name, current_idx);
                indices[i] = current_idx;

                // Load the texture
                var loaded = false;
                if (pack_manager) |pm| {
                    if (has_pbr) {
                        // Load full PBR texture set
                        var pbr_set = pm.loadPBRTextureSet(name);
                        defer pbr_set.deinit(allocator);

                        if (pbr_set.diffuse) |diffuse| {
                            copyTextureToTile(diffuse_pixels, @intCast(current_idx), diffuse.pixels, diffuse.width, diffuse.height, tile_size, atlas_size);
                            loaded = true;
                            loaded_count += 1;
                        }

                        if (pbr_set.normal) |normal| {
                            copyTextureToTile(normal_pixels.?, @intCast(current_idx), normal.pixels, normal.width, normal.height, tile_size, atlas_size);
                            // Ensure alpha is set to 255 to flag PBR support for this tile
                            setTileAlpha(normal_pixels.?, @intCast(current_idx), 255, tile_size, atlas_size);
                            pbr_count += 1;
                        }

                        // Pack Roughness into RED and Displacement into GREEN channel of the same atlas
                        if (pbr_set.roughness) |roughness| {
                            copyTextureChannelToTile(roughness_pixels.?, @intCast(current_idx), roughness.pixels, roughness.width, roughness.height, 0, 0, tile_size, atlas_size);
                        }
                        if (pbr_set.displacement) |displacement| {
                            copyTextureChannelToTile(roughness_pixels.?, @intCast(current_idx), displacement.pixels, displacement.width, displacement.height, 0, 1, tile_size, atlas_size);
                        }
                    } else {
                        // Legacy: load just diffuse
                        if (pm.loadTexture(name)) |loaded_tex| {
                            defer {
                                var tex = loaded_tex;
                                tex.deinit(allocator);
                            }
                            copyTextureToTile(diffuse_pixels, @intCast(current_idx), loaded_tex.pixels, loaded_tex.width, loaded_tex.height, tile_size, atlas_size);
                            loaded = true;
                            loaded_count += 1;
                        }
                    }
                }

                if (!loaded) {
                    log.log.warn("Failed to load texture: {s}, using fallback color", .{name});
                    // Use solid block color as fallback in the atlas
                    const base_f32 = def.default_color;
                    const base_u8 = [3]u8{
                        @intFromFloat(@min(base_f32[0] * 255.0, 255.0)),
                        @intFromFloat(@min(base_f32[1] * 255.0, 255.0)),
                        @intFromFloat(@min(base_f32[2] * 255.0, 255.0)),
                    };
                    fillTileWithColor(diffuse_pixels, @intCast(current_idx), base_u8, tile_size, atlas_size);
                }
            }

            tile_mappings[block_idx] = .{
                .top = indices[0],
                .bottom = indices[1],
                .side = indices[2],
            };
        }

        // Create textures using RHI with NEAREST filtering for sharp pixel art, but with mipmaps for performance
        // Use SRGB format for diffuse/albedo - GPU will automatically convert to linear during sampling
        const diffuse_texture = try Texture.init(rhi_instance, atlas_size, atlas_size, .rgba_srgb, .{
            .min_filter = .nearest_mipmap_linear,
            .mag_filter = .nearest,
            .generate_mipmaps = true,
        }, diffuse_pixels);

        var normal_texture: ?Texture = null;
        var roughness_texture: ?Texture = null;

        if (has_pbr) {
            // Normal maps must stay as linear (UNORM) - they contain direction data, not colors
            if (normal_pixels) |np| {
                normal_texture = Texture.init(rhi_instance, atlas_size, atlas_size, .rgba, .{
                    .min_filter = .linear_mipmap_linear,
                    .mag_filter = .linear,
                    .generate_mipmaps = true,
                }, np) catch |err| blk: {
                    log.log.warn("Failed to create normal map atlas: {}", .{err});
                    break :blk null;
                };
            }

            // Roughness/displacement are linear data, not colors - use UNORM
            if (roughness_pixels) |rp| {
                roughness_texture = Texture.init(rhi_instance, atlas_size, atlas_size, .rgba, .{
                    .min_filter = .linear_mipmap_linear,
                    .mag_filter = .linear,
                    .generate_mipmaps = true,
                }, rp) catch |err| blk: {
                    log.log.warn("Failed to create roughness map atlas: {}", .{err});
                    break :blk null;
                };
            }

            log.log.info("PBR atlases created: {} textures with {} normal maps", .{ loaded_count, pbr_count });
        }

        log.log.info("Texture atlas created: {}x{} - Loaded {} textures from pack", .{ atlas_size, atlas_size, loaded_count });

        return .{
            .texture = diffuse_texture,
            .normal_texture = normal_texture,
            .roughness_texture = roughness_texture,
            .displacement_texture = null,
            .allocator = allocator,
            .pack_manager = pack_manager,
            .tile_size = tile_size,
            .atlas_size = atlas_size,
            .has_pbr = has_pbr,
            .tile_mappings = tile_mappings,
        };
    }

    fn copyTextureChannelToTile(atlas_pixels: []u8, tile_index: u16, src_pixels: []const u8, src_width: u32, src_height: u32, src_channel: u8, dest_channel: u8, tile_size: u32, atlas_size: u32) void {
        const tile_col = tile_index % TILES_PER_ROW;
        const tile_row = tile_index / TILES_PER_ROW;
        const start_x = tile_col * tile_size;
        const start_y = tile_row * tile_size;

        var py: u32 = 0;
        while (py < tile_size) : (py += 1) {
            var px: u32 = 0;
            while (px < tile_size) : (px += 1) {
                const src_x = (px * src_width) / tile_size;
                const src_y = (py * src_height) / tile_size;
                const src_idx = (src_y * src_width + src_x) * 4;

                const dest_x = start_x + px;
                const dest_y = start_y + py;
                const dest_idx = (dest_y * atlas_size + dest_x) * 4;

                if (src_idx + src_channel < src_pixels.len and dest_idx + dest_channel < atlas_pixels.len) {
                    atlas_pixels[dest_idx + dest_channel] = src_pixels[src_idx + src_channel];
                }
            }
        }
    }

    fn copyTextureToTile(atlas_pixels: []u8, tile_index: u16, src_pixels: []const u8, src_width: u32, src_height: u32, tile_size: u32, atlas_size: u32) void {
        const tile_col = tile_index % TILES_PER_ROW;
        const tile_row = tile_index / TILES_PER_ROW;
        const start_x = tile_col * tile_size;
        const start_y = tile_row * tile_size;

        var py: u32 = 0;
        while (py < tile_size) : (py += 1) {
            var px: u32 = 0;
            while (px < tile_size) : (px += 1) {
                const src_x = (px * src_width) / tile_size;
                const src_y = (py * src_height) / tile_size;
                const src_idx = (src_y * src_width + src_x) * 4;

                const dest_x = start_x + px;
                const dest_y = start_y + py;
                const dest_idx = (dest_y * atlas_size + dest_x) * 4;

                if (src_idx + 3 < src_pixels.len and dest_idx + 3 < atlas_pixels.len) {
                    atlas_pixels[dest_idx + 0] = src_pixels[src_idx + 0];
                    atlas_pixels[dest_idx + 1] = src_pixels[src_idx + 1];
                    atlas_pixels[dest_idx + 2] = src_pixels[src_idx + 2];
                    atlas_pixels[dest_idx + 3] = src_pixels[src_idx + 3];
                }
            }
        }
    }

    fn fillTileWithColor(atlas_pixels: []u8, tile_index: u16, color: [3]u8, tile_size: u32, atlas_size: u32) void {
        const tile_col = tile_index % TILES_PER_ROW;
        const tile_row = tile_index / TILES_PER_ROW;
        const start_x = tile_col * tile_size;
        const start_y = tile_row * tile_size;

        var py: u32 = 0;
        while (py < tile_size) : (py += 1) {
            var px: u32 = 0;
            while (px < tile_size) : (px += 1) {
                const dest_x = start_x + px;
                const dest_y = start_y + py;
                const dest_idx = (dest_y * atlas_size + dest_x) * 4;

                if (dest_idx + 3 < atlas_pixels.len) {
                    atlas_pixels[dest_idx + 0] = color[0];
                    atlas_pixels[dest_idx + 1] = color[1];
                    atlas_pixels[dest_idx + 2] = color[2];
                    atlas_pixels[dest_idx + 3] = 255;
                }
            }
        }
    }

    fn setTileAlpha(atlas_pixels: []u8, tile_index: u16, alpha: u8, tile_size: u32, atlas_size: u32) void {
        const tile_col = tile_index % TILES_PER_ROW;
        const tile_row = tile_index / TILES_PER_ROW;
        const start_x = tile_col * tile_size;
        const start_y = tile_row * tile_size;

        var py: u32 = 0;
        while (py < tile_size) : (py += 1) {
            var px: u32 = 0;
            while (px < tile_size) : (px += 1) {
                const dest_x = start_x + px;
                const dest_y = start_y + py;
                const dest_idx = (dest_y * atlas_size + dest_x) * 4;

                if (dest_idx + 3 < atlas_pixels.len) {
                    atlas_pixels[dest_idx + 3] = alpha;
                }
            }
        }
    }

    pub fn deinit(self: *TextureAtlas) void {
        var tex = self.texture;
        tex.deinit();

        if (self.normal_texture) |*t| {
            var nt = t.*;
            nt.deinit();
        }
        if (self.roughness_texture) |*t| {
            var rt = t.*;
            rt.deinit();
        }
        if (self.displacement_texture) |*t| {
            var dt = t.*;
            dt.deinit();
        }
    }

    /// Bind diffuse texture
    pub fn bind(self: *const TextureAtlas, slot: u32) void {
        self.texture.bind(slot);
    }

    /// Bind normal map texture (if available)
    pub fn bindNormal(self: *const TextureAtlas, slot: u32) void {
        if (self.normal_texture) |*t| {
            t.bind(slot);
        }
    }

    /// Bind roughness texture (if available)
    pub fn bindRoughness(self: *const TextureAtlas, slot: u32) void {
        if (self.roughness_texture) |*t| {
            t.bind(slot);
        }
    }

    /// Bind displacement texture (if available)
    pub fn bindDisplacement(self: *const TextureAtlas, slot: u32) void {
        if (self.displacement_texture) |*t| {
            t.bind(slot);
        }
    }

    /// Check if PBR textures are available
    pub fn hasPBR(self: *const TextureAtlas) bool {
        return self.has_pbr;
    }
};

// Legacy constants for backward compatibility
pub const TILE_SIZE: u32 = DEFAULT_TILE_SIZE;
pub const ATLAS_SIZE: u32 = DEFAULT_TILE_SIZE * TILES_PER_ROW;
