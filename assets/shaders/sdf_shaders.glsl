@vs vs_sdf

in vec3 position;
in vec4 color;

layout(binding=0) uniform scene_matrices {
  mat4 mvp;
};

out vec3 v_color;

void main() {
  v_color = color.rgb;
  gl_Position = mvp * vec4(position, 1.0);
}

@end

@fs fs_sdf
// @include_block sdf

in vec3 v_color;
// in flat uint sdf_type;

// layout(binding=1) uniform texture2D tex;
// layout(binding=1) uniform sampler smp;
//
// layout(binding=2) uniform sdf_material {
//   vec4 tint;
// };

out vec4 frag_color;

void main() {
  frag_color = vec4(v_color, 1.0);
}

@end

@program sdf vs_sdf fs_sdf
