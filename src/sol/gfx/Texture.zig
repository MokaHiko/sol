const Texture = @This();

const gfx = @import("gfx.zig");

view: gfx.ImageView,
sampler: gfx.Sampler,

pub fn init(image: gfx.Image, sampler: gfx.Sampler) !Texture {
    return .{
        .view = try .init(image, .{}),
        .sampler = sampler,
    };
}

pub fn deinit(self: *Texture) void {
    self.view.deinit();
}
