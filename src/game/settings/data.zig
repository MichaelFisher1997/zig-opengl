const std = @import("std");

pub const ShadowQuality = struct {
    resolution: u32,
    label: []const u8,
};

pub const SHADOW_QUALITIES = [_]ShadowQuality{
    .{ .resolution = 1024, .label = "LOW" },
    .{ .resolution = 2048, .label = "MEDIUM" },
    .{ .resolution = 4096, .label = "HIGH" },
    .{ .resolution = 8192, .label = "ULTRA" },
};

pub const Resolution = struct {
    width: u32,
    height: u32,
    label: []const u8,
};

pub const RESOLUTIONS = [_]Resolution{
    .{ .width = 1280, .height = 720, .label = "1280X720" },
    .{ .width = 1600, .height = 900, .label = "1600X900" },
    .{ .width = 1920, .height = 1080, .label = "1920X1080" },
    .{ .width = 2560, .height = 1080, .label = "2560X1080" },
    .{ .width = 2560, .height = 1440, .label = "2560X1440" },
    .{ .width = 3440, .height = 1440, .label = "3440X1440" },
    .{ .width = 3840, .height = 2160, .label = "3840X2160" },
};

pub const Settings = struct {
    render_distance: i32 = 15,
    mouse_sensitivity: f32 = 50.0,
    vsync: bool = true,
    fov: f32 = 45.0,
    textures_enabled: bool = true,
    wireframe_enabled: bool = false,
    shadow_quality: u32 = 2, // 0=Low, 1=Medium, 2=High, 3=Ultra
    shadow_distance: f32 = 250.0,
    anisotropic_filtering: u8 = 16,
    msaa_samples: u8 = 4,
    ui_scale: f32 = 1.0, // Manual UI scale multiplier (0.5 to 2.0)
    window_width: u32 = 1920,
    window_height: u32 = 1080,
    lod_enabled: bool = false, // Disabled by default due to performance issues
    texture_pack: []const u8 = "default",
    environment_map: []const u8 = "default", // "default" or filename.exr/hdr

    // PBR Settings
    pbr_enabled: bool = true,
    pbr_quality: u8 = 2, // 0=Off, 1=Low (no normal maps), 2=Full
    exposure: f32 = 0.9,
    saturation: f32 = 1.3,

    // Shadow Settings
    shadow_pcf_samples: u8 = 12, // 4, 8, 12, 16
    shadow_cascade_blend: bool = true,

    // Cloud Settings
    cloud_shadows_enabled: bool = true,

    // Volumetric Lighting Settings (Phase 4)
    volumetric_lighting_enabled: bool = true,
    volumetric_density: f32 = 0.05, // Fog density
    volumetric_steps: u32 = 16, // Raymarching steps
    volumetric_scattering: f32 = 0.8, // Mie scattering anisotropy (G)
    ssao_enabled: bool = true,

    // Texture Settings
    max_texture_resolution: u32 = 512, // 16, 32, 64, 128, 256, 512

    // Helper methods that are purely data access
    pub fn getShadowResolution(self: *const Settings) u32 {
        if (self.shadow_quality < SHADOW_QUALITIES.len) {
            return SHADOW_QUALITIES[self.shadow_quality].resolution;
        }
        return SHADOW_QUALITIES[2].resolution; // Default to High
    }

    pub fn getResolutionIndex(self: *const Settings) usize {
        for (RESOLUTIONS, 0..) |res, i| {
            if (res.width == self.window_width and res.height == self.window_height) {
                return i;
            }
        }
        return 2; // Default to 1920x1080
    }

    pub fn setResolutionByIndex(self: *Settings, idx: usize) void {
        if (idx < RESOLUTIONS.len) {
            self.window_width = RESOLUTIONS[idx].width;
            self.window_height = RESOLUTIONS[idx].height;
        }
    }
};
