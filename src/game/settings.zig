pub const data = @import("settings/data.zig");
pub const presets = @import("settings/presets.zig");
pub const persistence = @import("settings/persistence.zig");
pub const ui_helpers = @import("settings/ui_helpers.zig");
pub const apply_logic = @import("settings/apply.zig");

// Re-export core types for convenience
pub const Settings = data.Settings;
pub const ShadowQuality = data.ShadowQuality;
pub const SHADOW_QUALITIES = data.SHADOW_QUALITIES;
pub const Resolution = data.Resolution;
pub const RESOLUTIONS = data.RESOLUTIONS;
pub const GraphicsPreset = presets.GraphicsPreset;
pub const GRAPHICS_PRESETS = presets.GRAPHICS_PRESETS;
pub const PresetConfig = presets.PresetConfig;
