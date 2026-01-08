#version 450

layout(location = 0) in vec3 vWorldDir;
layout(location = 0) out vec4 FragColor;

layout(push_constant) uniform SkyPC {
    vec4 cam_forward;
    vec4 cam_right;
    vec4 cam_up;
    vec4 sun_dir;
    vec4 sky_color;
    vec4 horizon_color;
    vec4 params; // aspect, tanHalfFov, sunIntensity, moonIntensity
    vec4 time;
} pc;

float hash21(vec2 p) {
    p = fract(p * vec2(234.34, 435.345));
    p += dot(p, p + 34.23);
    return fract(p.x * p.y);
}

vec2 hash22(vec2 p) {
    float n = hash21(p);
    return vec2(n, hash21(p + n));
}

float stars(vec3 dir) {
    float theta = atan(dir.z, dir.x);
    float phi = asin(clamp(dir.y, -1.0, 1.0));

    vec2 gridCoord = vec2(theta * 15.0, phi * 30.0);
    vec2 cell = floor(gridCoord);
    vec2 cellFrac = fract(gridCoord);

    float brightness = 0.0;

    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            vec2 neighbor = cell + vec2(float(dx), float(dy));

            float starChance = hash21(neighbor);
            if (starChance > 0.92) {
                vec2 starPos = hash22(neighbor * 1.7);
                vec2 offset = vec2(float(dx), float(dy)) + starPos - cellFrac;
                float dist = length(offset);

                float starBright = smoothstep(0.08, 0.0, dist);
                starBright *= 0.5 + 0.5 * hash21(neighbor * 3.14);
                float twinkle = 0.7 + 0.3 * sin(hash21(neighbor) * 50.0 + pc.time.x * 8.0);
                starBright *= twinkle;

                brightness = max(brightness, starBright);
            }
        }
    }

    return brightness;
}

void main() {
    vec3 dir = normalize(vWorldDir);

    float horizon = 1.0 - abs(dir.y);
    horizon = pow(horizon, 1.5);
    vec3 sky = mix(pc.sky_color.xyz, pc.horizon_color.xyz, horizon);

    float sunDot = dot(dir, normalize(pc.sun_dir.xyz));
    float sunDisc = smoothstep(0.9995, 0.9999, sunDot);
    vec3 sunColor = pow(vec3(1.0, 0.95, 0.8), vec3(2.2));

    float sunGlow = pow(max(sunDot, 0.0), 8.0) * 0.5;
    sunGlow += pow(max(sunDot, 0.0), 64.0) * 0.3;

    float moonDot = dot(dir, -normalize(pc.sun_dir.xyz));
    float moonDisc = smoothstep(0.9990, 0.9995, moonDot);
    vec3 moonColor = pow(vec3(0.9, 0.9, 1.0), vec3(2.2));

    float starIntensity = 0.0;
    if (pc.params.z < 0.3 && dir.y > 0.0) {
        float nightFactor = 1.0 - pc.params.z * 3.33;
        starIntensity = stars(dir) * nightFactor * 1.5;
    }

    vec3 finalColor = sky;

    // Clouds are now rendered via dedicated cloud pipeline
    // (removed duplicate cloud rendering from sky shader)

    finalColor += sunGlow * pc.params.z * pow(vec3(1.0, 0.8, 0.4), vec3(2.2));
    finalColor += sunDisc * sunColor * pc.params.z;
    finalColor += moonDisc * moonColor * pc.params.w * 3.0;
    finalColor += vec3(starIntensity);

    FragColor = vec4(finalColor, 1.0);
}
