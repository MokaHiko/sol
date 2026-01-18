const std = @import("std");
const Allocator = std.mem.Allocator;

const sol = @import("sol");
const gfx = sol.gfx;

const fetch = @import("sol_fetch");

const sol_shape = @import("sol_shape");
const ShapeRenderer = sol_shape.Renderer;

const zstbi = @import("zstbi");

const ShapeVariant = enum(i32) {
    GreenCircle,
    GradientSquare,
    TexturedCircle,
};

const StreamingShapes = struct {
    gpa: Allocator,
    input: *sol.Input,
    shape_renderer: *ShapeRenderer,

    shape_variants: []ShapeVariant,

    img: gfx.Image = .{},
    view: gfx.ImageView = .{},
    fetch_request: ?*fetch.Request,

    pub fn init(
        gpa: Allocator,
        input: *sol.Input,
        shape_renderer: *ShapeRenderer,
    ) !StreamingShapes {
        const fetch_request = try fetch.request(gpa, .{
            .method = .GET,
            .uri = "https://picsum.photos/512/512",
        });

        var prng: std.Random.DefaultPrng = .init(blk: {
            var seed: u64 = undefined;
            try std.posix.getrandom(std.mem.asBytes(&seed));
            break :blk seed;
        });
        const rand = prng.random();

        var shape_variants = try gpa.alloc(ShapeVariant, 10_000);
        for (0..shape_variants.len) |i| {
            shape_variants[i] = @enumFromInt(rand.intRangeAtMost(
                i32,
                0,
                @intFromEnum(ShapeVariant.TexturedCircle),
            ));
        }

        return .{
            .gpa = gpa,
            .input = input,
            .shape_renderer = shape_renderer,

            .fetch_request = fetch_request,
            .shape_variants = shape_variants,
        };
    }

    pub fn frame(self: *StreamingShapes) void {
        const shape = self.shape_renderer;

        // Check if request is valid and finished.
        if (self.fetch_request) |req| {
            if (req.isFinished()) {
                if (req.isSuccess()) {
                    zstbi.init(sol.allocator);
                    zstbi.setFlipVerticallyOnLoad(true);
                    defer zstbi.deinit();

                    var raw = zstbi.Image.loadFromMemory(
                        req.getData() orelse @panic("Fetch payload was empty!"),
                        4,
                    ) catch @panic("Failed to load image data!");
                    defer raw.deinit();

                    self.img = gfx.Image.init(
                        raw.data,
                        @intCast(raw.width),
                        @intCast(raw.height),
                        .RGBA8,
                        .{},
                    ) catch @panic("Failed to initialize image!");

                    self.view = gfx.ImageView.init(
                        self.img,
                        .{},
                    ) catch @panic("Failed to initialize image view");

                    // Invalidate request.
                    req.deinit(sol.allocator);
                    self.fetch_request = null;
                } else {
                    sol.log.err("Failed to get load image!", .{});
                }
            }
        }

        const s: i32 = @intFromFloat(@sqrt(@as(f32, @floatFromInt(self.shape_variants.len))));
        const shalf: i32 = @divFloor(s, 2);
        const r: i32 = 1;

        var y: i32 = -shalf;
        while (y < shalf) : (y += 1) {
            var x: i32 = -shalf;
            while (x < shalf) : (x += 1) {
                const shape_idx: usize = @intCast((y + shalf) * s + (x + shalf));

                switch (self.shape_variants[shape_idx]) {
                    .GreenCircle => {
                        shape.drawCircle(x * r * 2, y * r * 2, 1, .{
                            .tint = gfx.color.RGBA.green.asU32(),
                        });
                    },
                    .GradientSquare => {
                        const ns: f32 = @floatFromInt(s * 2);
                        const nx: f32 = @floatFromInt(x + s);
                        const ny: f32 = @floatFromInt(y + s);

                        shape.drawRect(x * r * 2, y * r * 2, r, r, .{
                            .tint = gfx.color.RGBA.new(
                                nx / ns,
                                ny / ns,
                                0.0,
                                1.0,
                            ).asU32(),
                        });
                    },
                    .TexturedCircle => {
                        if (self.img.isValid()) {
                            shape.drawCircle(x * r * 2, y * r * 2, 1, .{
                                .image_view = self.view,
                            });
                        }
                    },
                }
            }
        }
    }

    pub fn deinit(self: *StreamingShapes) void {
        self.gpa.free(self.shape_variants);

        // Catch early exit with incomplete fetch
        if (self.fetch_request) |f| {
            f.deinit(sol.allocator);
        }

        self.view.deinit();
        self.img.deinit();
    }
};

pub fn main() !void {
    var app = try sol.App.create(
        sol.allocator,
        &[_]sol.App.ModuleDesc{
            sol_shape.module,
            .{ .T = StreamingShapes, .opts = .{} },
        },
        .{
            .name = "Streaming and Shapes",
            .width = 1920,
            .height = 1080,
        },
    );

    try app.run();
}
