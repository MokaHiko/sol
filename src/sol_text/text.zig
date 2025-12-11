const Self = @This();

const sol = @import("sol");

pub const Font = @import("Font.zig");
pub const FontAtlas = @import("FontAtlas.zig");

pub const TextMesh = @import("TextMesh.zig");

const text_shaders = @import("text_shaders");

const math = @import("sol_math");
const Mat4 = math.Mat4;
const Vec3 = math.Vec3;

const sg = sol.sg;

var pip: sg.Pipeline = .{};
var bindings: sg.Bindings = .{};

pub fn init() !void {
    Self.pipeline = sg.makePipeline(.{
        .shader = sg.makeShader(text_shaders.fontShaderDesc(sg.queryBackend())),
        .index_type = .UINT16,
    });
}

pub fn draw(x: i32, y: i32, text_mesh: TextMesh, atlas: FontAtlas) void {
    sg.applyPipeline(pip);

    const window_width: f32 = @floatFromInt(sol.windowWidth());
    const window_height: f32 = @floatFromInt(sol.windowHeight());

    const proj = Mat4.ortho_rh(0, window_width, 0, window_height, 0.01, 1);

    const px: f32 = @floatFromInt(x);
    const py: f32 = @floatFromInt(y);
    const translate = Mat4.translate(Vec3.new(px, py, 0));

    const mvp = proj.mul(translate);
    _ = mvp;

    bindings.vertex_buffers[0] = text_mesh.vb;
    bindings.index_buffer = text_mesh.ib;

    _ = atlas;
    // bindings.views[text_shaders.VIEW_tex] = atlas.view;
    sg.applyBindings(bindings);
}

pub fn deinit() !void {
    sg.destroyPipeline(Self.pip);
}
