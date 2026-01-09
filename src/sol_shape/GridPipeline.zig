const GridPipeline = @This();

const sol = @import("sol");
const sg = sol.gfx_native;

const shaders = @import("shape_shaders");

pip: sg.Pipeline = .{},
bindings: sg.Bindings = .{},

pub fn init() !GridPipeline {
    var desc = sg.PipelineDesc{
        .shader = sg.makeShader(shaders.gridShaderDesc(sg.queryBackend())),
    };

    desc.colors[0].blend = .{
        .enabled = true,

        .src_factor_rgb = .SRC_ALPHA,
        .dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,

        .src_factor_alpha = .ONE,
        .dst_factor_alpha = .ONE_MINUS_SRC_ALPHA,

        .op_alpha = .ADD,
    };

    return .{ .pip = sg.makePipeline(desc) };
}

pub fn deinit(self: GridPipeline) void {
    sg.destroyPipeline(self.pip);
}
