const Settings = @import("data.zig").Settings;
const RHI = @import("../../engine/graphics/rhi.zig").RHI;

/// Applies all relevant settings to the Render Hardware Interface (RHI).
/// This ensures the RHI state matches the Settings data for values it directly controls.
pub fn applyToRHI(settings: *const Settings, rhi: *RHI) void {
    // These settings map directly to RHI state setters
    rhi.setVSync(settings.vsync);
    rhi.setWireframe(settings.wireframe_enabled);
    rhi.setTexturesEnabled(settings.textures_enabled);
    rhi.setAnisotropicFiltering(settings.anisotropic_filtering);
    rhi.setMSAA(settings.msaa_samples);

    // NOTE: The following settings are NOT applied here because RHI does not expose setters for them.
    // Instead, they are consumed by other systems frame-by-frame or during resource creation:
    //
    // - Shadow Resolution: Used in RenderGraph setup / ShadowPass init.
    // - PBR Enabled/Quality: Passed via updateGlobalUniforms() in App.runSingleFrame().
    // - Cloud Shadows: Passed via CloudParams in updateGlobalUniforms().
    // - Volumetric Lighting: Consumed by AtmosphereSystem/VolumetricPass.
    // - SSAO: Consumed by SSAOPass.
    // - Render Distance: Handled by World/ChunkManager.
    // - FOV/Sensitivity: Handled by Camera/Input.
    // - Window Size: Handled by WindowManager.

    // Calling this function ensures that any RHI-managed state is consistent with the Settings struct.
}
