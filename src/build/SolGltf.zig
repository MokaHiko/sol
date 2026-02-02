const Gltf = @This();

const std = @import("std");
const Build = std.Build;

const Config = @import("Config.zig");

const Sol = @import("Sol.zig");

const ZStbi = @import("ZStbi.zig");
const ShaderBuilder = @import("ShaderBuilder.zig");

module: *Build.Module,

pub fn init(
    b: *std.Build,
    config: Config,
    sol: Sol,
    zstbi: ZStbi,
) !Gltf {
    const mod_main = b.createModule(.{
        .root_source_file = b.path("src/sol_gltf/sol_gltf.zig"),
        .target = config.target,
        .optimize = config.optimize,
        .imports = &.{
            .{ .name = "sol", .module = sol.module },
            .{ .name = "zstbi", .module = zstbi.module },
        },
    });

    return .{
        .module = mod_main,
    };
}
