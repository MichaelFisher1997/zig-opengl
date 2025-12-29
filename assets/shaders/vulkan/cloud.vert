#version 450

layout(location = 0) in vec2 aPos;

layout(location = 0) out vec3 vWorldPos;

layout(push_constant) uniform CloudPC {
    mat4 view_proj;
    vec4 camera_pos;      // xyz = camera position, w = cloud_height
    vec4 cloud_params;    // x = coverage, y = scale, z = wind_offset_x, w = wind_offset_z
    vec4 sun_params;      // xyz = sun_dir, w = sun_intensity
    vec4 fog_params;      // xyz = fog_color, w = fog_density
} pc;

void main() {
    float cloudHeight = pc.camera_pos.w;
    vec3 relPos = vec3(
        aPos.x,
        cloudHeight - pc.camera_pos.y,
        aPos.y
    );
    vWorldPos = vec3(aPos.x + pc.camera_pos.x, cloudHeight, aPos.y + pc.camera_pos.z);
    gl_Position = pc.view_proj * vec4(relPos, 1.0);
    // Flip Y for Vulkan
    gl_Position.y = -gl_Position.y;
}
