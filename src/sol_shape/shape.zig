const std = @import("std");

const sol = @import("sol");
const gfx = sol.gfx;

const math = @import("sol_math");
const Mat4 = math.Mat4;
const Vec3 = math.Vec3;

const sg = sol.gfx_native;

const Limits = struct {
    const max_shapes: u16 = 128;
    const max_images: u16 = max_shapes;
};

pub const Type = enum(u16) {
    Circle = 0,
    CircleTextured = 1,

    Rect = 2,
    RectTextured = 3,

    Count,
};

const Shape = packed struct {
    x: f32 = 0,
    y: f32 = 0,
    type: Type = .Count,
    ctx: u16 = 0,

    data: packed union {
        circle: packed struct {
            r: f32 = 0,
        },

        rect: packed struct {
            w: u16 = 0,
            l: u16 = 0,
        },
    },
};

var linear_sampler: sg.Sampler = .{};
var white_image: gfx.Image = .{};
var white_image_view: gfx.ImageView = .{};

var grid: struct {
    const Self = @This();

    pip: sg.Pipeline = .{},
    bindings: sg.Bindings = .{},

    pub fn deinit(self: Self) void {
        sg.destroyPipeline(self.pip);
    }
} = .{};

var shape: struct {
    const Self = @This();

    items: [Limits.max_shapes]Shape = undefined,
    len: u16 = 0,

    images: [Limits.max_images]gfx.ImageView = undefined,
    nimages: u16 = 0,

    tints: [Limits.max_shapes]u32 = undefined,
    ntints: u16 = 0,

    shape_vbo: sg.Buffer = .{},

    bindings: sg.Bindings = .{},
    pip: sg.Pipeline = .{},

    pub fn deinit(self: Self) void {
        sg.destroyBuffer(self.shape_vbo);
        sg.destroyPipeline(self.pip);
    }
} = .{};

const shaders = @import("shape_shaders");

pub fn init() !void {
    // Init common
    linear_sampler = sg.makeSampler(.{
        .min_filter = .LINEAR,
        .mag_filter = .LINEAR,
        .wrap_u = .CLAMP_TO_EDGE,
        .wrap_v = .CLAMP_TO_EDGE,
    });

    const white = [4]u8{ 0xFF, 0xFF, 0xFF, 0xFF };
    white_image = try sol.gfx.Image.init(&white, 1, 1, .RGBA8, .{});

    // Init grid
    var grid_desc = sg.PipelineDesc{
        .shader = sg.makeShader(shaders.gridShaderDesc(sg.queryBackend())),
    };

    grid_desc.colors[0].blend = .{
        .enabled = true,

        .src_factor_rgb = .SRC_ALPHA,
        .dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,

        .src_factor_alpha = .ONE,
        .dst_factor_alpha = .ONE_MINUS_SRC_ALPHA,

        .op_alpha = .ADD,
    };

    grid.pip = sg.makePipeline(grid_desc);

    // Init shapes
    var shape_desc = sg.PipelineDesc{
        .shader = sg.makeShader(shaders.shapeShaderDesc(sg.queryBackend())),
    };

    shape_desc.colors[0].blend = .{
        .enabled = true,

        .src_factor_rgb = .SRC_ALPHA,
        .dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,

        .src_factor_alpha = .ONE,
        .dst_factor_alpha = .ONE_MINUS_SRC_ALPHA,

        .op_alpha = .ADD,
    };

    // Shape
    shape_desc.layout.attrs[0].buffer_index = 0;
    shape_desc.layout.attrs[0].format = .FLOAT4;
    shape_desc.layout.buffers[0].step_func = .PER_INSTANCE;

    shape.pip = sg.makePipeline(shape_desc);

    shape.shape_vbo = sg.makeBuffer(.{
        .usage = .{
            .vertex_buffer = true,
            .immutable = false,
            .dynamic_update = true,
        },
        .size = Limits.max_shapes * @sizeOf(Shape),
    });

    shape.bindings.vertex_buffers[0] = shape.shape_vbo;

    white_image_view = try gfx.ImageView.init(white_image, .{});
    shape.bindings.views[shaders.VIEW_tex] = white_image_view._view;
    shape.bindings.samplers[shaders.SMP_smp] = linear_sampler;
}

pub const DrawOptions = struct {
    tint: u32 = 0xFFFFFFFF,
    image_view: ?gfx.ImageView = null,
};

pub fn drawCircle(x: i32, y: i32, r: f32, opts: DrawOptions) void {
    if (shape.len > Limits.max_shapes) {
        // TODO: Flush if reached max
        sol.log.err("Exceeded max circles count {d}!", .{Limits.max_shapes});
        return;
    }

    shape.items[shape.len] = .{
        .x = @floatFromInt(x),
        .y = @floatFromInt(y),
        .data = .{
            .circle = .{ .r = r },
        },
        .ctx = 0,
        .type = .Circle,
    };

    var tint_found: bool = false;
    for (0..shape.ntints) |tint_idx| {
        if (shape.tints[tint_idx] == opts.tint) {
            shape.items[shape.len].ctx = @intCast(tint_idx);
            tint_found = true;
            break;
        }
    }

    if (!tint_found) {
        shape.tints[shape.ntints] = opts.tint;
        shape.items[shape.len].ctx = shape.ntints;
        shape.ntints += 1;
    }

    if (opts.image_view) |img| {
        shape.items[shape.len].type = .CircleTextured;

        var img_found: bool = false;
        for (0..shape.nimages) |img_idx| {
            if (shape.images[img_idx].gpuHandle() == img.gpuHandle()) {
                shape.items[shape.len].ctx = @intCast(img_idx);
                img_found = true;
                break;
            }
        }

        if (!img_found) {
            shape.images[shape.nimages] = img;
            shape.items[shape.len].ctx = shape.nimages;

            shape.nimages += 1;
        }
    }

    shape.len += 1;
}

pub fn drawRect(x: i32, y: i32, l: i32, w: i32, opts: DrawOptions) void {
    if (shape.len > Limits.max_shapes) {
        // TODO: Flush if reached max
        sol.log.err("Exceeded max shape count {d}!", .{Limits.max_shapes});
        return;
    }

    shape.items[shape.len] = .{
        .x = @floatFromInt(x),
        .y = @floatFromInt(y),
        .data = .{
            .rect = .{
                .l = @intCast(l),
                .w = @intCast(w),
            },
        },
        .type = .Rect,
        .ctx = 0,
    };

    var tint_found: bool = false;
    for (0..shape.ntints) |tint_idx| {
        if (shape.tints[tint_idx] == opts.tint) {
            shape.items[shape.len].ctx = @intCast(tint_idx);
            tint_found = true;
            break;
        }
    }

    if (!tint_found) {
        shape.tints[shape.ntints] = opts.tint;
        shape.items[shape.len].ctx = shape.ntints;
        shape.ntints += 1;
    }

    if (opts.image_view) |img| {
        shape.items[shape.len].type = .RectTextured;

        var img_found: bool = false;
        for (0..shape.nimages) |img_idx| {
            if (shape.images[img_idx].gpuHandle() == img.gpuHandle()) {
                shape.items[shape.len].ctx = @intCast(img_idx);
                img_found = true;
                break;
            }
        }

        if (!img_found) {
            shape.images[shape.nimages] = img;
            shape.items[shape.len].ctx = shape.nimages;

            shape.nimages += 1;
        }
    }

    shape.len += 1;
}

pub fn frame() void {
    // ==============================
    // ========== Common ============
    // ==============================
    const camera_pos = Vec3.new(1, 0, 0);
    const zoom = 0.25;

    const window_width: f32 = @floatFromInt(sol.windowWidth());
    const window_height: f32 = @floatFromInt(sol.windowHeight());
    const aspect_ratio: f32 = window_height / window_width;

    const width = 10.0 / zoom;
    const height = width * aspect_ratio;

    const half_width: f32 = width / 2.0;
    const half_height: f32 = height / 2.0;

    const view = Mat4.translate(camera_pos.scale(-1.0));
    var proj = Mat4.ortho_rh(-half_width, half_width, -half_height, half_height, 0.01, 1);
    const view_proj = proj.mul(view);
    const inv_view_proj = view_proj.inverse() catch unreachable;

    // ==============================
    // ========== Grid ==============
    // ==============================
    sg.applyPipeline(grid.pip);
    var props = shaders.GridProps{
        .inv_view_proj = undefined,
        .resolution = .{
            @floatFromInt(sol.windowWidth()),
            @floatFromInt(sol.windowHeight()),
        },
    };

    for (0..16) |idx| {
        const x: usize = idx % 4;
        const y: usize = idx / 4;
        props.inv_view_proj[idx] = inv_view_proj.at(.{ x, y });
    }

    sg.applyUniforms(shaders.UB_grid_props, sg.asRange(&props));
    sg.draw(0, 6, 1);

    // ==============================
    // ========== Shape =============
    // ==============================
    if (shape.len == 0) {
        return;
    }

    std.sort.insertion(
        Shape,
        shape.items[0..shape.len],
        {},
        sortByTypeAndContext,
    );

    sg.updateBuffer(shape.shape_vbo, sg.asRange(shape.items[0..shape.len]));

    sg.applyPipeline(shape.pip);
    var base_vertex: u32 = 0;
    var instance_count: u32 = 0;

    var lctx: u16 = shape.items[0].ctx;
    var ltype: Type = shape.items[0].type;

    for (shape.items[0..shape.len]) |s| {
        if (lctx == s.ctx and ltype == s.type) {
            instance_count += 1;
            continue;
        }

        shape.bindings.vertex_buffer_offsets[0] = @intCast(base_vertex * @sizeOf(Shape));

        const px: f32 = @floatFromInt(0);
        const py: f32 = @floatFromInt(0);
        const translate = Mat4.translate(Vec3.new(px, py, 0));

        const mvp = view_proj.mul(translate);
        sg.applyUniforms(shaders.UB_canvas_props, sg.asRange(&mvp));

        switch (ltype) {
            .Circle, .Rect => {
                const color = gfx.color.RGBA.fromU32(shape.tints[lctx]);
                sg.applyUniforms(shaders.UB_shape_material, sg.asRange(&color));

                shape.bindings.views[shaders.VIEW_tex] = white_image_view._view;
            },

            .CircleTextured, .RectTextured => {
                const color = gfx.color.RGBA.fromU32(0xFFFFFFFF);
                sg.applyUniforms(shaders.UB_shape_material, sg.asRange(&color));

                shape.bindings.views[shaders.VIEW_tex] = shape.images[lctx]._view;
            },

            else => unreachable,
        }

        sg.applyBindings(shape.bindings);
        sg.draw(0, 6, instance_count);

        // Update bindings
        lctx = s.ctx;
        ltype = s.type;
        base_vertex += instance_count;
        instance_count = 1;
    }

    // Draw with last bindings
    shape.bindings.vertex_buffer_offsets[0] = @intCast(base_vertex * @sizeOf(Shape));

    const px: f32 = @floatFromInt(0);
    const py: f32 = @floatFromInt(0);
    const translate = Mat4.translate(Vec3.new(px, py, 0));

    const mvp = view_proj.mul(translate);
    sg.applyUniforms(shaders.UB_canvas_props, sg.asRange(&mvp));

    switch (ltype) {
        .Circle, .Rect => {
            const color = gfx.color.RGBA.fromU32(shape.tints[lctx]);
            sg.applyUniforms(shaders.UB_shape_material, sg.asRange(&color));
            shape.bindings.views[shaders.VIEW_tex] = white_image_view._view;
        },

        .CircleTextured, .RectTextured => {
            const color = gfx.color.RGBA.fromU32(0xFFFFFFFF);
            sg.applyUniforms(shaders.UB_shape_material, sg.asRange(&color));

            shape.bindings.views[shaders.VIEW_tex] = shape.images[lctx]._view;
        },

        else => unreachable,
    }

    sg.applyBindings(shape.bindings);
    sg.draw(0, 6, instance_count);

    shape.len = 0;
    shape.nimages = 0;
    shape.ntints = 0;
}

pub fn deinit() void {
    shape.deinit();

    white_image_view.deinit();
    white_image.deinit();
}

fn sortByTypeAndContext(_: void, a: Shape, b: Shape) bool {
    const atype: u32 = @intFromEnum(a.type);
    const ahash: u32 = (atype << 16) | a.ctx;

    const btype: u32 = @intFromEnum(b.type);
    const bhash: u32 = (btype << 16) | b.ctx;

    return ahash < bhash;
}
