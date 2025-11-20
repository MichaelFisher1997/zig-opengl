const std = @import("std");
const math = @import("math.zig");
const Vec3 = math.Vec3;
const Mat4 = math.Mat4;
const Camera = @import("camera.zig").Camera;
const chunk_mod = @import("chunk.zig");
const mesh_mod = @import("mesh.zig");

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
    _ = c.SDL_SetWindowRelativeMouseMode(window, true);

    // 5. Initialize GLEW (Must be done after Context creation)
    c.glewExperimental = c.GL_TRUE;
    if (c.glewInit() != c.GLEW_OK) {
        return error.GLEWInitFailed;
    }

    // Clear any GL errors that might have been caused by glewInit (common issue)
    _ = c.glGetError();

    // Enable Depth Test for 3D
    c.glEnable(c.GL_DEPTH_TEST);
    // Enable Backface Culling
    c.glEnable(c.GL_CULL_FACE);

    // 6. Initialize Chunk
    var chunk = chunk_mod.Chunk.init();

    // Fill with test data
    for (0..chunk_mod.CHUNK_SIZE_X) |x| {
        for (0..chunk_mod.CHUNK_SIZE_Z) |z| {
            // Layers 0-3: Stone
            chunk.setBlock(x, 0, z, .Stone);
            chunk.setBlock(x, 1, z, .Stone);
            chunk.setBlock(x, 2, z, .Stone);
            chunk.setBlock(x, 3, z, .Stone);

            // Layer 4: Dirt
            chunk.setBlock(x, 4, z, .Dirt);
            // Layer 5: Grass
            chunk.setBlock(x, 5, z, .Grass);
        }
    }
    // A random pillar
    chunk.setBlock(8, 6, 8, .Stone);
    chunk.setBlock(8, 7, 8, .Stone);
    chunk.setBlock(8, 8, 8, .Stone);

    // Generate Mesh
    const chunk_mesh = try mesh_mod.generateMesh(std.heap.c_allocator, &chunk);
    defer chunk_mesh.deinit();

    const vertex_count = @as(c_int, @intCast(chunk_mesh.vertices.len / 6));

    var vao: c.GLuint = undefined;
    var vbo: c.GLuint = undefined;

    // Use standard OpenGL functions if available, GLEW macros might be tricky in Zig?
    // But glew.h should map them.
    // Let's check if glGenVertexArrays is actually a function pointer that is null.
    // if (c.glGenVertexArrays == null) {
    //     std.debug.print("Error: glGenVertexArrays is null! OpenGL 3.3 not supported?\n", .{});
    //     return error.GLFunctionLoadFailed;
    // }

    c.glGenVertexArrays().?(1, &vao);
    c.glGenBuffers().?(1, &vbo);

    c.glBindVertexArray().?(vao);

    c.glBindBuffer().?(c.GL_ARRAY_BUFFER, vbo);
    // Upload dynamic mesh data
    c.glBufferData().?(c.GL_ARRAY_BUFFER, @as(c.GLsizeiptr, @intCast(chunk_mesh.vertices.len * @sizeOf(f32))), chunk_mesh.vertices.ptr, c.GL_STATIC_DRAW);

    // Position Attribute (Layout 0, 3 floats, Stride 6 * f32)
    c.glVertexAttribPointer().?(0, 3, c.GL_FLOAT, c.GL_FALSE, 6 * @sizeOf(f32), null);
    c.glEnableVertexAttribArray().?(0);

    // Color Attribute (Layout 1, 3 floats, Offset 3 * f32)
    c.glVertexAttribPointer().?(1, 3, c.GL_FLOAT, c.GL_FALSE, 6 * @sizeOf(f32), @ptrFromInt(3 * @sizeOf(f32)));
    c.glEnableVertexAttribArray().?(1);

    // 7. Compile Shaders
    const shader_program = try createShaderProgram();
    defer c.glDeleteProgram().?(shader_program);

    // Important: Use the shader program BEFORE locating uniforms!
    c.glUseProgram().?(shader_program);

    const transform_loc = c.glGetUniformLocation().?(shader_program, "transform");

    // Camera Setup (Position slightly outside the chunk to see it)
    var camera = Camera.new(Vec3.new(-5.0, 10.0, -5.0), Vec3.new(0.0, 1.0, 0.0), -45.0, -20.0);
    var lastTime: u64 = c.SDL_GetTicks();

    // 8. Main Loop
    var running = true;
    while (running) {
        // Calculate Delta Time
        const currentTime = c.SDL_GetTicks();
        const deltaTime = @as(f32, @floatFromInt(currentTime - lastTime)) / 1000.0;
        lastTime = currentTime;

        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event)) {
            if (event.type == c.SDL_EVENT_QUIT) running = false;
            if (event.type == c.SDL_EVENT_KEY_DOWN and event.key.key == c.SDLK_ESCAPE) running = false;

            if (event.type == c.SDL_EVENT_MOUSE_MOTION) {
                camera.processMouseMovement(event.motion.xrel, event.motion.yrel, true);
            }

            if (event.type == c.SDL_EVENT_WINDOW_RESIZED) {
                var w: c_int = 0;
                var h: c_int = 0;
                _ = c.SDL_GetWindowSize(window, &w, &h);
                c.glViewport(0, 0, w, h);
            }
        }

        // Keyboard Input
        const keys = c.SDL_GetKeyboardState(null);

        if (keys[c.SDL_SCANCODE_W]) camera.processKeyboard(.FORWARD, deltaTime);
        if (keys[c.SDL_SCANCODE_S]) camera.processKeyboard(.BACKWARD, deltaTime);
        if (keys[c.SDL_SCANCODE_A]) camera.processKeyboard(.LEFT, deltaTime);
        if (keys[c.SDL_SCANCODE_D]) camera.processKeyboard(.RIGHT, deltaTime);

        // Projection
        var w: c_int = 0;
        var h: c_int = 0;
        _ = c.SDL_GetWindowSize(window, &w, &h);
        const aspect = @as(f32, @floatFromInt(w)) / @as(f32, @floatFromInt(h));
        const proj = Mat4.perspective(std.math.degreesToRadians(45.0), aspect, 0.1, 100.0);
        // View (Camera)
        const view = camera.getViewMatrix();

        // Model (Identity)
        const model = Mat4.identity();

        const mvp = Mat4.multiply(proj, Mat4.multiply(view, model));

        // Render
        c.glClearColor(0.53, 0.81, 0.92, 1.0); // Sky blue background
        c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);

        c.glUseProgram().?(shader_program);

        c.glUniformMatrix4fv().?(transform_loc, 1, c.GL_TRUE, &mvp.data[0][0]);

        c.glBindVertexArray().?(vao);
        c.glDrawArrays(c.GL_TRIANGLES, 0, vertex_count);

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
