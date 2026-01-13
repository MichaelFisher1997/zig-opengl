const std = @import("std");
const rhi = @import("rhi.zig");
const RHI = rhi.RHI;
const TextureAtlas = @import("texture_atlas.zig").TextureAtlas;

pub const MaterialSystem = struct {
    allocator: std.mem.Allocator,
    rhi: RHI,
    atlas: *TextureAtlas,

    pub fn init(allocator: std.mem.Allocator, rhi_instance: RHI, atlas: *TextureAtlas) !*MaterialSystem {
        const self = try allocator.create(MaterialSystem);
        self.* = .{
            .allocator = allocator,
            .rhi = rhi_instance,
            .atlas = atlas,
        };
        return self;
    }

    pub fn deinit(self: *MaterialSystem) void {
        self.allocator.destroy(self);
    }

    /// Binds the standard terrain material (diffuse, normal, roughness, etc.)
    pub fn bindTerrainMaterial(self: *MaterialSystem, env_map_handle: rhi.TextureHandle) void {
        self.rhi.bindTexture(self.atlas.texture.handle, 1);
        if (self.atlas.normal_texture) |t| self.rhi.bindTexture(t.handle, 6);
        if (self.atlas.roughness_texture) |t| self.rhi.bindTexture(t.handle, 7);
        if (self.atlas.displacement_texture) |t| self.rhi.bindTexture(t.handle, 8);
        if (env_map_handle != 0) self.rhi.bindTexture(env_map_handle, 9);
    }

    /// Gets the handles for the current texture atlas
    pub fn getAtlasHandles(self: *MaterialSystem, env_map_handle: rhi.TextureHandle) rhi.TextureAtlasHandles {
        return .{
            .diffuse = self.atlas.texture.handle,
            .normal = if (self.atlas.normal_texture) |t| t.handle else 0,
            .roughness = if (self.atlas.roughness_texture) |t| t.handle else 0,
            .displacement = if (self.atlas.displacement_texture) |t| t.handle else 0,
            .env = env_map_handle,
        };
    }
};
