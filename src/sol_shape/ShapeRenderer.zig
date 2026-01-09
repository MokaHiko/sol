const ShapeRenderer = @This();

const std = @import("std");

const sol = @import("sol");
const sg = sol.gfx_native;

const gfx = sol.gfx;

const math = @import("sol_math");
const Mat4 = math.Mat4;
const Vec3 = math.Vec3;

const shaders = @import("shape_shaders");

const GridPipeline = @import("GridPipeline.zig");
const ShapePipeline = @import("ShapePipeline.zig");

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

pub const Shape = packed struct {
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

pub const DrawOptions = struct {
    tint: u32 = 0xFFFFFFFF,
    image_view: ?gfx.ImageView = null,
};

// Common
linear_sampler: sg.Sampler,
white_image: gfx.Image,
white_image_view: gfx.ImageView,

// Pipelines
grid: GridPipeline,
shape: ShapePipeline,

items: [Limits.max_shapes]Shape = undefined,
len: u16 = 0,

images: [Limits.max_images]gfx.ImageView = undefined,
nimages: u16 = 0,

tints: [Limits.max_shapes]u32 = undefined,
ntints: u16 = 0,

pub fn init() !ShapeRenderer {
    // Init common resources.
    const linear_sampler = sg.makeSampler(.{
        .min_filter = .LINEAR,
        .mag_filter = .LINEAR,
        .wrap_u = .CLAMP_TO_EDGE,
        .wrap_v = .CLAMP_TO_EDGE,
    });

    const white = [4]u8{ 0xFF, 0xFF, 0xFF, 0xFF };
    const white_image = try sol.gfx.Image.init(&white, 1, 1, .RGBA8, .{});
    const white_image_view = try gfx.ImageView.init(white_image, .{});

    const grid_pipeline = try GridPipeline.init();
    const shape_pipeline = try ShapePipeline.init(white_image_view, linear_sampler);

    return .{
        .linear_sampler = linear_sampler,
        .white_image = white_image,
        .white_image_view = white_image_view,
        .grid = grid_pipeline,
        .shape = shape_pipeline,
    };
}

pub fn drawCircle(self: *ShapeRenderer, x: i32, y: i32, r: f32, opts: DrawOptions) void {
    if (self.len > Limits.max_shapes) {
        sol.log.err("Exceeded max circles count {d}!", .{Limits.max_shapes});
        return;
    }

    self.items[self.len] = .{
        .x = @floatFromInt(x),
        .y = @floatFromInt(y),
        .data = .{
            .circle = .{ .r = r },
        },
        .ctx = 0,
        .type = .Circle,
    };

    var tint_found: bool = false;
    for (0..self.ntints) |tint_idx| {
        if (self.tints[tint_idx] == opts.tint) {
            self.items[self.len].ctx = @intCast(tint_idx);
            tint_found = true;
            break;
        }
    }

    if (!tint_found) {
        self.tints[self.ntints] = opts.tint;
        self.items[self.len].ctx = self.ntints;
        self.ntints += 1;
    }

    if (opts.image_view) |img| {
        self.items[self.len].type = .CircleTextured;

        var img_found: bool = false;
        for (0..self.nimages) |img_idx| {
            if (self.images[img_idx].gpuHandle() == img.gpuHandle()) {
                self.items[self.len].ctx = @intCast(img_idx);
                img_found = true;
                break;
            }
        }

        if (!img_found) {
            self.images[self.nimages] = img;
            self.items[self.len].ctx = self.nimages;

            self.nimages += 1;
        }
    }

    self.len += 1;
}

pub fn drawRect(self: *ShapeRenderer, x: i32, y: i32, l: i32, w: i32, opts: DrawOptions) void {
    if (self.len > Limits.max_shapes) {
        sol.log.err("Exceeded max shape count {d}!", .{Limits.max_shapes});
        return;
    }

    self.items[self.len] = .{
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
    for (0..self.ntints) |tint_idx| {
        if (self.tints[tint_idx] == opts.tint) {
            self.items[self.len].ctx = @intCast(tint_idx);
            tint_found = true;
            break;
        }
    }

    if (!tint_found) {
        self.tints[self.ntints] = opts.tint;
        self.items[self.len].ctx = self.ntints;
        self.ntints += 1;
    }

    if (opts.image_view) |img| {
        self.items[self.len].type = .RectTextured;

        var img_found: bool = false;
        for (0..self.nimages) |img_idx| {
            if (self.images[img_idx].gpuHandle() == img.gpuHandle()) {
                self.items[self.len].ctx = @intCast(img_idx);
                img_found = true;
                break;
            }
        }

        if (!img_found) {
            self.images[self.nimages] = img;
            self.items[self.len].ctx = self.nimages;

            self.nimages += 1;
        }
    }

    self.len += 1;
}

pub fn frame(self: *ShapeRenderer) void {
    // TODO: Get camera via DI
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

    // ==============================
    // ========== Grid ==============
    // ==============================
    const inv_view_proj = view_proj.inverse() catch unreachable;
    sg.applyPipeline(self.grid.pip);
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
    if (self.len == 0) {
        return;
    }

    std.sort.insertion(
        Shape,
        self.items[0..self.len],
        {},
        sortByTypeAndContext,
    );

    sg.updateBuffer(self.shape.vbo, sg.asRange(self.items[0..self.len]));

    sg.applyPipeline(self.shape.pip);
    var base_vertex: u32 = 0;
    var instance_count: u32 = 0;

    var lctx: u16 = self.items[0].ctx;
    var ltype: Type = self.items[0].type;

    for (self.items[0..self.len]) |s| {
        if (lctx == s.ctx and ltype == s.type) {
            instance_count += 1;
            continue;
        }

        self.shape.bindings.vertex_buffer_offsets[0] = @intCast(base_vertex * @sizeOf(Shape));

        const px: f32 = @floatFromInt(0);
        const py: f32 = @floatFromInt(0);
        const translate = Mat4.translate(Vec3.new(px, py, 0));

        const mvp = view_proj.mul(translate);
        sg.applyUniforms(shaders.UB_canvas_props, sg.asRange(&mvp));

        switch (ltype) {
            .Circle, .Rect => {
                const color = gfx.color.RGBA.fromU32(self.tints[lctx]);
                sg.applyUniforms(shaders.UB_shape_material, sg.asRange(&color));

                self.shape.bindings.views[shaders.VIEW_tex] = self.white_image_view._view;
            },

            .CircleTextured, .RectTextured => {
                const color = gfx.color.RGBA.fromU32(0xFFFFFFFF);
                sg.applyUniforms(shaders.UB_shape_material, sg.asRange(&color));

                self.shape.bindings.views[shaders.VIEW_tex] = self.images[lctx]._view;
            },

            else => unreachable,
        }

        sg.applyBindings(self.shape.bindings);
        sg.draw(0, 6, instance_count);

        // Update bindings
        lctx = s.ctx;
        ltype = s.type;
        base_vertex += instance_count;
        instance_count = 1;
    }

    // Draw with last bindings
    self.shape.bindings.vertex_buffer_offsets[0] = @intCast(base_vertex * @sizeOf(Shape));

    const px: f32 = @floatFromInt(0);
    const py: f32 = @floatFromInt(0);
    const translate = Mat4.translate(Vec3.new(px, py, 0));

    const mvp = view_proj.mul(translate);
    sg.applyUniforms(shaders.UB_canvas_props, sg.asRange(&mvp));

    switch (ltype) {
        .Circle, .Rect => {
            const color = gfx.color.RGBA.fromU32(self.tints[lctx]);
            sg.applyUniforms(shaders.UB_shape_material, sg.asRange(&color));
            self.shape.bindings.views[shaders.VIEW_tex] = self.white_image_view._view;
        },

        .CircleTextured, .RectTextured => {
            const color = gfx.color.RGBA.fromU32(0xFFFFFFFF);
            sg.applyUniforms(shaders.UB_shape_material, sg.asRange(&color));

            self.shape.bindings.views[shaders.VIEW_tex] = self.images[lctx]._view;
        },

        else => unreachable,
    }

    sg.applyBindings(self.shape.bindings);
    sg.draw(0, 6, instance_count);

    self.len = 0;
    self.nimages = 0;
    self.ntints = 0;
}

pub fn deinit(self: *ShapeRenderer) void {
    self.shape.deinit();
    self.grid.deinit();
}

fn sortByTypeAndContext(_: void, a: Shape, b: Shape) bool {
    const atype: u32 = @intFromEnum(a.type);
    const ahash: u32 = (atype << 16) | a.ctx;

    const btype: u32 = @intFromEnum(b.type);
    const bhash: u32 = (btype << 16) | b.ctx;

    return ahash < bhash;
}
