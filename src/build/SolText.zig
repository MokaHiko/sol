const SolText = @This();

const std = @import("std");
const Build = std.Build;

const Config = @import("Config.zig");

module: *Build.Module,

pub fn init(b: *std.Build, config: Config) !SolText {
    const dep_TrueType = b.dependency("TrueType", .{
        .target = config.target,
        .optimize = config.optimize,
    });

    const mod = b.addModule("sol_text", .{
        .target = config.target,
        .root_source_file = b.path("src/sol_text/main.zig"),
        .imports = &.{
            .{ .name = "sol", .module = b.modules.get("sol").? },
            .{ .name = "TrueType", .module = dep_TrueType.module("TrueType") },
        },
    });

    return .{
        .module = mod,
    };
}
