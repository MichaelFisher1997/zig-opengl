#version 450

layout(location = 0) in vec2 vTexCoord;

layout(location = 0) out vec4 FragColor;

layout(set = 0, binding = 0) uniform sampler2D uTexture;

void main() {
    vec4 texColor = texture(uTexture, vTexCoord);
    // UI textures are typically sRGB. Convert to linear so the
    // hardware sRGB swapchain encodes them back correctly.
    vec3 linearColor = pow(texColor.rgb, vec3(2.2));
    FragColor = vec4(linearColor, texColor.a);
}
