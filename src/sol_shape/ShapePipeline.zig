const ShapePipeline = @This();

const sol = @import("sol");
const gfx = sol.gfx;

const sg = sol.gfx_native;

const shaders = @import("shape_shaders");

const Shape = @import("ShapeRenderer.zig").Shape;
const Type = @import("ShapeRenderer.zig").Type;

const Limits = struct {
    const start_size: u16 = 128;
};

vbo: sg.Buffer = .{},

bindings: sg.Bindings = .{},
pip: sg.Pipeline = .{},

pub fn init(white: gfx.ImageView, linear_sampler: sg.Sampler) !ShapePipeline {
    var desc = sg.PipelineDesc{
        .shader = sg.makeShader(shaders.shapeShaderDesc(sg.queryBackend())),
    };

    desc.colors[0].blend = .{
        .enabled = true,

        .src_factor_rgb = .SRC_ALPHA,
        .dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,

        .src_factor_alpha = .ONE,
        .dst_factor_alpha = .ONE_MINUS_SRC_ALPHA,

        .op_alpha = .ADD,
    };

    desc.layout.attrs[0].buffer_index = 0;
    desc.layout.attrs[0].format = .FLOAT4;
    desc.layout.buffers[0].step_func = .PER_INSTANCE;

    const pip = sg.makePipeline(desc);

    const shape_vbo = sg.makeBuffer(.{
        .usage = .{
            .vertex_buffer = true,
            .immutable = false,
            .dynamic_update = true,
        },
        .size = Limits.start_size * @sizeOf(Shape),
    });

    var bindings: sg.Bindings = .{};
    bindings.vertex_buffers[0] = shape_vbo;

    bindings.views[shaders.VIEW_tex] = white.view;
    bindings.samplers[shaders.SMP_smp] = linear_sampler;

    return .{
        .pip = pip,
        .vbo = shape_vbo,
        .bindings = bindings,
    };
}

pub fn deinit(self: ShapePipeline) void {
    sg.destroyBuffer(self.vbo);
    sg.destroyPipeline(self.pip);
}
