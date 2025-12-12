const sol = @import("sol");
const text = @import("sol_text");

const ExTest = struct {
    font: text.Font,
    font_atlas: text.FontAtlas,
    text_mesh: text.TextMesh,

    pub fn init() !ExTest {
        try text.init();

        const font = try text.Font.init(sol.allocator, @embedFile("Inter_18pt-Black.ttf"));
        const font_atlas = try text.FontAtlas.init(sol.allocator, font);
        const text_mesh = try text.TextMesh.init(sol.allocator, &font, "TextRendering!");

        return .{
            .font = font,
            .font_atlas = font_atlas,
            .text_mesh = text_mesh,
        };
    }

    pub fn update(self: *ExTest) !void {
        text.draw(0, 0, self.text_mesh, self.font_atlas);
    }

    pub fn deinit(self: *ExTest) void {
        self.font_atlas.deinit();
        self.text_mesh.deinit();
        self.font.deinit(sol.allocator);

        try text.deinit();
    }
};

pub fn main() !void {
    var app = try sol.App(ExTest).init(.{
        .name = "Texture Rendering",
        .width = 600,
        .height = 800,
    });

    try app.run();
}
