/// ==============================
/// ========== GPASS ==============
/// ==============================
@vs vs_pbr

in vec3 position;
in vec3 normal;
in vec2 texcoord;

layout(binding=0) uniform scene_matrices {
  mat4 mvp;
};

out vec3 v_local_pos;
out vec3 v_normal;
out vec2 v_uv;

void main() {
  v_local_pos = position;
  v_normal = normal;
  v_uv = texcoord;
  gl_Position = mvp * vec4(position, 1.0);
}

@end

@fs fs_pbr

in vec3 v_local_pos;
in vec3 v_normal;
in vec2 v_uv;

out vec4 frag_color;

layout(binding=1) uniform texture2D abledo;
layout(binding=1) uniform sampler linear;

layout(binding=2) uniform material_parameters {
  vec4 base_color;
};

void main() {
  // normal =normal_sample * 2.0 - 1.0.
  //
  //occlusion = 1.0 + strength * (occlusionTexture - 1.0). 

  vec4 color = texture(sampler2D(abledo, linear), v_uv);
  color *= base_color;

  frag_color = vec4(color.xyz, 1.0);
  // frag_color = vec4(v_uv, 0.0, 1.0);
  // frag_color = vec4(v_normal, 1.0);
}

@end

@program pbr vs_pbr fs_pbr


/// ==============================
/// ========== BLIT ==============
/// ==============================
@vs vs_fsq

const vec2 positions[] = {
  {-1, -1}, {-1, 1}, { 1, 1},   // bottom-left, top-left, top-right
  { 1, 1}, { 1, -1}, { -1, -1}, // top right - bottom-right, bottom-left
};

const vec2 uvs[] = {
  {0, 0}, {0, 1}, { 1, 1},   // bottom-left, top-left, top-right
  {1, 1}, {1, 0}, {0, 0},    // top right - bottom-right, bottom-left
};

out vec2 uv;

void main() {
  uv = uvs[gl_VertexIndex];
  gl_Position = vec4(positions[gl_VertexIndex], 0.0f, 1.0);
}

@end

@fs fs_fsq
layout(binding=1) uniform texture2D tex;
layout(binding=1) uniform sampler smp;

in vec2 uv;

out vec4 frag_color;

void main() {
  vec4 color = texture(sampler2D(tex, smp), uv);
  frag_color = color;
}

@end

@program fsq vs_fsq fs_fsq
