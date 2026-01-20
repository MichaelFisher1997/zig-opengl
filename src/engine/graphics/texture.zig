const std = @import("std");
const rhi = @import("rhi.zig");

pub const TextureFormat = rhi.TextureFormat;
pub const FilterMode = rhi.FilterMode;
pub const WrapMode = rhi.WrapMode;
pub const Config = rhi.TextureConfig;

pub const Texture = struct {
    handle: rhi.TextureHandle,
    width: u32,
    height: u32,
    rhi_instance: rhi.RHI,

    pub fn init(instance: rhi.RHI, width: u32, height: u32, format: TextureFormat, config: Config, data: ?[]const u8) Texture {
        const handle = instance.createTexture(width, height, format, config, data);
        return .{
            .handle = handle,
            .width = width,
            .height = height,
            .rhi_instance = instance,
        };
    }

    pub fn initEmpty(instance: rhi.RHI, width: u32, height: u32, format: TextureFormat, config: Config) Texture {
        return init(instance, width, height, format, config, null);
    }

    pub fn initFloat(instance: rhi.RHI, width: u32, height: u32, data: []const f32) Texture {
        const bytes = std.mem.sliceAsBytes(data);
        const handle = instance.createTexture(width, height, .rgba32f, .{
            .min_filter = .linear_mipmap_linear,
            .mag_filter = .linear,
            .wrap_s = .clamp_to_edge,
            .wrap_t = .clamp_to_edge,
            .generate_mipmaps = true,
        }, bytes);
        return .{
            .handle = handle,
            .width = width,
            .height = height,
            .rhi_instance = instance,
        };
    }

    pub fn initSolidColor(instance: rhi.RHI, r: u8, g: u8, b: u8, a: u8) Texture {
        const data = [_]u8{ r, g, b, a };
        return init(instance, 1, 1, .rgba, .{}, &data);
    }

    pub fn deinit(self: *Texture) void {
        self.rhi_instance.destroyTexture(self.handle);
    }

    pub fn bind(self: *const Texture, slot: u32) void {
        self.rhi_instance.bindTexture(self.handle, slot);
    }

    pub fn update(self: *const Texture, data: []const u8) rhi.RhiError!void {
        try self.rhi_instance.updateTexture(self.handle, data);
    }
};
