const SolText = @This();

const std = @import("std");
const Build = std.Build;

const Config = @import("Config.zig");

const SolMath = @import("SolMath.zig");
const ShaderBuilder = @import("ShaderBuilder.zig");

module: *Build.Module,

pub fn init(b: *std.Build, config: Config, sol_math: SolMath, shader_builder: ShaderBuilder) !SolText {
    const dep_TrueType = b.dependency("TrueType", .{
        .target = config.target,
        .optimize = config.optimize,
    });

    const text_shaders = try shader_builder.createModule("assets/shaders/text_shaders.glsl");

    const mod = b.addModule("sol_text", .{
        .target = config.target,
        .root_source_file = b.path("src/sol_text/text.zig"),
        .imports = &.{
            .{ .name = "sol", .module = b.modules.get("sol").? },
            .{ .name = "sol_math", .module = sol_math.module },
            .{ .name = "text_shaders", .module = text_shaders },
            .{ .name = "TrueType", .module = dep_TrueType.module("TrueType") },
        },
    });

    return .{
        .module = mod,
    };
}
