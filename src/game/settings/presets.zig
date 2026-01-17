const std = @import("std");
const data = @import("data.zig");
const Settings = data.Settings;

pub const GraphicsPreset = enum {
    low,
    medium,
    high,
    ultra,
    custom,
};

pub const PresetConfig = struct {
    preset: GraphicsPreset,
    shadow_quality: u32,
    shadow_pcf_samples: u8,
    shadow_cascade_blend: bool,
    pbr_enabled: bool,
    pbr_quality: u8,
    msaa_samples: u8,
    anisotropic_filtering: u8,
    max_texture_resolution: u32,
    cloud_shadows_enabled: bool,
    exposure: f32,
    saturation: f32,
    volumetric_lighting_enabled: bool,
    volumetric_density: f32,
    volumetric_steps: u32,
    volumetric_scattering: f32,
    ssao_enabled: bool,
    render_distance: i32,
};

pub const GRAPHICS_PRESETS = [_]PresetConfig{
    // LOW: Prioritize performance
    .{ .preset = .low, .shadow_quality = 0, .shadow_pcf_samples = 4, .shadow_cascade_blend = false, .pbr_enabled = false, .pbr_quality = 0, .msaa_samples = 1, .anisotropic_filtering = 1, .max_texture_resolution = 64, .cloud_shadows_enabled = false, .exposure = 0.9, .saturation = 1.3, .volumetric_lighting_enabled = false, .volumetric_density = 0.0, .volumetric_steps = 4, .volumetric_scattering = 0.5, .ssao_enabled = false, .render_distance = 6 },

    // MEDIUM: Balanced
    .{ .preset = .medium, .shadow_quality = 1, .shadow_pcf_samples = 8, .shadow_cascade_blend = false, .pbr_enabled = true, .pbr_quality = 1, .msaa_samples = 2, .anisotropic_filtering = 4, .max_texture_resolution = 128, .cloud_shadows_enabled = true, .exposure = 0.9, .saturation = 1.3, .volumetric_lighting_enabled = true, .volumetric_density = 0.00005, .volumetric_steps = 8, .volumetric_scattering = 0.7, .ssao_enabled = true, .render_distance = 12 },

    // HIGH: Quality focus
    .{ .preset = .high, .shadow_quality = 2, .shadow_pcf_samples = 12, .shadow_cascade_blend = true, .pbr_enabled = true, .pbr_quality = 2, .msaa_samples = 4, .anisotropic_filtering = 8, .max_texture_resolution = 256, .cloud_shadows_enabled = true, .exposure = 0.9, .saturation = 1.3, .volumetric_lighting_enabled = true, .volumetric_density = 0.0001, .volumetric_steps = 12, .volumetric_scattering = 0.75, .ssao_enabled = true, .render_distance = 18 },

    // ULTRA: Maximum quality
    .{ .preset = .ultra, .shadow_quality = 3, .shadow_pcf_samples = 16, .shadow_cascade_blend = true, .pbr_enabled = true, .pbr_quality = 2, .msaa_samples = 4, .anisotropic_filtering = 16, .max_texture_resolution = 512, .cloud_shadows_enabled = true, .exposure = 0.9, .saturation = 1.3, .volumetric_lighting_enabled = true, .volumetric_density = 0.0002, .volumetric_steps = 16, .volumetric_scattering = 0.8, .ssao_enabled = true, .render_distance = 28 },
};

pub fn apply(settings: *Settings, preset_idx: usize) void {
    if (preset_idx >= GRAPHICS_PRESETS.len) return;
    const config = GRAPHICS_PRESETS[preset_idx];
    settings.shadow_quality = config.shadow_quality;
    settings.shadow_pcf_samples = config.shadow_pcf_samples;
    settings.shadow_cascade_blend = config.shadow_cascade_blend;
    settings.pbr_enabled = config.pbr_enabled;
    settings.pbr_quality = config.pbr_quality;
    settings.msaa_samples = config.msaa_samples;
    settings.anisotropic_filtering = config.anisotropic_filtering;
    settings.max_texture_resolution = config.max_texture_resolution;
    settings.cloud_shadows_enabled = config.cloud_shadows_enabled;
    settings.exposure = config.exposure;
    settings.saturation = config.saturation;
    settings.volumetric_lighting_enabled = config.volumetric_lighting_enabled;
    settings.volumetric_density = config.volumetric_density;
    settings.volumetric_steps = config.volumetric_steps;
    settings.volumetric_scattering = config.volumetric_scattering;
    settings.ssao_enabled = config.ssao_enabled;
    settings.render_distance = config.render_distance;
}

pub fn getIndex(settings: *const Settings) usize {
    for (GRAPHICS_PRESETS, 0..) |preset, i| {
        if (matches(settings, preset)) return i;
    }
    return GRAPHICS_PRESETS.len; // Custom
}

fn matches(settings: *const Settings, preset: PresetConfig) bool {
    return settings.shadow_quality == preset.shadow_quality and
        settings.shadow_pcf_samples == preset.shadow_pcf_samples and
        settings.shadow_cascade_blend == preset.shadow_cascade_blend and
        settings.pbr_enabled == preset.pbr_enabled and
        settings.pbr_quality == preset.pbr_quality and
        settings.msaa_samples == preset.msaa_samples and
        settings.anisotropic_filtering == preset.anisotropic_filtering and
        settings.max_texture_resolution == preset.max_texture_resolution and
        settings.cloud_shadows_enabled == preset.cloud_shadows_enabled and
        settings.exposure == preset.exposure and
        settings.saturation == preset.saturation and
        settings.render_distance == preset.render_distance and
        settings.volumetric_lighting_enabled == preset.volumetric_lighting_enabled and
        settings.volumetric_density == preset.volumetric_density and
        settings.volumetric_steps == preset.volumetric_steps and
        settings.volumetric_scattering == preset.volumetric_scattering and
        settings.ssao_enabled == preset.ssao_enabled;
}
