const sol = @import("sol");
const gfx = sol.gfx;

const fetch = @import("sol_fetch");

const sol_shape = @import("sol_shape");
const ShapeRenderer = sol_shape.Renderer;

const zstbi = @import("zstbi");

const NumberProvider = struct {
    my_num: i32,

    pub fn init() !NumberProvider {
        return .{ .my_num = 24 };
    }

    pub fn deinit(self: *NumberProvider) void {
        _ = self;
    }
};

const StreamingShapes = struct {
    img: gfx.Image = .{},
    view: gfx.ImageView = .{},

    fetch_request: ?*fetch.Request,
    shape_renderer: *ShapeRenderer,

    pub fn init(shape_renderer: *ShapeRenderer, np: NumberProvider) !StreamingShapes {
        const fetch_request = try fetch.request(sol.allocator, .{
            .method = .GET,
            .uri = "https://picsum.photos/512/512",
        });

        sol.log.debug("MY NUMBER IS : {d}", .{np.my_num});

        return .{
            .fetch_request = fetch_request,
            .shape_renderer = shape_renderer,
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
                    ) catch @panic("Fialed to initialize image view");

                    // Invalidate request.
                    req.deinit(sol.allocator);
                    self.fetch_request = null;
                } else {
                    sol.log.err("Failed to get load image!", .{});
                }
            }
        }

        // Only draw if image has been loaded.
        if (self.img.isValid()) {
            shape.drawRect(3, 0, 3, 3, .{ .image_view = self.view });
            shape.drawCircle(9, 0, 2, .{ .image_view = self.view });
            shape.drawCircle(3, 5, 2, .{ .image_view = self.view });
        }

        shape.drawCircle(-3, 0, 1, .{ .tint = gfx.color.RGBA.red.asU32() });
        shape.drawCircle(3, 8, 1, .{ .tint = gfx.color.RGBA.red.asU32() });
        shape.drawCircle(3, 12, 3, .{ .tint = gfx.color.RGBA.red.asU32() });
        shape.drawRect(3, -6, 3, 3, .{ .tint = gfx.color.RGBA.blue.asU32() });
    }

    pub fn deinit(self: *StreamingShapes) void {
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
            .{ .T = NumberProvider, .opts = .{} },
            .{ .T = StreamingShapes, .opts = .{} },
        },
        .{
            .name = "Streaming + Shapes",
            .width = 1920,
            .height = 1080,
        },
    );

    try app.run();
}
