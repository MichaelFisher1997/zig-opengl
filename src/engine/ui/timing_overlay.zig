const std = @import("std");
const UISystem = @import("ui_system.zig").UISystem;
const Color = @import("ui_system.zig").Color;
const Rect = @import("ui_system.zig").Rect;
const rhi = @import("../graphics/rhi.zig");
const font = @import("font.zig");

pub const TimingOverlay = struct {
    enabled: bool = false,

    pub fn draw(self: *TimingOverlay, ui: *UISystem, results: rhi.GpuTimingResults) void {
        if (!self.enabled) return;

        const x: f32 = 10;
        var y: f32 = 10;
        const width: f32 = 280;
        const line_height: f32 = 15;
        const scale: f32 = 1.0;
        const num_lines = 14; // Title + 12 passes + Total
        const padding = 20; // Spacers and margins

        // Background
        ui.drawRect(.{ .x = x, .y = y, .width = width, .height = num_lines * line_height + padding }, .{ .r = 0, .g = 0, .b = 0, .a = 0.6 });
        y += 5;

        drawTimingLine(ui, "GPU PROFILER (MS)", -1.0, x + 10, &y, scale, Color.white);
        y += 5;

        drawTimingLine(ui, "SHADOW 0:", results.shadow_pass_ms[0], x + 10, &y, scale, Color.gray);
        drawTimingLine(ui, "SHADOW 1:", results.shadow_pass_ms[1], x + 10, &y, scale, Color.gray);
        drawTimingLine(ui, "SHADOW 2:", results.shadow_pass_ms[2], x + 10, &y, scale, Color.gray);
        drawTimingLine(ui, "G-PASS:", results.g_pass_ms, x + 10, &y, scale, Color.gray);
        drawTimingLine(ui, "SSAO:", results.ssao_pass_ms, x + 10, &y, scale, Color.gray);
        drawTimingLine(ui, "LPV:", results.lpv_pass_ms, x + 10, &y, scale, Color.gray);
        drawTimingLine(ui, "SKY:", results.sky_pass_ms, x + 10, &y, scale, Color.gray);
        drawTimingLine(ui, "OPAQUE:", results.opaque_pass_ms, x + 10, &y, scale, Color.gray);
        drawTimingLine(ui, "CLOUDS:", results.cloud_pass_ms, x + 10, &y, scale, Color.gray);
        drawTimingLine(ui, "BLOOM:", results.bloom_pass_ms, x + 10, &y, scale, Color.gray);
        drawTimingLine(ui, "FXAA:", results.fxaa_pass_ms, x + 10, &y, scale, Color.gray);
        drawTimingLine(ui, "POST PROC:", results.post_process_pass_ms, x + 10, &y, scale, Color.gray);

        y += 5;
        drawTimingLine(ui, "TOTAL GPU:", results.total_gpu_ms, x + 10, &y, scale, Color.white);
    }

    fn drawTimingLine(ui: *UISystem, label: []const u8, value: f32, x: f32, y: *f32, scale: f32, color: Color) void {
        font.drawText(ui, label, x, y.*, scale, color);

        if (value >= 0.0) {
            var buffer: [16]u8 = undefined;
            const val_str = std.fmt.bufPrint(&buffer, "{d:.2}", .{value}) catch "0.00";
            const val_x = x + 180;
            font.drawText(ui, val_str, val_x, y.*, scale, color);
        }

        y.* += 15;
    }

    pub fn toggle(self: *TimingOverlay) void {
        self.enabled = !self.enabled;
    }
};
