const std = @import("std");

// Import C headers
const c = @cImport({
    @cDefine("_FORTIFY_SOURCE", "0");
    @cInclude("SDL3/SDL.h");
    @cInclude("GL/glew.h");
    @cInclude("SDL3/SDL_opengl.h");
});

// Simple Shader Sources
const vertex_shader_src =
    \\#version 330 core
    \\layout (location = 0) in vec3 aPos;
    \\layout (location = 1) in vec3 aColor;
    \\out vec3 vColor;
    \\uniform mat4 transform;
    \\void main() {
    \\    gl_Position = transform * vec4(aPos, 1.0);
    \\    vColor = aColor;
    \\}
;

const fragment_shader_src =
    \\#version 330 core
    \\in vec3 vColor;
    \\out vec4 FragColor;
    \\void main() {
    \\    FragColor = vec4(vColor, 1.0);
    \\}
;

// Matrix Helper
const Mat4 = struct {
    data: [4][4]f32,

    fn identity() Mat4 {
        return .{
            .data = .{
                .{ 1, 0, 0, 0 },
                .{ 0, 1, 0, 0 },
                .{ 0, 0, 1, 0 },
                .{ 0, 0, 0, 1 },
            },
        };
    }

    fn multiply(a: Mat4, b: Mat4) Mat4 {
        var res = Mat4.identity();
        for (0..4) |r| {
            for (0..4) |c_idx| {
                res.data[r][c_idx] =
                    a.data[r][0] * b.data[0][c_idx] +
                    a.data[r][1] * b.data[1][c_idx] +
                    a.data[r][2] * b.data[2][c_idx] +
                    a.data[r][3] * b.data[3][c_idx];
            }
        }
        return res;
    }

    fn perspective(fov: f32, aspect: f32, near: f32, far: f32) Mat4 {
        const tan_half_fov = std.math.tan(fov / 2.0);
        var res = Mat4.identity();
        // Zero out diagonal first
        res.data[0][0] = 0;
        res.data[1][1] = 0;
        res.data[2][2] = 0;
        res.data[3][3] = 0;

        res.data[0][0] = 1.0 / (aspect * tan_half_fov);
        res.data[1][1] = 1.0 / tan_half_fov;
        res.data[2][2] = -(far + near) / (far - near);
        res.data[2][3] = -(2.0 * far * near) / (far - near);
        res.data[3][2] = -1.0;
        return res;
    }

    fn translate(x: f32, y: f32, z: f32) Mat4 {
        var res = Mat4.identity();
        res.data[0][3] = x;
        res.data[1][3] = y;
        res.data[2][3] = z;
        return res;
    }

    fn rotateY(angle: f32) Mat4 {
        var res = Mat4.identity();
        const c_val = std.math.cos(angle);
        const s_val = std.math.sin(angle);
        res.data[0][0] = c_val;
        res.data[0][2] = s_val;
        res.data[2][0] = -s_val;
        res.data[2][2] = c_val;
        return res;
    }
};

pub fn main() !void {
    // 1. Initialize SDL
    if (c.SDL_Init(c.SDL_INIT_VIDEO) == false) {
        std.debug.print("SDL Init Failed: {s}\n", .{c.SDL_GetError()});
        return error.SDLInitializationFailed;
    }
    defer c.SDL_Quit();

    // 2. Configure OpenGL Attributes
    _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_MAJOR_VERSION, 3);
    _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_MINOR_VERSION, 3);
    _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_PROFILE_MASK, c.SDL_GL_CONTEXT_PROFILE_CORE);

    // 3. Create Window
    const window = c.SDL_CreateWindow("Zig SDL3 OpenGL", 800, 600, c.SDL_WINDOW_OPENGL | c.SDL_WINDOW_RESIZABLE);
    if (window == null) return error.WindowCreationFailed;
    defer c.SDL_DestroyWindow(window);

    // 4. Create Context
    const gl_context = c.SDL_GL_CreateContext(window);
    if (gl_context == null) return error.GLContextCreationFailed;
    defer _ = c.SDL_GL_DestroyContext(gl_context);

    _ = c.SDL_GL_MakeCurrent(window, gl_context);

    // 5. Initialize GLEW (Must be done after Context creation)
    c.glewExperimental = c.GL_TRUE;
    if (c.glewInit() != c.GLEW_OK) {
        return error.GLEWInitFailed;
    }

    // Enable Depth Test for 3D
    c.glEnable(c.GL_DEPTH_TEST);

    // 6. Setup Tetrahedron Data (Position x,y,z | Color r,g,b)
    const vertices = [_]f32{
        // Front Face (Red)
        0.0,  0.5,  0.0,  1.0, 0.0, 0.0,
        -0.5, -0.5, 0.5,  1.0, 0.0, 0.0,
        0.5,  -0.5, 0.5,  1.0, 0.0, 0.0,

        // Right Face (Green)
        0.0,  0.5,  0.0,  0.0, 1.0, 0.0,
        0.5,  -0.5, 0.5,  0.0, 1.0, 0.0,
        0.5,  -0.5, -0.5, 0.0, 1.0, 0.0,

        // Back Face (Blue)
        0.0,  0.5,  0.0,  0.0, 0.0, 1.0,
        0.5,  -0.5, -0.5, 0.0, 0.0, 1.0,
        -0.5, -0.5, -0.5, 0.0, 0.0, 1.0,

        // Left Face (Yellow)
        0.0,  0.5,  0.0,  1.0, 1.0, 0.0,
        -0.5, -0.5, -0.5, 1.0, 1.0, 0.0,
        -0.5, -0.5, 0.5,  1.0, 1.0, 0.0,

        // Bottom Face (Grey) - Optional, makes it a solid solid
        -0.5, -0.5, 0.5,  0.5, 0.5, 0.5,
        -0.5, -0.5, -0.5, 0.5, 0.5, 0.5,
        0.5,  -0.5, -0.5, 0.5, 0.5, 0.5,

        -0.5, -0.5, 0.5,  0.5, 0.5, 0.5,
        0.5,  -0.5, -0.5, 0.5, 0.5, 0.5,
        0.5,  -0.5, 0.5,  0.5, 0.5, 0.5,
    };

    var vao: c.GLuint = undefined;
    var vbo: c.GLuint = undefined;
    c.glGenVertexArrays().?(1, &vao);
    c.glGenBuffers().?(1, &vbo);

    c.glBindVertexArray().?(vao);

    c.glBindBuffer().?(c.GL_ARRAY_BUFFER, vbo);
    c.glBufferData().?(c.GL_ARRAY_BUFFER, @sizeOf(@TypeOf(vertices)), &vertices, c.GL_STATIC_DRAW);

    // Position Attribute (Layout 0, 3 floats, Stride 6 * f32)
    c.glVertexAttribPointer().?(0, 3, c.GL_FLOAT, c.GL_FALSE, 6 * @sizeOf(f32), null);
    c.glEnableVertexAttribArray().?(0);

    // Color Attribute (Layout 1, 3 floats, Offset 3 * f32)
    c.glVertexAttribPointer().?(1, 3, c.GL_FLOAT, c.GL_FALSE, 6 * @sizeOf(f32), @ptrFromInt(3 * @sizeOf(f32)));
    c.glEnableVertexAttribArray().?(1);

    // 7. Compile Shaders

    const shader_program = try createShaderProgram();
    defer c.glDeleteProgram().?(shader_program);

    const transform_loc = c.glGetUniformLocation().?(shader_program, "transform");

    // 8. Main Loop
    var running = true;
    while (running) {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event)) {
            if (event.type == c.SDL_EVENT_QUIT) running = false;
            if (event.type == c.SDL_EVENT_KEY_DOWN and event.key.key == c.SDLK_ESCAPE) running = false;
        }

        // Calculate Matrix
        const time = @as(f32, @floatFromInt(c.SDL_GetTicks())) / 1000.0;

        // Projection (Aspect ratio 800/600)
        const proj = Mat4.perspective(std.math.degreesToRadians(45.0), 800.0 / 600.0, 0.1, 100.0);

        // View/Model (Push back -3 units, rotate)
        const model_trans = Mat4.translate(0, 0, -3.0);
        const model_rot = Mat4.rotateY(time);
        const model = Mat4.multiply(model_trans, model_rot);

        const mvp = Mat4.multiply(proj, model);

        // Render
        c.glClearColor(0.1, 0.1, 0.1, 1.0);
        c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);

        c.glUseProgram().?(shader_program);

        // Send Matrix (transpose = GL_TRUE because our matrix is row-major)
        c.glUniformMatrix4fv().?(transform_loc, 1, c.GL_TRUE, &mvp.data[0][0]);

        c.glBindVertexArray().?(vao);
        c.glDrawArrays(c.GL_TRIANGLES, 0, 18); // 6 triangles * 3 vertices

        _ = c.SDL_GL_SwapWindow(window);
    }
}

fn createShaderProgram() !c.GLuint {
    // Helper to compile single shader
    const compile = struct {
        fn func(shader_type: c.GLenum, source: [*c]const u8) !c.GLuint {
            const shader = c.glCreateShader().?(shader_type);
            c.glShaderSource().?(shader, 1, &source, null);
            c.glCompileShader().?(shader);

            var success: c.GLint = undefined;
            c.glGetShaderiv().?(shader, c.GL_COMPILE_STATUS, &success);
            if (success == 0) return error.ShaderCompileFailed;

            return shader;
        }
    }.func;

    const vert = try compile(c.GL_VERTEX_SHADER, vertex_shader_src);
    const frag = try compile(c.GL_FRAGMENT_SHADER, fragment_shader_src);

    const prog = c.glCreateProgram().?();
    c.glAttachShader().?(prog, vert);
    c.glAttachShader().?(prog, frag);
    c.glLinkProgram().?(prog);

    c.glDeleteShader().?(vert);
    c.glDeleteShader().?(frag);

    return prog;
}
