const Tracy = @This();

const std = @import("std");
const Build = std.Build;

const Config = @import("Config.zig");

enabled: bool,
module: *Build.Module,
artifact: *std.Build.Step.Compile,

pub fn init(b: *std.Build, config: Config) !Tracy {
    const opt_tracy =
        b.option(bool, "tracy_enable", "Enable profiling") orelse
        if (config.optimize == .Debug) true else false;

    const tracy = b.dependency("tracy", .{
        .target = config.target,
        .optimize = config.optimize,
        .tracy_enable = opt_tracy,
    });

    return .{
        .enabled = opt_tracy,
        .module = tracy.module("tracy"),
        .artifact = if (opt_tracy) tracy.artifact("tracy") else undefined,
    };
}
