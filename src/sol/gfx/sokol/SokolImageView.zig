const ImageView = @This();

const sokol = @import("sokol");
const sg = sokol.gfx;

const gfx = @import("../gfx.zig");

/// Native handle.
view: sg.View = .{},

pub const Options = struct {};

pub fn init(img: gfx.Image, opts: Options) gfx.image.Error!ImageView {
    _ = opts;

    return .{
        .view = sg.makeView(.{
            .texture = .{
                .image = img.native,
            },
        }),
    };
}

pub fn deinit(self: *ImageView) void {
    sg.destroyView(self.view);
}

/// Returns the native gpu handle of the view as u32.
pub inline fn gpuHandle(self: ImageView) sg.View {
    return self.view;
}
