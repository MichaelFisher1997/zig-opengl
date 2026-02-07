const rhi = @import("../graphics/rhi.zig");
const IUIContext = rhi.IUIContext;

pub const DebugLPVOverlay = struct {
    pub const Config = struct {
        width: f32 = 220.0,
        height: f32 = 220.0,
        spacing: f32 = 10.0,
    };

    pub fn rect(screen_height: f32, config: Config) rhi.Rect {
        return .{
            .x = config.spacing,
            .y = screen_height - config.height - config.spacing,
            .width = config.width,
            .height = config.height,
        };
    }

    pub fn draw(ui: IUIContext, lpv_texture: rhi.TextureHandle, screen_width: f32, screen_height: f32, config: Config) void {
        if (lpv_texture == 0) return;

        const r = rect(screen_height, config);

        ui.beginPass(screen_width, screen_height);
        defer ui.endPass();

        ui.drawTexture(lpv_texture, r);
    }
};
