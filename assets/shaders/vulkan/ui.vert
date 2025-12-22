#version 450

layout(location = 0) in vec2 aPos;
layout(location = 1) in vec4 aColor;

layout(location = 0) out vec4 vColor;

layout(push_constant) uniform PushConstants {
    mat4 projection;
} pc;

void main() {
    gl_Position = pc.projection * vec4(aPos, 0.0, 1.0);
    // Vulkan NDC has Y pointing down, OpenGL has Y pointing up
    // Our orthographic projection creates OpenGL-style coords, so flip Y for Vulkan
    gl_Position.y = -gl_Position.y;
    vColor = aColor;
}
