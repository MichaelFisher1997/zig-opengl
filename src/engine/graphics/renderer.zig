//! Main renderer that manages OpenGL state and rendering pipeline.

const std = @import("std");
const c = @cImport({
    @cInclude("GL/glew.h");
});

const Mat4 = @import("../math/mat4.zig").Mat4;
const Vec3 = @import("../math/vec3.zig").Vec3;
const Camera = @import("camera.zig").Camera;
const Shader = @import("shader.zig").Shader;
const Mesh = @import("mesh.zig").Mesh;

pub const Renderer = struct {
    clear_color: Vec3,
    wireframe: bool,

    pub fn init() Renderer {
        // Enable depth testing
        c.glEnable(c.GL_DEPTH_TEST);

        // Disable backface culling for now (debug)
        c.glDisable(c.GL_CULL_FACE);

        // Enable blending for transparency
        c.glEnable(c.GL_BLEND);
        c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);

        return .{
            .clear_color = Vec3.init(0.5, 0.7, 1.0), // Sky blue
            .wireframe = false,
        };
    }

    pub fn beginFrame(self: *const Renderer) void {
        c.glClearColor(self.clear_color.x, self.clear_color.y, self.clear_color.z, 1.0);
        c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);

        if (self.wireframe) {
            c.glPolygonMode(c.GL_FRONT_AND_BACK, c.GL_LINE);
        } else {
            c.glPolygonMode(c.GL_FRONT_AND_BACK, c.GL_FILL);
        }
    }

    pub fn setViewport(self: *Renderer, width: u32, height: u32) void {
        _ = self;
        c.glViewport(0, 0, @intCast(width), @intCast(height));
    }

    pub fn toggleWireframe(self: *Renderer) void {
        self.wireframe = !self.wireframe;
    }

    pub fn setClearColor(self: *Renderer, color: Vec3) void {
        self.clear_color = color;
    }

    /// Draw a mesh with a shader and transform
    pub fn drawMesh(self: *const Renderer, mesh: *const Mesh, shader: *const Shader, model: Mat4, view_proj: Mat4) void {
        _ = self;
        shader.use();

        const mvp = view_proj.multiply(model);
        shader.setMat4("transform", &mvp.data);

        mesh.draw();
    }
};
