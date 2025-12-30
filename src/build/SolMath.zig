const SolMath = @This();

const std = @import("std");
const Build = std.Build;

const Config = @import("Config.zig");

module: *Build.Module,

pub fn init(b: *std.Build, config: Config) !SolMath {
    const mod = b.addModule("sol_text", .{
        .target = config.target,
        .root_source_file = b.path("src/sol_math/math.zig"),
        .imports = &.{
            .{ .name = "sol", .module = b.modules.get("sol").? },
        },
    });

    return .{
        .module = mod,
    };
}
