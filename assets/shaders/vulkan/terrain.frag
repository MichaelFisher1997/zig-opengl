#version 450

layout(location = 0) in vec3 vColor;
layout(location = 1) flat in vec3 vNormal;
layout(location = 2) in vec2 vTexCoord;
layout(location = 3) flat in int vTileID;
layout(location = 4) in float vDistance;
layout(location = 5) in float vSkyLight;
layout(location = 6) in vec3 vBlockLight;
layout(location = 7) in vec3 vFragPosWorld;
layout(location = 8) in float vViewDepth;
layout(location = 9) in vec3 vTangent;
layout(location = 10) in vec3 vBitangent;
layout(location = 11) in float vAO;
layout(location = 12) in vec4 vClipPosCurrent;
layout(location = 13) in vec4 vClipPosPrev;
layout(location = 14) in float vMaskRadius;

layout(location = 0) out vec4 FragColor;

layout(set = 0, binding = 0) uniform GlobalUniforms {
    mat4 view_proj;
    mat4 view_proj_prev; // Previous frame's view-projection for velocity buffer
    vec4 cam_pos;
    vec4 sun_dir;
    vec4 sun_color;
    vec4 fog_color;
    vec4 cloud_wind_offset; // xy = offset, z = scale, w = coverage
    vec4 params; // x = time, y = fog_density, z = fog_enabled, w = sun_intensity
    vec4 lighting; // x = ambient, y = use_texture, z = pbr_enabled, w = cloud_shadow_strength
    vec4 cloud_params; // x = cloud_height, y = shadow_samples, z = shadow_blend, w = cloud_shadows
    vec4 pbr_params; // x = pbr_quality, y = exposure, z = saturation, w = ssao_strength
    vec4 volumetric_params; // x = enabled, y = density, z = steps, w = scattering
    vec4 viewport_size; // xy = width/height
} global;

// Constants
const float PI = 3.14159265359;

layout(set = 0, binding = 1) uniform sampler2D uTexture;
layout(set = 0, binding = 2) uniform ShadowUniforms {
    mat4 light_space_matrices[3];
    vec4 cascade_splits;
    vec4 shadow_texel_sizes;
} shadows;

layout(set = 0, binding = 3) uniform sampler2DArrayShadow uShadowMaps;
layout(set = 0, binding = 4) uniform sampler2DArray uShadowMapsRegular;
layout(set = 0, binding = 6) uniform sampler2D uNormalMap;
layout(set = 0, binding = 7) uniform sampler2D uRoughnessMap;
layout(set = 0, binding = 9) uniform sampler2D uEnvMap;
layout(set = 0, binding = 10) uniform sampler2D uSSAOMap;

layout(push_constant) uniform ModelUniforms {
    mat4 model;
    vec3 color_override;
    float mask_radius;
} model_data;

// Poisson Disk for PCF
const vec2 poissonDisk16[16] = vec2[](
    vec2(-0.94201624, -0.39906216),
    vec2(0.94558609, -0.76890725),
    vec2(-0.094184101, -0.92938870),
    vec2(0.34495938, 0.29387760),
    vec2(-0.91588581, 0.45771432),
    vec2(-0.81544232, -0.87912464),
    vec2(0.97484398, 0.75648379),
    vec2(0.44323325, -0.97511554),
    vec2(0.53742981, -0.47373420),
    vec2(-0.26496911, -0.41893023),
    vec2(0.79197514, 0.19090188),
    vec2(-0.24188840, 0.99706507),
    vec2(-0.81409955, 0.91437590),
    vec2(0.19984126, 0.78641367),
    vec2(0.14383161, -0.14100790),
    vec2(-0.63242006, 0.31173663)
);

float interleavedGradientNoise(vec2 fragCoord) {
    vec3 magic = vec3(0.06711056, 0.00583715, 52.9829189);
    return fract(magic.z * fract(dot(fragCoord.xy, magic.xy)));
}

float findBlocker(vec2 uv, float zReceiver, int layer) {
    float blockerDepthSum = 0.0;
    int numBlockers = 0;
    float searchRadius = 0.0015;
    for (int i = -1; i <= 1; i++) {
        for (int j = -1; j <= 1; j++) {
            vec2 offset = vec2(i, j) * searchRadius;
            float depth = texture(uShadowMapsRegular, vec3(uv + offset, float(layer))).r;
            if (depth > zReceiver + 0.0001) {
                blockerDepthSum += depth;
                numBlockers++;
            }
        }
    }
    if (numBlockers == 0) return -1.0;
    return blockerDepthSum / float(numBlockers);
}

float computeShadowFactor(vec3 fragPosWorld, vec3 N, vec3 L, int layer) {
    vec4 fragPosLightSpace = shadows.light_space_matrices[layer] * vec4(fragPosWorld, 1.0);
    vec3 projCoords = fragPosLightSpace.xyz / fragPosLightSpace.w;
    projCoords.xy = projCoords.xy * 0.5 + 0.5;
    
    if (projCoords.x < 0.0 || projCoords.x > 1.0 || projCoords.y < 0.0 || projCoords.y > 1.0 || projCoords.z < 0.0 || projCoords.z > 1.0) return 0.0;

    float currentDepth = projCoords.z;
    float texelSize = shadows.shadow_texel_sizes[layer];
    float baseTexelSize = shadows.shadow_texel_sizes[0];
    float cascadeScale = texelSize / max(baseTexelSize, 0.0001);
    
    float NdotL = max(dot(N, L), 0.001);
    float sinTheta = sqrt(1.0 - NdotL * NdotL);
    float tanTheta = sinTheta / NdotL;
    
    const float BASE_BIAS = 0.001;
    const float SLOPE_BIAS = 0.002;
    const float MAX_BIAS = 0.01;
    
    float bias = BASE_BIAS * cascadeScale + SLOPE_BIAS * min(tanTheta, 5.0) * cascadeScale;
    bias = min(bias, MAX_BIAS);
    if (vTileID < 0) bias = max(bias, 0.005 * cascadeScale);

    float angle = interleavedGradientNoise(gl_FragCoord.xy) * PI * 0.25;
    float s = sin(angle);
    float c = cos(angle);
    mat2 rot = mat2(c, s, -s, c);
    
    float shadow = 0.0;
    float radius = 0.0015 * cascadeScale;
    for (int i = 0; i < 16; i++) {
        vec2 offset = (rot * poissonDisk16[i]) * radius;
        shadow += texture(uShadowMaps, vec4(projCoords.xy + offset, float(layer), currentDepth + bias));
    }
    return 1.0 - (shadow / 16.0);
}

// Simplified PBR for terrain
vec3 fresnelSchlick(float cosTheta, vec3 F0) {
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

void main() {
    vec3 N = normalize(vNormal);
    vec2 tiledUV = fract(vTexCoord);
    tiledUV = clamp(tiledUV, 0.001, 0.999);
    vec2 uv = (vec2(mod(float(vTileID), 16.0), floor(float(vTileID) / 16.0)) + tiledUV) * (1.0 / 16.0);

    if (global.lighting.z > 0.5 && global.pbr_params.x > 1.5 && vTileID >= 0) {
        vec4 normalMapSample = texture(uNormalMap, uv);
        mat3 TBN = mat3(normalize(vTangent), normalize(vBitangent), N);
        N = normalize(TBN * (normalMapSample.rgb * 2.0 - 1.0));
    }

    vec3 L = normalize(global.sun_dir.xyz);
    float nDotL = max(dot(N, L), 0.0);
    int layer = vDistance < shadows.cascade_splits[0] ? 0 : (vDistance < shadows.cascade_splits[1] ? 1 : 2);
    float shadowFactor = computeShadowFactor(vFragPosWorld, N, L, layer);
    
    float ssao = mix(1.0, texture(uSSAOMap, gl_FragCoord.xy / global.viewport_size.xy).r, global.pbr_params.w);
    float ao = mix(1.0, vAO, mix(0.4, 0.05, clamp(vDistance / 128.0, 0.0, 1.0)));
    
    vec3 albedo = vColor;
    if (global.lighting.y > 0.5 && vTileID >= 0) {
        vec4 texColor = texture(uTexture, uv);
        if (texColor.a < 0.1) discard;
        albedo *= texColor.rgb;
    }

    vec3 ambient = albedo * global.lighting.x * ao * ssao;
    vec3 direct = albedo * global.sun_color.rgb * global.params.w * nDotL * (1.0 - shadowFactor);
    vec3 color = ambient + direct;

    if (global.params.z > 0.5) {
        color = mix(color, global.fog_color.rgb, clamp(1.0 - exp(-vDistance * global.params.y), 0.0, 1.0));
    }

    if (global.viewport_size.z > 0.5) {
        color = mix(vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), shadowFactor);
    }

    FragColor = vec4(color, 1.0);
}
