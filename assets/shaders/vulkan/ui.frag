#version 450

layout(location = 0) in vec4 vColor;

layout(location = 0) out vec4 FragColor;

void main() {
    // UI colors are typically defined in sRGB space.
    // Since we are using an sRGB swapchain, we need to convert to linear here
    // so the hardware can correctly encode it back to sRGB on output.
    vec3 linearColor = pow(vColor.rgb, vec3(2.2));
    FragColor = vec4(linearColor, vColor.a);
}
