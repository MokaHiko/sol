const GltfViewer = @This();

const std = @import("std");
const Build = std.Build;

const Config = @import("Config.zig");

const Sol = @import("Sol.zig");
const SolMath = @import("SolMath.zig");
const SolCamera = @import("SolCamera.zig");

const ZStbi = @import("ZStbi.zig");
const Gltf = @import("SolGltf.zig");

const ShaderBuilder = @import("ShaderBuilder.zig");

module: *Build.Module,

pub fn init(
    b: *std.Build,
    config: Config,
    sol: Sol,
    sol_math: SolMath,
    sol_camera: SolCamera,
    sol_gltf: Gltf,
    shader_builder: ShaderBuilder,
    zstbi: ZStbi,
) !GltfViewer {
    const pbr_shaders = try shader_builder.createModule("assets/shaders/pbr_shaders.glsl");

    const mod_main = b.createModule(.{
        .root_source_file = b.path("examples/gltf_viewer/gltf_viewer.zig"),
        .target = config.target,
        .optimize = config.optimize,
        .imports = &.{
            .{ .name = "sol", .module = sol.module },
            .{ .name = "sol_math", .module = sol_math.module },
            .{ .name = "sol_camera", .module = sol_camera.module },
            .{ .name = "sol_gltf", .module = sol_gltf.module },
            .{ .name = "pbr_shaders", .module = pbr_shaders },
            .{ .name = "zstbi", .module = zstbi.module },
        },
    });

    return .{
        .module = mod_main,
    };
}
