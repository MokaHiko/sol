const SolShapeExample = @This();

const std = @import("std");
const Build = std.Build;

const Config = @import("Config.zig");

const Sol = @import("Sol.zig");
const SolMath = @import("SolMath.zig");
const SolShape = @import("SolShape.zig");

module: *Build.Module,

pub fn init(b: *std.Build, config: Config, sol: Sol, sol_math: SolMath, sol_shape: SolShape) !SolShapeExample {
    const dep_zstbi = b.dependency("zstbi", .{});

    const mod_main = b.createModule(.{
        .root_source_file = b.path("examples/shape/shape_example.zig"),
        .target = config.target,
        .optimize = config.optimize,
        .imports = &.{
            .{ .name = "sol", .module = sol.module },
            .{ .name = "sol_math", .module = sol_math.module },
            .{ .name = "sol_shape", .module = sol_shape.module },
            .{ .name = "zstbi", .module = dep_zstbi.module("root") },
        },
    });

    return .{
        .module = mod_main,
    };
}
