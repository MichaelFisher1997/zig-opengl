const std = @import("std");
const rhi = @import("rhi.zig");

pub const TextureFormat = enum {
    rgb,
    rgba,
    red,
    depth,
};

pub const FilterMode = enum {
    nearest,
    linear,
    nearest_mipmap_nearest,
    linear_mipmap_nearest,
    nearest_mipmap_linear,
    linear_mipmap_linear,
};

pub const WrapMode = enum {
    repeat,
    mirrored_repeat,
    clamp_to_edge,
    clamp_to_border,
};

pub const Texture = struct {
    handle: rhi.TextureHandle,
    width: u32,
    height: u32,
    rhi_instance: rhi.RHI,

    pub const Config = struct {
        min_filter: FilterMode = .linear_mipmap_linear,
        mag_filter: FilterMode = .linear,
        wrap_s: WrapMode = .repeat,
        wrap_t: WrapMode = .repeat,
        generate_mipmaps: bool = true,
    };

    pub fn init(instance: rhi.RHI, width: u32, height: u32, data: []const u8) Texture {
        const handle = instance.createTexture(width, height, data);
        return .{
            .handle = handle,
            .width = width,
            .height = height,
            .rhi_instance = instance,
        };
    }

    pub fn initEmpty(instance: rhi.RHI, width: u32, height: u32, format: TextureFormat, config: Config) Texture {
        _ = format;
        _ = config;
        const allocator = instance.getAllocator();
        const data = allocator.alloc(u8, width * height * 4) catch unreachable;
        defer allocator.free(data);
        @memset(data, 0);
        return init(instance, width, height, data);
    }

    pub fn initSolidColor(instance: rhi.RHI, r: u8, g: u8, b: u8, a: u8) Texture {
        const data = [_]u8{ r, g, b, a };
        return init(instance, 1, 1, &data);
    }

    pub fn deinit(self: *Texture) void {
        self.rhi_instance.destroyTexture(self.handle);
    }

    pub fn bind(self: *const Texture, slot: u32) void {
        self.rhi_instance.bindTexture(self.handle, slot);
    }

    pub fn update(self: *const Texture, data: []const u8) void {
        self.rhi_instance.updateTexture(self.handle, data);
    }
};
