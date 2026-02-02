const ZStbi = @This();

const std = @import("std");
const Build = std.Build;

const Sol = @import("Sol.zig");
const Config = @import("Config.zig");

module: *Build.Module,

pub fn init(b: *std.Build, config: Config, sol: Sol) !ZStbi {
    const dep_zstbi = b.dependency("zstbi", .{});

    if (config.target.result.cpu.arch.isWasm()) {
        const emsdk_incl_path = sol.dep_emsdk.path("upstream/emscripten/cache/sysroot/include");
        dep_zstbi.module("root").addIncludePath(emsdk_incl_path);
    }

    return .{ .module = dep_zstbi.module("root") };
}
