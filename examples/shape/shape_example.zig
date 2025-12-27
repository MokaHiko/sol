const sol = @import("sol");
const gfx = sol.gfx;

const shape = @import("sol_shape");
const zstbi = @import("zstbi");

const ExShape = struct {
    icon: gfx.Image,
    icon_view: gfx.ImageView,

    dice: gfx.Image,
    dice_view: gfx.ImageView,

    pub fn init() !ExShape {
        try shape.init();

        zstbi.init(sol.allocator);
        defer zstbi.deinit();

        var icon_data = try zstbi.Image.loadFromMemory(
            @embedFile("icon.png"),
            4,
        );
        defer icon_data.deinit();

        const icon = try gfx.Image.init(
            icon_data.data,
            @intCast(icon_data.width),
            @intCast(icon_data.height),
            .RGBA8,
            .{},
        );

        const icon_view = try gfx.ImageView.init(
            icon,
            .{},
        );

        var dice_data = try zstbi.Image.loadFromMemory(
            @embedFile("dice.png"),
            4,
        );
        defer dice_data.deinit();

        const dice = try gfx.Image.init(
            dice_data.data,
            @intCast(dice_data.width),
            @intCast(dice_data.height),
            .RGBA8,
            .{},
        );

        const dice_view = try gfx.ImageView.init(
            dice,
            .{},
        );

        return .{
            .icon = icon,
            .icon_view = icon_view,
            .dice = dice,
            .dice_view = dice_view,
        };
    }

    pub fn update(self: *ExShape) !void {
        shape.drawCircle(-3, 0, 1, .{ .tint = gfx.color.RGBA.red.asU32() });

        shape.drawRect(3, 0, 3, 3, .{ .image_view = self.icon_view });

        shape.drawCircle(9, 0, 2, .{ .image_view = self.dice_view });

        shape.drawRect(3, -6, 3, 3, .{ .tint = gfx.color.RGBA.blue.asU32() });

        shape.drawCircle(3, 5, 2, .{ .image_view = self.dice_view });

        shape.drawCircle(3, 8, 1, .{ .tint = gfx.color.RGBA.red.asU32() });

        shape.drawCircle(3, 12, 3, .{ .tint = gfx.color.RGBA.red.asU32() });

        shape.frame();
    }

    pub fn deinit(self: *ExShape) void {
        self.icon_view.deinit();
        self.icon.deinit();

        self.dice_view.deinit();
        self.dice.deinit();

        shape.deinit();
    }
};

pub fn main() !void {
    var app = try sol.App(ExShape).create(.{
        .name = "Shapes",
        .width = 1920,
        .height = 1080,
    });

    try app.run();
}
