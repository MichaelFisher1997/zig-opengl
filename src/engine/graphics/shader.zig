//! Shader compilation and program management.

const std = @import("std");
const c = @cImport({
    @cInclude("GL/glew.h");
});

pub const Shader = struct {
    program: c.GLuint,

    pub const Error = error{
        VertexCompileFailed,
        FragmentCompileFailed,
        LinkFailed,
    };

    pub fn init(vertex_src: [*c]const u8, fragment_src: [*c]const u8) Error!Shader {
        const vert = try compileShader(c.GL_VERTEX_SHADER, vertex_src);
        defer c.glDeleteShader().?(vert);

        const frag = try compileShader(c.GL_FRAGMENT_SHADER, fragment_src);
        defer c.glDeleteShader().?(frag);

        const program = c.glCreateProgram().?();
        c.glAttachShader().?(program, vert);
        c.glAttachShader().?(program, frag);
        c.glLinkProgram().?(program);

        var success: c.GLint = undefined;
        c.glGetProgramiv().?(program, c.GL_LINK_STATUS, &success);
        if (success == 0) {
            return Error.LinkFailed;
        }

        return .{ .program = program };
    }

    pub fn deinit(self: *Shader) void {
        c.glDeleteProgram().?(self.program);
    }

    pub fn use(self: *const Shader) void {
        c.glUseProgram().?(self.program);
    }

    pub fn getUniformLocation(self: *const Shader, name: [*c]const u8) c.GLint {
        return c.glGetUniformLocation().?(self.program, name);
    }

    // Uniform setters
    pub fn setMat4(self: *const Shader, name: [*c]const u8, matrix: *const [4][4]f32) void {
        const loc = self.getUniformLocation(name);
        c.glUniformMatrix4fv().?(loc, 1, c.GL_FALSE, @ptrCast(matrix));
    }

    pub fn setVec3(self: *const Shader, name: [*c]const u8, x: f32, y: f32, z: f32) void {
        const loc = self.getUniformLocation(name);
        c.glUniform3f().?(loc, x, y, z);
    }

    pub fn setFloat(self: *const Shader, name: [*c]const u8, value: f32) void {
        const loc = self.getUniformLocation(name);
        c.glUniform1f().?(loc, value);
    }

    pub fn setInt(self: *const Shader, name: [*c]const u8, value: i32) void {
        const loc = self.getUniformLocation(name);
        c.glUniform1i().?(loc, value);
    }

    fn compileShader(shader_type: c.GLenum, source: [*c]const u8) Error!c.GLuint {
        const shader = c.glCreateShader().?(shader_type);
        c.glShaderSource().?(shader, 1, &source, null);
        c.glCompileShader().?(shader);

        var success: c.GLint = undefined;
        c.glGetShaderiv().?(shader, c.GL_COMPILE_STATUS, &success);
        if (success == 0) {
            if (shader_type == c.GL_VERTEX_SHADER) {
                return Error.VertexCompileFailed;
            } else {
                return Error.FragmentCompileFailed;
            }
        }

        return shader;
    }
};
