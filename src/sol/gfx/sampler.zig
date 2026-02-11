const builtin = @import("builtin");

pub const Sampler = switch (builtin.os.tag) {
    else => @import("sokol/SokolSampler.zig"),
};
