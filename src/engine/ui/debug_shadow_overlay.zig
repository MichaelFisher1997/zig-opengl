const std = @import("std");
const rhi = @import("../graphics/rhi.zig");
const IUIContext = rhi.IUIContext;
const IShadowContext = rhi.IShadowContext;

pub const DebugShadowOverlay = struct {
    pub const Config = struct {
        size: f32 = 200.0,
        spacing: f32 = 10.0,
    };

    pub fn draw(ui: IUIContext, shadow: IShadowContext, screen_width: f32, screen_height: f32, config: Config) void {
        ui.beginPass(screen_width, screen_height);
        defer ui.endPass();

        for (0..rhi.SHADOW_CASCADE_COUNT) |i| {
            const handle = shadow.getShadowMapHandle(@intCast(i));
            if (handle == 0) continue;

            const x = config.spacing + @as(f32, @floatFromInt(i)) * (config.size + config.spacing);
            const y = config.spacing;

            ui.drawDepthTexture(handle, .{
                .x = x,
                .y = y,
                .width = config.size,
                .height = config.size,
            });
        }
    }
};
