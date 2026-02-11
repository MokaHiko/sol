const RenderAttachment = @This();

const sokol = @import("sokol");
const sg = sokol.gfx;

const gfx = @import("../gfx.zig");
const render_attachment = gfx.render_attachment;

/// Native handle.
view: sg.View = .{},

pub const Options = struct {};

pub fn init(img: gfx.Image, attachment_type: render_attachment.Type) render_attachment.Error!RenderAttachment {
    const native = switch (attachment_type) {
        .Color => sg.makeView(.{
            .color_attachment = .{ .image = img.native },
        }),

        .Depth, .DepthStencil => sg.makeView(.{
            .depth_stencil_attachment = .{ .image = img.native },
        }),
    };

    if (sg.queryViewState(native) != .VALID) {
        return gfx.render_attachment.Error.FailedToCreate;
    }

    return .{ .view = native };
}

pub fn deinit(self: *RenderAttachment) void {
    sg.destroyView(self.view);
}

/// Returns the native gpu handle.
pub inline fn gpuHandle(self: RenderAttachment) sg.View {
    return self.view;
}
