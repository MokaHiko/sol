const ImageView = @This();

const sokol = @import("sokol");
const sg = sokol.gfx;

const gfx = @import("../gfx.zig");

_view: sg.View = .{},

pub const Options = struct {};

pub fn init(img: gfx.Image, opts: Options) gfx.image.Error!ImageView {
    _ = opts;

    return .{
        ._view = sg.makeView(.{
            .texture = .{
                .image = img._image,
            },
        }),
    };
}

pub fn deinit(self: *ImageView) void {
    sg.destroyView(self._view);
}

/// Returns the native gpu handle of the view as u32.
pub inline fn gpuHandle(self: ImageView) u32 {
    return self._view.id;
}
