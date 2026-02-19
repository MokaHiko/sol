const std = @import("std");
const Allocator = std.mem.Allocator;

const sol = @import("sol");
const gfx = sol.gfx;

const sol_fetch = @import("sol_fetch");

const sol_camera = @import("sol_camera");
const MainCamera = sol_camera.MainCamera;

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
    main_camera: *MainCamera,
    shape_renderer: *ShapeRenderer,

    variants: []ShapeVariant,

    fetch_request: ?*sol_fetch.Request,
    texture: ?gfx.Texture = null,

    zoom: f32 = 1.0,

    pub fn init(
        gpa: Allocator,
        input: *sol.Input,
        main_camera: *MainCamera,
        shape_renderer: *ShapeRenderer,
    ) !StreamingShapes {
        const fetch_request = try sol_fetch.request(gpa, .{
            .method = .GET,
            .uri = "https://picsum.photos/512/512",
        });

        var prng: std.Random.DefaultPrng = .init(blk: {
            var seed: u64 = undefined;
            try std.posix.getrandom(std.mem.asBytes(&seed));
            break :blk seed;
        });
        const rand = prng.random();

        var shape_variants = try gpa.alloc(ShapeVariant, 3_000);
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
            .main_camera = main_camera,
            .shape_renderer = shape_renderer,

            .fetch_request = fetch_request,
            .variants = shape_variants,
        };
    }

    pub fn frame(self: *StreamingShapes) void {
        if (self.texture == null) {
            self.texture = self.loadTexture() catch |e| blk: {
                sol.log.err("Error {s}", .{@errorName(e)});
                break :blk null;
            };
        }

        const input = self.input;
        const camera = self.main_camera.camera();
        const shape = self.shape_renderer;

        // camera zoom controls
        if (input.isKeyDown(.LEFT_CONTROL) and input.isKeyDown(.EQUAL)) {
            self.zoom += 0.01;
            camera.setOrthogonal(self.zoom, 0.1, 1.0);
        }

        if (input.isKeyDown(.LEFT_CONTROL) and input.isKeyDown(.MINUS)) {
            self.zoom -= 0.01;
            if (self.zoom <= 0.0) {
                self.zoom = 0.01;
            }

            camera.setOrthogonal(self.zoom, 0.1, 1.0);
        }

        // camera pan controls
        if (input.isKeyDown(.UP)) {
            camera.position = camera.position.add(.new(0.0, 0.1, 0));
        }

        if (input.isKeyDown(.DOWN)) {
            camera.position = camera.position.sub(.new(0.0, 0.1, 0));
        }

        if (input.isKeyDown(.RIGHT)) {
            camera.position = camera.position.add(.new(0.1, 0, 0));
        }

        if (input.isKeyDown(.LEFT)) {
            camera.position = camera.position.sub(.new(0.1, 0, 0));
        }
        const s: i32 = @intFromFloat(@sqrt(@as(f32, @floatFromInt(self.variants.len))));
        const shalf: i32 = @divFloor(s, 2);
        const r: i32 = 1;

        var y: i32 = -shalf;
        while (y < shalf) : (y += 1) {
            var x: i32 = -shalf;
            while (x < shalf) : (x += 1) {
                const shape_idx: usize = @intCast((y + shalf) * s + (x + shalf));
                switch (self.variants[shape_idx]) {
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
                        const texture = self.texture orelse continue;
                        shape.drawCircle(x * r * 2, y * r * 2, 1, .{
                            .image_view = texture.view,
                        });
                    },
                }
            }
        }
    }

    pub fn loadTexture(self: *StreamingShapes) !?gfx.Texture {
        // check state of request
        var req = self.fetch_request orelse return null;
        if (!req.isSuccess()) return null;

        // deinit/free request after use
        defer {
            req.deinit(sol.allocator);
            self.fetch_request = null;
        }

        zstbi.init(sol.allocator);
        zstbi.setFlipVerticallyOnLoad(true);
        defer zstbi.deinit();

        var raw = try zstbi.Image.loadFromMemory(
            req.getData() orelse @panic("Fetch payload was empty!"),
            4,
        );
        defer raw.deinit();

        return try .init(
            try .init(
                raw.data,
                @intCast(raw.width),
                @intCast(raw.height),
                .RGBA8,
                .{},
            ),
            try .init(.{}),
            .{
                .destroy_image = true,
                .destroy_sampler = true,
            },
        );
    }

    pub fn deinit(self: *StreamingShapes) void {
        self.gpa.free(self.variants);

        // Catch early exit with incomplete fetch
        if (self.fetch_request) |f| {
            f.deinit(sol.allocator);
        }

        if (self.texture) |*texture| {
            texture.deinit();
        }
    }
};

pub fn main() !void {
    var app = try sol.App.create(
        sol.allocator,
        &[_]sol.App.ModuleDesc{
            sol_camera.module,
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
