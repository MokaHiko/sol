/// Full Screen Quad
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
layout(binding=0) uniform texture2D tex;
layout(binding=0) uniform sampler smp;

in vec2 uv;

out vec4 frag_color;

void main() {
  vec4 color = texture(sampler2D(tex, smp), uv);
  frag_color = color;
}

@end

@program fsq vs_fsq fs_fsq
