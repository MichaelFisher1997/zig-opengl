#version 450

layout(location = 0) in vec3 aPos;
layout(location = 1) in vec3 aNormal;

layout(push_constant) uniform ShadowModelUniforms {
    mat4 mvp;
    vec4 bias_params; // x=normalBias, y=slopeBias, z=cascadeIndex, w=texelSize
} pc;

void main() {
    // Standard chunk-relative normal (voxel faces are axis-aligned)
    vec3 worldNormal = aNormal; 
    
    // Normal offset bias: push geometry along normal by texelSize * normalBias
    float normalBias = pc.bias_params.x * pc.bias_params.w;
    vec3 biasedPos = aPos + worldNormal * normalBias;
    
    gl_Position = pc.mvp * vec4(biasedPos, 1.0);
    
    // Vulkan Y-flip: GL-style projection to Vulkan clip space
    gl_Position.y = -gl_Position.y;
}
