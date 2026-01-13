const std = @import("std");
const rhi = @import("rhi.zig");
const RHI = rhi.RHI;
const Vec3 = @import("../math/vec3.zig").Vec3;
const Mat4 = @import("../math/mat4.zig").Mat4;

pub const AtmosphereSystem = struct {
    allocator: std.mem.Allocator,
    rhi: RHI,

    cloud_vbo: rhi.BufferHandle = 0,
    cloud_ebo: rhi.BufferHandle = 0,
    cloud_mesh_size: f32 = 10000.0,

    pub fn init(allocator: std.mem.Allocator, rhi_instance: RHI) !*AtmosphereSystem {
        const self = try allocator.create(AtmosphereSystem);
        self.* = .{
            .allocator = allocator,
            .rhi = rhi_instance,
        };

        // Create cloud mesh (large quad centered on camera)
        const cloud_vertices = [_]f32{
            -self.cloud_mesh_size, -self.cloud_mesh_size,
            self.cloud_mesh_size,  -self.cloud_mesh_size,
            self.cloud_mesh_size,  self.cloud_mesh_size,
            -self.cloud_mesh_size, self.cloud_mesh_size,
        };
        const cloud_indices = [_]u16{ 0, 1, 2, 0, 2, 3 };

        self.cloud_vbo = rhi_instance.createBuffer(@sizeOf(@TypeOf(cloud_vertices)), .vertex);
        self.cloud_ebo = rhi_instance.createBuffer(@sizeOf(@TypeOf(cloud_indices)), .index);

        rhi_instance.uploadBuffer(self.cloud_vbo, std.mem.asBytes(&cloud_vertices));
        rhi_instance.uploadBuffer(self.cloud_ebo, std.mem.asBytes(&cloud_indices));

        return self;
    }

    pub fn deinit(self: *AtmosphereSystem) void {
        if (self.cloud_vbo != 0) self.rhi.destroyBuffer(self.cloud_vbo);
        if (self.cloud_ebo != 0) self.rhi.destroyBuffer(self.cloud_ebo);
        self.allocator.destroy(self);
    }

    pub fn renderSky(self: *AtmosphereSystem, params: rhi.SkyParams) void {
        // This still uses rhi.drawSky for now until we move the pipeline out of RHI
        self.rhi.drawSky(params);
    }

    pub fn renderClouds(self: *AtmosphereSystem, params: rhi.CloudParams, view_proj: Mat4) void {
        // We will move the logic from rhi_vulkan.zig to use rhi primitives here
        // But for Phase 4 to work without a massive RHI rewrite,
        // we'll first just delegate and then gradually move primitives.

        var final_params = params;
        final_params.view_proj = view_proj;
        final_params.cam_pos = params.cam_pos;

        // Instead of calling rhi.drawClouds(params) which uses internal RHI VBO,
        // we want to use self.cloud_vbo.

        // To do this properly, RHI needs a way to draw with a specific VBO/EBO.
        // We have rhi.draw(handle, count, mode).

        // Let's see if we can use that.
        // But clouds need a specific shader.

        self.rhi.drawClouds(final_params);
    }
};
