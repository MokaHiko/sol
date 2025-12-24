/// ==============================
/// ========== QUAD ==============
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

/// ==============================
/// ========== GRID ==============
/// ==============================
@vs vs_grid

const vec2 positions[] = {
  {-1, -1}, {-1, 1}, { 1, 1},   // bottom-left, top-left, top-right
  { 1, 1}, { 1, -1}, { -1, -1}, // top right - bottom-right, bottom-left
};

const vec2 uvs[] = {
  {0, 0}, {0, 1}, { 1, 1},   // bottom-left, top-left, top-right
  {1, 1}, {1, 0}, {0, 0},    // top right - bottom-right, bottom-left
};

void main() {
  gl_Position = vec4(positions[gl_VertexIndex], 0.0f, 1.0);
}

@end

@fs fs_grid

layout(binding=0) uniform grid_props {
  mat4 inv_view_proj;
  vec2 resolution;
};

out vec4 frag_color;

float grid_color(vec2 coord);

void main() {
  vec4 ndc = vec4(gl_FragCoord.xy / resolution * 2 - 1.0, 0.0, 1.0);

  vec4 world_pos = inv_view_proj * ndc;
  vec2 world_coord = world_pos.xy / world_pos.w;

  float fine = grid_color(world_coord);
  float coarse = grid_color(world_coord / 5.0);

  float lw = fine + coarse;

  // Apply gamma correction
  fine = pow(fine, 1.0 / 2.2);
  frag_color = vec4(vec3(fine), 0.15 * lw);
 
  coarse = pow(coarse, 1.0 / 2.2);
  frag_color = vec4(frag_color.rgb, frag_color.a * 1.5);
}

float grid_color(vec2 coord) {
  // distance to nearest grid line (centered at integers) 
  // in texture coords [0-1.0]
  vec2 d = abs(fract(coord) - 0.5);

  // screen-space line thickness i.e unit/pixels
  vec2 w = fwidth(coord);

  // line_mask in pixels
  float line = min(d.x / w.x, d.y / w.y);
  return 1.0 - clamp(line, 0.0, 1.0);
}

@end

@program grid vs_grid fs_grid

/// ==============================
/// ========== Shape ============
/// ==============================
@block shape 
#define Circle          0
#define CircleTextured  1

#define Rect            2
#define RectTextured    3
@end

@vs vs_shape
@include_block shape

const vec2 positions[] = {
  {-1, -1}, {-1, 1}, { 1, 1},   // bottom-left, top-left, top-right
  { 1, 1}, { 1, -1}, { -1, -1}, // top right - bottom-right, bottom-left
};

const vec2 uvs[] = {
  {0, 0}, {0, 1}, { 1, 1},   // bottom-left, top-left, top-right
  {1, 1}, {1, 0}, {0, 0},    // top right - bottom-right, bottom-left
};

// x -> x_pos  : f32
// y -> y_pos  : f32
// z -> (type, ctx) : (Shape.Type(u16), u16)
// w -> shape_data union : f32
in vec4 shape;

layout(binding=0) uniform canvas_props {
  mat4 mvp; // orthographic
};

out vec2 local_pos;
out vec2 uv;
out flat uint shape_type;

void main() {
  uint vidx = gl_VertexIndex % 6;

  uv = uvs[vidx];
  local_pos = positions[vidx];

  uint shape_bytes = floatBitsToUint(shape.z);
  shape_type = shape_bytes & 0xFFFFu;

  uint shape_data = floatBitsToUint(shape.w);

  vec2 point = shape.xy;

  if(shape_type == Rect || shape_type == RectTextured) {
    uint w = shape_data >> 16 & 0xFFFFu;
    uint h = shape_data & 0xFFFFu;

    point.x += positions[vidx].x * w;
    point.y += positions[vidx].y * h;
  } else if(shape_type == Circle || shape_type == CircleTextured) {
    float radius = uintBitsToFloat(shape_data);
    point += positions[vidx] * radius;
  }

  gl_Position = mvp * vec4(point, 0.0f, 1.0);
}

@end

@fs fs_shape
@include_block shape

in vec2 local_pos;
in vec2 uv;
in flat uint shape_type;

layout(binding=1) uniform texture2D tex;
layout(binding=1) uniform sampler smp;

layout(binding=2) uniform shape_material {
  vec4 tint;
};

out vec4 frag_color;

float sd_circle(vec2 p, float r) {
  return length(p) - r;
}

float sd_rect(vec2 p, vec2 b) {
    vec2 d = abs(p)-b;
    return length(max(d,0.0)) + min(max(d.x,d.y),0.0);
}

void main() {
  float s = 0.0;

  if(shape_type == Rect || shape_type == RectTextured) {
    s += sd_rect(local_pos, vec2(1.0, 1.0));
  } else if(shape_type == Circle || shape_type == CircleTextured) {
    s += sd_circle(local_pos, 1);
  }

  float alpha = clamp(-s / fwidth(s), 0.0, 1.0);

  const float t = 0.05;
  float is_outline = step(abs(s), t) * alpha;

  vec4 color = texture(sampler2D(tex, smp), uv) * (1.0 - is_outline);
  color += vec4(0.0, 0.0, 0.0, 1.0) * is_outline;

  frag_color = vec4(alpha) * tint * color;
}

@end

@program shape vs_shape fs_shape
