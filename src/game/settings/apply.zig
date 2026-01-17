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

    // Note:
    // - Shadow resolution, PBR quality, and cloud shadows are primarily used during pipeline configuration
    //   or uniform updates in RenderGraph/Systems, not through direct RHI setters.
    // - Render distance is handled by Camera/World.
    // - FOV/Sensitivity are handled by Input/Camera.
    // - Window size is handled by WindowManager.

    // Future expansion: If RHI exposes more setters (e.g. setShadowResolution), add them here.
}
