#version 450


layout(set = 0, binding = 3) uniform UniformBufferObject4 {
    mat4 mat;
} colormat;

layout(location = 1) in vec3 fragUv;
layout(location = 2) in vec4 fragColor;
layout(location = 0) out vec4 outColor;


void main() {
    // vec3 dx = dFdx(fragUv);
    // vec3 dy = dFdy(fragUv);
    // float fx = (3 * fragUv.x * fragUv.x) * dx.x - dx.y * fragUv.y - dx.z * fragUv.z;
    // float fy = (3 * fragUv.x * fragUv.x) * dy.x - dy.y * fragUv.y - dy.z * fragUv.z;

    // float sd = (pow(fragUv.x, 3) - fragUv.y * fragUv.z) / sqrt(fx * fx + fy * fy);
    // float alpha = 0.5 - sd;
    
    outColor = fragColor;

    if ((pow(fragUv.x, 3) - fragUv.y * fragUv.z) <= 0) discard;
}