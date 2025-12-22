#version 450

layout(location = 0) in vec3 vColor;
layout(location = 1) flat in vec3 vNormal;
layout(location = 2) in vec2 vTexCoord;
layout(location = 3) flat in int vTileID;
layout(location = 4) in float vDistance;
layout(location = 5) in float vSkyLight;
layout(location = 6) in float vBlockLight;
layout(location = 7) in vec3 vFragPosWorld;
layout(location = 8) in float vViewDepth;

layout(location = 0) out vec4 FragColor;

layout(set = 0, binding = 0) uniform GlobalUniforms {
    mat4 view_proj;
    vec4 cam_pos;
    vec4 sun_dir;
    vec4 fog_color;
    float time;
    float fog_density;
    float fog_enabled;
    float sun_intensity;
    float ambient;
    float padding[3];
} global;

layout(set = 0, binding = 1) uniform sampler2D uTexture;

void main() {
    // DEBUG: Output bright magenta to verify draw calls are working
    // FragColor = vec4(1.0, 0.0, 1.0, 1.0); return;
    
    float nDotL = max(dot(vNormal, global.sun_dir.xyz), 0.0);
    
    float directLight = nDotL * global.sun_intensity;
    float skyLight = vSkyLight * (global.ambient + directLight * 0.8);
    float blockLight = vBlockLight;
    float lightLevel = max(skyLight, blockLight);
    
    lightLevel = max(lightLevel, global.ambient * 0.5);
    lightLevel = clamp(lightLevel, 0.0, 1.0);
    
    vec2 atlasSize = vec2(16.0, 16.0);
    vec2 tileSize = 1.0 / atlasSize;
    vec2 tilePos = vec2(mod(float(vTileID), atlasSize.x), floor(float(vTileID) / atlasSize.x));
    vec2 tiledUV = fract(vTexCoord);
    tiledUV = clamp(tiledUV, 0.001, 0.999);
    vec2 uv = (tilePos + tiledUV) * tileSize;
    
    vec4 texColor = texture(uTexture, uv);
    if (texColor.a < 0.1) discard;
    
    vec3 color = texColor.rgb * vColor * lightLevel;
    
    // Apply fog
    if (global.fog_enabled > 0.5) {
        float fogFactor = 1.0 - exp(-vDistance * global.fog_density);
        fogFactor = clamp(fogFactor, 0.0, 1.0);
        color = mix(color, global.fog_color.rgb, fogFactor);
    }
    
    FragColor = vec4(color, 1.0);
}
