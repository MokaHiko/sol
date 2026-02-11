const SolFetch = @This();

const std = @import("std");
const Build = std.Build;

const Config = @import("Config.zig");
const Sol = @import("Sol.zig");

module: *Build.Module,

pub fn init(b: *std.Build, config: Config, sol: Sol) !SolFetch {
    const mod = b.addModule("sol_fetch", .{
        .target = config.target,
        .root_source_file = b.path("src/sol_fetch/fetch.zig"),
        .imports = &.{
            .{ .name = "sol", .module = sol.module },
        },
    });

    if (config.target.result.cpu.arch.isWasm()) {
        const emsdk_incl_path = sol.dep_emsdk.path("upstream/emscripten/cache/sysroot/include");
        mod.addIncludePath(emsdk_incl_path);
    }

    return .{ .module = mod };
}
