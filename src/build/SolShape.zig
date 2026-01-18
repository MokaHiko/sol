const SolShape = @This();

const std = @import("std");
const Build = std.Build;

const Config = @import("Config.zig");

const Sol = @import("Sol.zig");
const SolMath = @import("SolMath.zig");
const SolCamera = @import("SolCamera.zig");
const ShaderBuilder = @import("ShaderBuilder.zig");
const Tracy = @import("Tracy.zig");

module: *Build.Module,

pub fn init(
    b: *std.Build,
    config: Config,
    sol: Sol,
    sol_math: SolMath,
    sol_camera: SolCamera,
    shader_builder: ShaderBuilder,
) !SolShape {
    const shape_shaders = try shader_builder.createModule("assets/shaders/shape_shaders.glsl");

    const mod = b.addModule("sol_shape", .{
        .target = config.target,
        .root_source_file = b.path("src/sol_shape/shape.zig"),
        .imports = &.{
            .{ .name = "sol", .module = sol.module },
            .{ .name = "sol_math", .module = sol_math.module },
            .{ .name = "sol_camera", .module = sol_camera.module },
            .{ .name = "shape_shaders", .module = shape_shaders },
        },
    });

    return .{
        .module = mod,
    };
}
