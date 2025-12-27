#version 450

layout(location = 0) in vec2 vTexCoord;

layout(location = 0) out vec4 FragColor;

layout(set = 0, binding = 0) uniform sampler2D uDepthMap;

void main() {
    float depth = texture(uDepthMap, vTexCoord).r;
    // Display depth as grayscale - depth is typically 0-1 range
    FragColor = vec4(vec3(depth), 1.0);
}
