const sol = @import("sol");

pub const Renderer = @import("TextRenderer.zig");

pub const Font = @import("Font.zig");
pub const FontAtlas = @import("FontAtlas.zig");

pub const TextMesh = @import("TextMesh.zig");

pub const module = sol.App.ModuleDesc{
    .T = Renderer,
    .opts = .{},
};
