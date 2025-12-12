const SolTextExample = @This();

const std = @import("std");
const Build = std.Build;

const Config = @import("Config.zig");

const Sol = @import("Sol.zig");
const SolMath = @import("SolMath.zig");
const SolText = @import("SolText.zig");

module: *Build.Module,

pub fn init(b: *std.Build, config: Config, sol: Sol, sol_math: SolMath, sol_text: SolText) !SolTextExample {
    const mod_main = b.createModule(.{
        .root_source_file = b.path("examples/text/text_example.zig"),
        .target = config.target,
        .optimize = config.optimize,
        .imports = &.{
            .{ .name = "sol", .module = sol.module },
            .{ .name = "sol_math", .module = sol_math.module },
            .{ .name = "sol_text", .module = sol_text.module },
        },
    });

    return .{
        .module = mod_main,
    };
}
