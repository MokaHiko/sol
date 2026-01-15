const sol = @import("sol");

pub const Renderer = @import("ShapeRenderer.zig");

pub const module = sol.App.ModuleDesc{
    .T = Renderer,
    .opts = .{},
};
