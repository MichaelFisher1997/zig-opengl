const Settings = @import("data.zig").Settings;
const RHI = @import("../../engine/graphics/rhi.zig").RHI;

/// Applies all relevant settings to the Render Hardware Interface.
/// This ensures the RHI state matches the Settings data.
pub fn applyToRHI(settings: *const Settings, rhi: *RHI) void {
    rhi.setVSync(settings.vsync);
    rhi.setWireframe(settings.wireframe_enabled);
    rhi.setTexturesEnabled(settings.textures_enabled);
    rhi.setAnisotropicFiltering(settings.anisotropic_filtering);
    rhi.setMSAA(settings.msaa_samples);
    // Note: Shadow resolution, PBR quality, etc might be handled during pipeline creation
    // or uniform updates rather than direct RHI setters, checking available methods.

    // Some settings (resolution, render distance) are handled by WindowManager or RenderGraph/Camera.
}
