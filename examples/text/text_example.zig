const sol = @import("sol");
const sol_text = @import("sol_text");

const Font = sol_text.Font;
const FontAtlas = sol_text.FontAtlas;
const TextMesh = sol_text.TextMesh;

const BitmapFonts = struct {
    font: Font,
    font_atlas: FontAtlas,
    text_mesh: TextMesh,

    text: *sol_text.Renderer,

    pub fn init(text_renderer: *sol_text.Renderer) !BitmapFonts {
        const font = try Font.init(sol.allocator, @embedFile("Inter_18pt-Black.ttf"));
        const font_atlas = try FontAtlas.init(sol.allocator, font);
        const text_mesh = try TextMesh.init(sol.allocator, &font, "LoremIpsumDolor!");

        return .{
            .font = font,
            .font_atlas = font_atlas,
            .text_mesh = text_mesh,
            .text = text_renderer,
        };
    }

    pub fn frame(self: *BitmapFonts) void {
        self.text.draw(
            0,
            0,
            self.text_mesh,
            self.font_atlas,
        );
    }

    pub fn deinit(self: *BitmapFonts) void {
        self.text_mesh.deinit();
        self.font_atlas.deinit();
        self.font.deinit(sol.allocator);
    }
};

pub fn main() !void {
    var app = try sol.App.create(
        sol.allocator,
        &[_]sol.App.ModuleDesc{
            sol_text.module,
            .{ .T = BitmapFonts, .opts = .{ .mod_type = .System } },
        },
        .{
            .name = "Bitmap Fonts",
            .width = 600,
            .height = 800,
        },
    );

    try app.run();
}
