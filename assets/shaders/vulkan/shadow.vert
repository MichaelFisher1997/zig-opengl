#version 450

layout(location = 0) in vec3 aPos;

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

layout(push_constant) uniform ModelUniforms {
    mat4 model;
} model_data;

void main() {
    vec4 worldPos = model_data.model * vec4(aPos, 1.0);
    vec4 clipPos = global.view_proj * worldPos;
    gl_Position = clipPos;
    gl_Position.y = -gl_Position.y;
}
