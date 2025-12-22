const std = @import("std");
const c = @import("../../c.zig").c;
const rhi = @import("rhi.zig");
const Mat4 = @import("../math/mat4.zig").Mat4;
const Vec3 = @import("../math/vec3.zig").Vec3;
const Shader = @import("shader.zig").Shader;

const BufferResource = struct {
    vao: c.GLuint,
    vbo: c.GLuint,
};

const OpenGLContext = struct {
    allocator: std.mem.Allocator,
    buffers: std.ArrayListUnmanaged(BufferResource),
    free_indices: std.ArrayListUnmanaged(usize),
    mutex: std.Thread.Mutex,

    // UI rendering state
    ui_shader: ?Shader,
    ui_tex_shader: ?Shader,
    ui_vao: c.GLuint,
    ui_vbo: c.GLuint,
    ui_screen_width: f32,
    ui_screen_height: f32,
};

// UI Shaders (embedded GLSL)
const ui_vertex_shader =
    \\#version 330 core
    \\layout (location = 0) in vec2 aPos;
    \\layout (location = 1) in vec4 aColor;
    \\out vec4 vColor;
    \\uniform mat4 projection;
    \\void main() {
    \\    gl_Position = projection * vec4(aPos, 0.0, 1.0);
    \\    vColor = aColor;
    \\}
;

const ui_fragment_shader =
    \\#version 330 core
    \\in vec4 vColor;
    \\out vec4 FragColor;
    \\void main() {
    \\    FragColor = vColor;
    \\}
;

const ui_tex_vertex_shader =
    \\#version 330 core
    \\layout (location = 0) in vec2 aPos;
    \\layout (location = 1) in vec2 aTexCoord;
    \\out vec2 vTexCoord;
    \\uniform mat4 projection;
    \\void main() {
    \\    gl_Position = projection * vec4(aPos, 0.0, 1.0);
    \\    vTexCoord = aTexCoord;
    \\}
;

const ui_tex_fragment_shader =
    \\#version 330 core
    \\in vec2 vTexCoord;
    \\out vec4 FragColor;
    \\uniform sampler2D uTexture;
    \\void main() {
    \\    FragColor = texture(uTexture, vTexCoord);
    \\}
;

fn init(ctx_ptr: *anyopaque, allocator: std.mem.Allocator) anyerror!void {
    const ctx: *OpenGLContext = @ptrCast(@alignCast(ctx_ptr));
    ctx.allocator = allocator;
    ctx.buffers = .empty;
    ctx.free_indices = .empty;
    ctx.mutex = .{};

    // Initialize UI shaders
    std.log.info("Creating OpenGL UI shaders...", .{});
    ctx.ui_shader = try Shader.initSimple(ui_vertex_shader, ui_fragment_shader);
    ctx.ui_tex_shader = try Shader.initSimple(ui_tex_vertex_shader, ui_tex_fragment_shader);
    std.log.info("OpenGL UI shaders created", .{});

    // Create UI VAO/VBO
    c.glGenVertexArrays().?(1, &ctx.ui_vao);
    c.glGenBuffers().?(1, &ctx.ui_vbo);
    c.glBindVertexArray().?(ctx.ui_vao);
    c.glBindBuffer().?(c.GL_ARRAY_BUFFER, ctx.ui_vbo);

    // Position (2 floats) + Color (4 floats) = 6 floats per vertex
    const stride: c.GLsizei = 6 * @sizeOf(f32);
    c.glVertexAttribPointer().?(0, 2, c.GL_FLOAT, c.GL_FALSE, stride, null);
    c.glEnableVertexAttribArray().?(0);
    c.glVertexAttribPointer().?(1, 4, c.GL_FLOAT, c.GL_FALSE, stride, @ptrFromInt(2 * @sizeOf(f32)));
    c.glEnableVertexAttribArray().?(1);

    c.glBindVertexArray().?(0);
    ctx.ui_screen_width = 1280;
    ctx.ui_screen_height = 720;
}

fn deinit(ctx_ptr: *anyopaque) void {
    const ctx: *OpenGLContext = @ptrCast(@alignCast(ctx_ptr));
    {
        ctx.mutex.lock();
        defer ctx.mutex.unlock();

        for (ctx.buffers.items) |buf| {
            if (buf.vao != 0) c.glDeleteVertexArrays().?(1, &buf.vao);
            if (buf.vbo != 0) c.glDeleteBuffers().?(1, &buf.vbo);
        }
        ctx.buffers.deinit(ctx.allocator);
        ctx.free_indices.deinit(ctx.allocator);
    }

    // Cleanup UI resources
    if (ctx.ui_shader) |*s| s.deinit();
    if (ctx.ui_tex_shader) |*s| s.deinit();
    if (ctx.ui_vao != 0) c.glDeleteVertexArrays().?(1, &ctx.ui_vao);
    if (ctx.ui_vbo != 0) c.glDeleteBuffers().?(1, &ctx.ui_vbo);

    ctx.allocator.destroy(ctx);
}

fn createBuffer(ctx_ptr: *anyopaque, size: usize, usage: rhi.BufferUsage) rhi.BufferHandle {
    const ctx: *OpenGLContext = @ptrCast(@alignCast(ctx_ptr));
    ctx.mutex.lock();
    defer ctx.mutex.unlock();

    // We only support vertex buffers for this refactor as per requirements
    if (usage != .vertex) {
        // Fallback or error
    }

    var vao: c.GLuint = 0;
    var vbo: c.GLuint = 0;

    c.glGenVertexArrays().?(1, &vao);
    c.glGenBuffers().?(1, &vbo);
    c.glBindVertexArray().?(vao);
    c.glBindBuffer().?(c.GL_ARRAY_BUFFER, vbo);

    // Allocate mutable storage with NULL data
    c.glBufferData().?(c.GL_ARRAY_BUFFER, @intCast(size), null, c.GL_DYNAMIC_DRAW);

    // Stride is 14 floats (matches Vertex struct)
    const stride: c.GLsizei = 14 * @sizeOf(f32);

    // Position (3)
    c.glVertexAttribPointer().?(0, 3, c.GL_FLOAT, c.GL_FALSE, stride, null);
    c.glEnableVertexAttribArray().?(0);

    // Color (3)
    c.glVertexAttribPointer().?(1, 3, c.GL_FLOAT, c.GL_FALSE, stride, @ptrFromInt(3 * @sizeOf(f32)));
    c.glEnableVertexAttribArray().?(1);

    // Normal (3)
    c.glVertexAttribPointer().?(2, 3, c.GL_FLOAT, c.GL_FALSE, stride, @ptrFromInt(6 * @sizeOf(f32)));
    c.glEnableVertexAttribArray().?(2);

    // UV (2)
    c.glVertexAttribPointer().?(3, 2, c.GL_FLOAT, c.GL_FALSE, stride, @ptrFromInt(9 * @sizeOf(f32)));
    c.glEnableVertexAttribArray().?(3);

    // Tile ID (1)
    c.glVertexAttribPointer().?(4, 1, c.GL_FLOAT, c.GL_FALSE, stride, @ptrFromInt(11 * @sizeOf(f32)));
    c.glEnableVertexAttribArray().?(4);

    // Skylight (1)
    c.glVertexAttribPointer().?(5, 1, c.GL_FLOAT, c.GL_FALSE, stride, @ptrFromInt(12 * @sizeOf(f32)));
    c.glEnableVertexAttribArray().?(5);

    // Blocklight (1)
    c.glVertexAttribPointer().?(6, 1, c.GL_FLOAT, c.GL_FALSE, stride, @ptrFromInt(13 * @sizeOf(f32)));
    c.glEnableVertexAttribArray().?(6);

    c.glBindVertexArray().?(0);

    if (ctx.free_indices.items.len > 0) {
        const new_len = ctx.free_indices.items.len - 1;
        const idx = ctx.free_indices.items[new_len];
        ctx.free_indices.items.len = new_len;

        ctx.buffers.items[idx] = .{ .vao = vao, .vbo = vbo };
        return @intCast(idx + 1);
    } else {
        ctx.buffers.append(ctx.allocator, .{ .vao = vao, .vbo = vbo }) catch {
            c.glDeleteVertexArrays().?(1, &vao);
            c.glDeleteBuffers().?(1, &vbo);
            return rhi.InvalidBufferHandle;
        };
        return @intCast(ctx.buffers.items.len);
    }
}

fn uploadBuffer(ctx_ptr: *anyopaque, handle: rhi.BufferHandle, data: []const u8) void {
    const ctx: *OpenGLContext = @ptrCast(@alignCast(ctx_ptr));
    ctx.mutex.lock();
    defer ctx.mutex.unlock();

    if (handle == 0) return;
    const idx = handle - 1;
    if (idx < ctx.buffers.items.len) {
        const buf = ctx.buffers.items[idx];
        if (buf.vbo != 0) {
            c.glBindBuffer().?(c.GL_ARRAY_BUFFER, buf.vbo);
            // Replace entire buffer content
            // NOTE: In a real queue we would use glMapBufferRange or just glBufferSubData
            // For now, since we allocate with size in createBuffer, we use glBufferSubData.
            c.glBufferSubData().?(c.GL_ARRAY_BUFFER, 0, @intCast(data.len), data.ptr);
            c.glBindBuffer().?(c.GL_ARRAY_BUFFER, 0);
        }
    }
}

fn destroyBuffer(ctx_ptr: *anyopaque, handle: rhi.BufferHandle) void {
    const ctx: *OpenGLContext = @ptrCast(@alignCast(ctx_ptr));
    ctx.mutex.lock();
    defer ctx.mutex.unlock();

    if (handle == 0) return;
    const idx = handle - 1;
    if (idx < ctx.buffers.items.len) {
        const buf = ctx.buffers.items[idx];
        if (buf.vao != 0) {
            var vao = buf.vao;
            var vbo = buf.vbo;
            c.glDeleteVertexArrays().?(1, &vao);
            c.glDeleteBuffers().?(1, &vbo);
            ctx.buffers.items[idx] = .{ .vao = 0, .vbo = 0 };
            ctx.free_indices.append(ctx.allocator, idx) catch {};
        }
    }
}

fn beginFrame(ctx_ptr: *anyopaque) void {
    _ = ctx_ptr;
}

fn endFrame(ctx_ptr: *anyopaque) void {
    _ = ctx_ptr;
}

fn updateGlobalUniforms(ctx_ptr: *anyopaque, view_proj: Mat4, cam_pos: Vec3, sun_dir: Vec3, time: f32, fog_color: Vec3, fog_density: f32, fog_enabled: bool, sun_intensity: f32, ambient: f32) void {
    _ = ctx_ptr;
    _ = view_proj;
    _ = cam_pos;
    _ = sun_dir;
    _ = time;
    _ = fog_color;
    _ = fog_density;
    _ = fog_enabled;
    _ = sun_intensity;
    _ = ambient;
}

fn setModelMatrix(ctx_ptr: *anyopaque, model: Mat4) void {
    _ = ctx_ptr;
    _ = model;
}

fn draw(ctx_ptr: *anyopaque, handle: rhi.BufferHandle, count: u32, mode: rhi.DrawMode) void {
    const ctx: *OpenGLContext = @ptrCast(@alignCast(ctx_ptr));
    ctx.mutex.lock();
    defer ctx.mutex.unlock();

    if (handle == 0) return;
    const idx = handle - 1;
    if (idx < ctx.buffers.items.len) {
        const buf = ctx.buffers.items[idx];
        if (buf.vao != 0) {
            c.glBindVertexArray().?(buf.vao);
            const gl_mode: c.GLenum = switch (mode) {
                .triangles => c.GL_TRIANGLES,
                .lines => c.GL_LINES,
                .points => c.GL_POINTS,
            };
            c.glDrawArrays(gl_mode, 0, @intCast(count));
            c.glBindVertexArray().?(0);
        }
    }
}

fn createTexture(ctx_ptr: *anyopaque, width: u32, height: u32, data: []const u8) rhi.TextureHandle {
    _ = ctx_ptr;
    var id: c.GLuint = 0;
    c.glGenTextures(1, &id);
    c.glBindTexture(c.GL_TEXTURE_2D, id);

    // Default parameters (linear/linear)
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_REPEAT);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_REPEAT);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_LINEAR);

    c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_RGBA, @intCast(width), @intCast(height), 0, c.GL_RGBA, c.GL_UNSIGNED_BYTE, if (data.len > 0) data.ptr else null);
    c.glGenerateMipmap().?(c.GL_TEXTURE_2D);

    return @intCast(id);
}

fn destroyTexture(ctx_ptr: *anyopaque, handle: rhi.TextureHandle) void {
    _ = ctx_ptr;
    if (handle == 0) return;
    var id: c.GLuint = @intCast(handle);
    c.glDeleteTextures(1, &id);
}

fn bindTexture(ctx_ptr: *anyopaque, handle: rhi.TextureHandle, slot: u32) void {
    _ = ctx_ptr;
    c.glActiveTexture().?(@as(c.GLenum, @intCast(@as(u32, @intCast(c.GL_TEXTURE0)) + slot)));
    c.glBindTexture(c.GL_TEXTURE_2D, @intCast(handle));
}

fn getAllocator(ctx_ptr: *anyopaque) std.mem.Allocator {
    const ctx: *OpenGLContext = @ptrCast(@alignCast(ctx_ptr));
    return ctx.allocator;
}

fn updateTexture(ctx_ptr: *anyopaque, handle: rhi.TextureHandle, data: []const u8) void {
    _ = ctx_ptr;
    // This assumes the texture is already bound or we bind it temporarily
    // For safety, we should really track width/height or have them passed in.
    // But world_map.zig calls it expecting a specific size.
    // For now, let's assume 256x256 as used in world_map.zig or get from GL.
    c.glBindTexture(c.GL_TEXTURE_2D, @intCast(handle));
    var w: c.GLint = 0;
    var h: c.GLint = 0;
    c.glGetTexLevelParameteriv(c.GL_TEXTURE_2D, 0, c.GL_TEXTURE_WIDTH, &w);
    c.glGetTexLevelParameteriv(c.GL_TEXTURE_2D, 0, c.GL_TEXTURE_HEIGHT, &h);

    c.glTexSubImage2D(
        c.GL_TEXTURE_2D,
        0,
        0,
        0,
        w,
        h,
        c.GL_RGBA,
        c.GL_UNSIGNED_BYTE,
        data.ptr,
    );
}

// UI Rendering functions
fn beginUI(ctx_ptr: *anyopaque, screen_width: f32, screen_height: f32) void {
    const ctx: *OpenGLContext = @ptrCast(@alignCast(ctx_ptr));
    ctx.ui_screen_width = screen_width;
    ctx.ui_screen_height = screen_height;

    // Ensure we're rendering to the default framebuffer
    c.glBindFramebuffer().?(c.GL_FRAMEBUFFER, 0);

    // Disable depth test and culling for UI
    c.glDisable(c.GL_DEPTH_TEST);
    c.glDisable(c.GL_CULL_FACE);
    c.glEnable(c.GL_BLEND);
    c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);

    if (ctx.ui_shader) |*shader| {
        shader.use();
        // Orthographic projection: (0,0) at top-left
        const proj = Mat4.orthographic(0, screen_width, screen_height, 0, -1, 1);
        shader.setMat4("projection", &proj.data);
    }

    c.glBindVertexArray().?(ctx.ui_vao);
}

fn endUI(ctx_ptr: *anyopaque) void {
    _ = ctx_ptr;
    c.glBindVertexArray().?(0);
    c.glDisable(c.GL_BLEND);
    c.glEnable(c.GL_DEPTH_TEST);
    c.glEnable(c.GL_CULL_FACE);
}

fn drawUIQuad(ctx_ptr: *anyopaque, rect: rhi.Rect, color: rhi.Color) void {
    const ctx: *OpenGLContext = @ptrCast(@alignCast(ctx_ptr));

    const x = rect.x;
    const y = rect.y;
    const w = rect.width;
    const h = rect.height;

    // Two triangles forming a quad
    // Each vertex: x, y, r, g, b, a
    const vertices = [_]f32{
        // Triangle 1
        x,     y,     color.r, color.g, color.b, color.a,
        x + w, y,     color.r, color.g, color.b, color.a,
        x + w, y + h, color.r, color.g, color.b, color.a,
        // Triangle 2
        x,     y,     color.r, color.g, color.b, color.a,
        x + w, y + h, color.r, color.g, color.b, color.a,
        x,     y + h, color.r, color.g, color.b, color.a,
    };

    c.glBindBuffer().?(c.GL_ARRAY_BUFFER, ctx.ui_vbo);
    c.glBufferData().?(c.GL_ARRAY_BUFFER, @sizeOf(@TypeOf(vertices)), &vertices, c.GL_DYNAMIC_DRAW);
    c.glDrawArrays(c.GL_TRIANGLES, 0, 6);
}

fn drawUITexturedQuad(ctx_ptr: *anyopaque, texture: rhi.TextureHandle, rect: rhi.Rect) void {
    const ctx: *OpenGLContext = @ptrCast(@alignCast(ctx_ptr));

    const x = rect.x;
    const y = rect.y;
    const w = rect.width;
    const h = rect.height;

    if (ctx.ui_tex_shader) |*tex_shader| {
        tex_shader.use();
        const proj = Mat4.orthographic(0, ctx.ui_screen_width, ctx.ui_screen_height, 0, -1, 1);
        tex_shader.setMat4("projection", &proj.data);

        c.glActiveTexture().?(c.GL_TEXTURE0);
        c.glBindTexture(c.GL_TEXTURE_2D, @intCast(texture));
        tex_shader.setInt("uTexture", 0);
    }

    // Position (2) + TexCoord (2) = 4 floats per vertex
    const vertices = [_]f32{
        // pos, uv
        x,     y,     0.0, 0.0,
        x + w, y,     1.0, 0.0,
        x + w, y + h, 1.0, 1.0,
        x,     y,     0.0, 0.0,
        x + w, y + h, 1.0, 1.0,
        x,     y + h, 0.0, 1.0,
    };

    // Need different VAO setup for textured quads - use same VBO but different layout
    // For simplicity, we'll just draw with position data and let the shader handle it
    c.glBindBuffer().?(c.GL_ARRAY_BUFFER, ctx.ui_vbo);
    c.glBufferData().?(c.GL_ARRAY_BUFFER, @sizeOf(@TypeOf(vertices)), &vertices, c.GL_DYNAMIC_DRAW);

    // Temporarily reconfigure vertex attributes for textured quad
    const stride: c.GLsizei = 4 * @sizeOf(f32);
    c.glVertexAttribPointer().?(0, 2, c.GL_FLOAT, c.GL_FALSE, stride, null);
    c.glVertexAttribPointer().?(1, 2, c.GL_FLOAT, c.GL_FALSE, stride, @ptrFromInt(2 * @sizeOf(f32)));

    c.glDrawArrays(c.GL_TRIANGLES, 0, 6);

    // Restore colored quad vertex format
    const color_stride: c.GLsizei = 6 * @sizeOf(f32);
    c.glVertexAttribPointer().?(0, 2, c.GL_FLOAT, c.GL_FALSE, color_stride, null);
    c.glVertexAttribPointer().?(1, 4, c.GL_FLOAT, c.GL_FALSE, color_stride, @ptrFromInt(2 * @sizeOf(f32)));

    // Switch back to color shader
    if (ctx.ui_shader) |*shader| {
        shader.use();
    }
}

const vtable = rhi.RHI.VTable{
    .init = init,
    .deinit = deinit,
    .createBuffer = createBuffer,
    .uploadBuffer = uploadBuffer,
    .destroyBuffer = destroyBuffer,
    .beginFrame = beginFrame,
    .endFrame = endFrame,
    .updateGlobalUniforms = updateGlobalUniforms,
    .setModelMatrix = setModelMatrix,
    .draw = draw,
    .createTexture = createTexture,
    .destroyTexture = destroyTexture,
    .bindTexture = bindTexture,
    .updateTexture = updateTexture,
    .getAllocator = getAllocator,
    .beginUI = beginUI,
    .endUI = endUI,
    .drawUIQuad = drawUIQuad,
    .drawUITexturedQuad = drawUITexturedQuad,
};

pub fn createRHI(allocator: std.mem.Allocator) !rhi.RHI {
    const ctx = try allocator.create(OpenGLContext);
    ctx.* = .{
        .allocator = allocator,
        .buffers = .empty,
        .free_indices = .empty,
        .mutex = .{},
        .ui_shader = null,
        .ui_tex_shader = null,
        .ui_vao = 0,
        .ui_vbo = 0,
        .ui_screen_width = 1280,
        .ui_screen_height = 720,
    };

    return rhi.RHI{
        .ptr = ctx,
        .vtable = &vtable,
    };
}
