const ShapeRenderer = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

const sol = @import("sol");
const sol_camera = @import("sol_camera");
const sg = sol.gfx_native;

const tracy = sol.tracy;

const gfx = sol.gfx;

const math = @import("sol_math");
const Mat4 = math.Mat4;
const Vec3 = math.Vec3;

const shaders = @import("shape_shaders");

const GridPipeline = @import("GridPipeline.zig");
const ShapePipeline = @import("ShapePipeline.zig");

const Limits = struct {
    const max_shapes: u16 = std.math.maxInt(u16);
};

const Error = error{
    ExceededMaxShapes,
};

///
/// Internally ordered by base type
/// i.e Circle then variants
/// ex. Circle + 1 = CircleTextured
///
/// Variants are infered by function call and only used internally
///
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
main_camera: *sol_camera.MainCamera,

linear_sampler: sg.Sampler,
white_image: gfx.Image,
white_image_view: gfx.ImageView,

// Pipelines
grid_pipeline: GridPipeline,
pipeline: ShapePipeline,

shapes: std.ArrayList(Shape),
views: std.ArrayList(gfx.ImageView),
tints: std.ArrayList(u32),
allocator: Allocator,

pub fn init(allocator: Allocator, main_camera: *sol_camera.MainCamera) !ShapeRenderer {
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
        .main_camera = main_camera,

        .linear_sampler = linear_sampler,
        .white_image = white_image,
        .white_image_view = white_image_view,
        .grid_pipeline = grid_pipeline,
        .pipeline = shape_pipeline,

        .allocator = allocator,
        .views = try .initCapacity(allocator, 0),
        .shapes = try .initCapacity(allocator, 0),
        .tints = try .initCapacity(allocator, 0),
    };
}

pub fn drawCircle(self: *ShapeRenderer, x: i32, y: i32, r: f32, opts: DrawOptions) void {
    const shape: Shape = .{
        .x = @floatFromInt(x),
        .y = @floatFromInt(y),
        .data = .{
            .circle = .{ .r = r },
        },
        .ctx = 0,
        .type = .Circle,
    };

    self.drawShape(shape, opts) catch |e| {
        sol.log.err("{s}", .{@errorName(e)});
    };
}

pub fn drawRect(self: *ShapeRenderer, x: i32, y: i32, l: i32, w: i32, opts: DrawOptions) void {
    const shape: Shape = .{
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

    self.drawShape(shape, opts) catch |e| {
        sol.log.err("{s}", .{@errorName(e)});
    };
}

fn drawShape(
    self: *ShapeRenderer,
    base: Shape,
    opts: DrawOptions,
) !void {
    if (self.shapes.items.len >= Limits.max_shapes) {
        return Error.ExceededMaxShapes;
    }

    var shape: Shape = base;

    var tint_found: bool = false;
    for (self.tints.items, 0..) |tint, i| {
        if (tint == opts.tint) {
            shape.ctx = @intCast(i);
            tint_found = true;
            break;
        }
    }

    if (!tint_found) {
        try self.tints.append(self.allocator, opts.tint);
        shape.ctx = @intCast(self.tints.items.len - 1);
    }

    if (opts.image_view) |view| {
        const type_id: u16 = @intFromEnum(shape.type);
        shape.type = @enumFromInt(type_id + 1);

        var img_found: bool = false;
        for (self.views.items, 0..) |sview, i| {
            if (sview.gpuHandle() == view.gpuHandle()) {
                shape.ctx = @intCast(i);
                img_found = true;
                break;
            }
        }

        if (!img_found) {
            try self.views.append(self.allocator, view);
            shape.ctx = @intCast(self.views.items.len - 1);
        }
    }

    try self.shapes.append(self.allocator, shape);
}

pub fn frame(self: *ShapeRenderer) void {
    const ztx = tracy.beginZone(@src(), .{
        .name = "Shapes",
    });
    defer ztx.end();

    ztx.text("shape count : {d}", .{self.shapes.items.len});

    const camera = self.main_camera.camera();

    // ==============================
    // ========== Grid ==============
    // ==============================
    const inv_view_proj = camera.viewProj().inverse() catch unreachable;
    sg.applyPipeline(self.grid_pipeline.pip);
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

    const shapes = self.shapes.items;
    const tints = self.tints.items;
    const views = self.views.items;

    if (shapes.len == 0) {
        return;
    }

    {
        const ztx_sort = tracy.beginZone(@src(), .{
            .name = "material sort",
        });
        defer ztx_sort.end();

        std.sort.pdq(
            Shape,
            shapes,
            {},
            sortByTypeAndContext,
        );
    }

    // TODO: Move to shape pipeline or shape pipeline here
    // Resize if missing
    const shapes_size = shapes.len * @bitSizeOf(Shape);
    if (sg.queryBufferSize(self.pipeline.vbo) < shapes_size) {
        sg.destroyBuffer(self.pipeline.vbo);

        const shape_vbo = sg.makeBuffer(.{
            .usage = .{
                .vertex_buffer = true,
                .immutable = false,
                .dynamic_update = true,
            },
            .size = shapes_size,
        });

        self.pipeline.vbo = shape_vbo;
        self.pipeline.bindings.vertex_buffers[0] = shape_vbo;
    }

    sg.updateBuffer(self.pipeline.vbo, sg.asRange(shapes));

    sg.applyPipeline(self.pipeline.pip);
    var base_vertex: u32 = 0;
    var instance_count: u32 = 0;

    var lctx: u16 = shapes[0].ctx;
    var ltype: Type = shapes[0].type;

    for (shapes) |shape| {
        if (lctx == shape.ctx and ltype == shape.type) {
            instance_count += 1;
            continue;
        }

        self.pipeline.bindings.vertex_buffer_offsets[0] = @intCast(base_vertex * @sizeOf(Shape));

        const px: f32 = @floatFromInt(0);
        const py: f32 = @floatFromInt(0);
        const translate = Mat4.translate(Vec3.new(px, py, 0));

        const mvp = camera.viewProj().mul(translate);
        sg.applyUniforms(shaders.UB_canvas_props, sg.asRange(&mvp));

        switch (ltype) {
            .Circle, .Rect => {
                const color = gfx.color.RGBA.fromU32(tints[lctx]);
                sg.applyUniforms(shaders.UB_shape_material, sg.asRange(&color));

                self.pipeline.bindings.views[shaders.VIEW_tex] = self.white_image_view._view;
            },

            .CircleTextured, .RectTextured => {
                const color = gfx.color.RGBA.fromU32(0xFFFFFFFF);
                sg.applyUniforms(shaders.UB_shape_material, sg.asRange(&color));

                self.pipeline.bindings.views[shaders.VIEW_tex] = views[lctx]._view;
            },

            else => unreachable,
        }

        sg.applyBindings(self.pipeline.bindings);
        sg.draw(0, 6, instance_count);

        // Update bindings
        lctx = shape.ctx;
        ltype = shape.type;
        base_vertex += instance_count;
        instance_count = 1;
    }

    // Draw with last bindings
    self.pipeline.bindings.vertex_buffer_offsets[0] = @intCast(base_vertex * @sizeOf(Shape));

    const px: f32 = @floatFromInt(0);
    const py: f32 = @floatFromInt(0);
    const translate = Mat4.translate(Vec3.new(px, py, 0));

    const mvp = camera.viewProj().mul(translate);
    sg.applyUniforms(shaders.UB_canvas_props, sg.asRange(&mvp));

    switch (ltype) {
        .Circle, .Rect => {
            const color = gfx.color.RGBA.fromU32(tints[lctx]);
            sg.applyUniforms(shaders.UB_shape_material, sg.asRange(&color));
            self.pipeline.bindings.views[shaders.VIEW_tex] = self.white_image_view._view;
        },

        .CircleTextured, .RectTextured => {
            const color = gfx.color.RGBA.fromU32(0xFFFFFFFF);
            sg.applyUniforms(shaders.UB_shape_material, sg.asRange(&color));

            self.pipeline.bindings.views[shaders.VIEW_tex] = views[lctx]._view;
        },

        else => unreachable,
    }

    sg.applyBindings(self.pipeline.bindings);
    sg.draw(0, 6, instance_count);

    self.shapes.clearRetainingCapacity();
    self.tints.clearRetainingCapacity();
    self.views.clearRetainingCapacity();
}

pub fn deinit(self: *ShapeRenderer) void {
    self.pipeline.deinit();
    self.grid_pipeline.deinit();

    self.shapes.deinit(self.allocator);
    self.tints.deinit(self.allocator);
    self.views.deinit(self.allocator);
}

fn sortByTypeAndContext(_: void, a: Shape, b: Shape) bool {
    const atype: u32 = @intFromEnum(a.type);
    const ahash: u32 = (atype << 16) | a.ctx;

    const btype: u32 = @intFromEnum(b.type);
    const bhash: u32 = (btype << 16) | b.ctx;

    return ahash < bhash;
}
