const TextRenderer = @This();

const sol = @import("sol");

// Types
pub const Font = @import("Font.zig");
pub const FontAtlas = @import("FontAtlas.zig");
pub const TextMesh = @import("TextMesh.zig");

const text_shaders = @import("text_shaders");

const math = @import("sol_math");
const Mat4 = math.Mat4;
const Vec3 = math.Vec3;

const sg = sol.gfx_native;

pip: sg.Pipeline = .{},
bindings: sg.Bindings = .{},
linear_sampler: sg.Sampler = .{},

pub fn init() !TextRenderer {
    var pip_desc = sg.PipelineDesc{
        .shader = sg.makeShader(text_shaders.fontShaderDesc(sg.queryBackend())),
        .index_type = .UINT16,
    };

    pip_desc.layout.attrs[0].format = .FLOAT2; // Position
    pip_desc.layout.attrs[1].format = .FLOAT2; // UV

    const pip = sg.makePipeline(pip_desc);

    const linear_sampler = sg.makeSampler(.{
        .min_filter = .LINEAR,
        .mag_filter = .LINEAR,
        .wrap_u = .CLAMP_TO_EDGE,
        .wrap_v = .CLAMP_TO_EDGE,
    });

    return .{
        .pip = pip,
        .linear_sampler = linear_sampler,
    };
}

pub fn draw(self: *TextRenderer, x: i32, y: i32, text_mesh: TextMesh, font_atlas: FontAtlas) void {
    sg.applyPipeline(self.pip);

    const window_width: f32 = @floatFromInt(sol.windowWidth());
    const window_height: f32 = @floatFromInt(sol.windowHeight());

    const proj = Mat4.orthoRH(0, window_width, 0, window_height, 0.01, 1);

    const px: f32 = @floatFromInt(x);
    const py: f32 = @floatFromInt(y);
    const translate = Mat4.translate(Vec3.new(px, py, 0));

    const mvp = proj.mul(translate);
    sg.applyUniforms(text_shaders.UB_font_properties, sg.asRange(&mvp));

    self.bindings.vertex_buffers[0] = text_mesh.vb;
    self.bindings.index_buffer = text_mesh.ib;
    self.bindings.views[text_shaders.VIEW_tex] = font_atlas.view;

    self.bindings.samplers[text_shaders.SMP_smp] = self.linear_sampler;
    sg.applyBindings(self.bindings);

    sg.draw(0, text_mesh.char_count * 6, 1);
}

pub fn deinit(self: *TextRenderer) void {
    sg.destroySampler(self.linear_sampler);
    sg.destroyPipeline(self.pip);
}
