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

/// Widget
// TODO: Specialize to WidgetsWColor, WidgetsWColorAndEffect 
@vs vs_widget
in vec2 in_pos;
in vec4 in_color;

out vec4 color;

layout(binding=0) uniform widget_properties {
  mat4 widget_mvp;
};

void main() {
  color = in_color;
  gl_Position = widget_mvp * vec4(in_pos, 1.0, 1.0);
}
@end

@fs fs_widget
out vec4 frag_color;

in vec4 color;

void main() {
  if(color.a == 0.0) {
    discard;
  }

  frag_color = color;
}
@end

@program widget vs_widget fs_widget

// Font
@vs vs_font
in vec2 in_pos;
in vec2 in_uv;

out vec2 uv;

layout(binding=1) uniform font_properties {
  mat4 font_mvp;
};

void main() {
  uv = in_uv;
  gl_Position = font_mvp * vec4(in_pos, 1.0, 1.0);
}
@end

@fs fs_font
out vec4 frag_color;

in vec2 uv;

layout(binding=0) uniform texture2D tex;
layout(binding=0) uniform sampler smp;

void main() {
  vec4 color = texture(sampler2D(tex, smp), uv);

  if(color.a == 0.0) {
    discard;
  }

  frag_color = color;
}
@end

@program font vs_font fs_font
