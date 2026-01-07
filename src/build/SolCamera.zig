const SolCamera = @This();

const std = @import("std");
const Build = std.Build;

const Config = @import("Config.zig");

const Sol = @import("Sol.zig");
const SolMath = @import("SolMath.zig");

module: *Build.Module,

pub fn init(b: *std.Build, config: Config, sol: Sol, sol_math: SolMath) !SolCamera {
    const mod = b.addModule("sol_camera", .{
        .target = config.target,
        .root_source_file = b.path("src/sol_camera/camera.zig"),
        .imports = &.{
            .{ .name = "sol", .module = sol.module },
            .{ .name = "sol_math", .module = sol_math.module },
        },
    });

    return .{ .module = mod };
}
