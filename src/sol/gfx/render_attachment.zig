const builtin = @import("builtin");

pub const RenderAttachment = switch (builtin.os.tag) {
    else => @import("sokol/SokolRenderAttachment.zig"),
};

pub const Type = enum {
    Color,
    Depth,
    DepthStencil,
};

pub const Error = error{
    FailedToCreate,
};
