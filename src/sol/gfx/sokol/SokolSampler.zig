const SokolSampler = @This();

const sokol = @import("sokol");
const sg = sokol.gfx;

pub const Options = struct {};

sampler: sg.Sampler = .{},

pub fn init(opts: Options) !SokolSampler {
    _ = opts;

    return .{ .sampler = sg.makeSampler(.{}) };
}

pub fn deinit(self: SokolSampler) void {
    sg.destroySampler(self.sampler);
}

/// Returns the native gpu handle.
pub inline fn gpuHandle(self: SokolSampler) sg.Sampler {
    return self.sampler;
}
