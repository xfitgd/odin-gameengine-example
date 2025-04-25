#version 450

//#extension GL_EXT_debug_printf : enable
layout(location = 0) out vec2 fragTexCoord;

layout(set = 1, binding = 0) uniform sampler2D texSampler;

vec2 quad[6] = {
    vec2(-1,-1),
    vec2(1, -1),
    vec2(-1, 1),
    vec2(1, -1),
    vec2(1, 1),
    vec2(-1, 1)
};

void main() {
    gl_Position = vec4(quad[gl_VertexIndex], 0.0, 1.0);
}