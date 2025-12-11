// Font
@vs vs_font
in vec2 in_pos;
in vec2 in_uv;

out vec2 uv;

layout(binding=0) uniform font_properties {
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

layout(binding=1) uniform texture2D tex;
layout(binding=1) uniform sampler smp;

void main() {
  vec4 color = texture(sampler2D(tex, smp), uv);

  if(color.a == 0.0) {
    discard;
  }

  frag_color = color;
}
@end

@program font vs_font fs_font
