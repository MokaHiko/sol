const SolShapeExample = @This();

const std = @import("std");
const Build = std.Build;

const Config = @import("Config.zig");

const Sol = @import("Sol.zig");
const SolMath = @import("SolMath.zig");
const SolCamera = @import("SolCamera.zig");
const SolShape = @import("SolShape.zig");
const SolFetch = @import("SolFetch.zig");

module: *Build.Module,

pub fn init(
    b: *std.Build,
    config: Config,
    sol: Sol,
    sol_math: SolMath,
    sol_camera: SolCamera,
    sol_shape: SolShape,
    sol_fetch: SolFetch,
) !SolShapeExample {
    const dep_zstbi = b.dependency("zstbi", .{});

    if (config.target.result.cpu.arch.isWasm()) {
        const emsdk_incl_path = sol.dep_emsdk.path("upstream/emscripten/cache/sysroot/include");
        dep_zstbi.module("root").addIncludePath(emsdk_incl_path);
    }

    const mod_main = b.createModule(.{
        .root_source_file = b.path("examples/shape/shape_example.zig"),
        .target = config.target,
        .optimize = config.optimize,
        .imports = &.{
            .{ .name = "sol", .module = sol.module },
            .{ .name = "sol_math", .module = sol_math.module },
            .{ .name = "sol_camera", .module = sol_camera.module },
            .{ .name = "sol_shape", .module = sol_shape.module },
            .{ .name = "sol_fetch", .module = sol_fetch.module },
            .{ .name = "zstbi", .module = dep_zstbi.module("root") },
        },
    });

    if (config.target.result.cpu.arch.isWasm()) {
        const emsdk_incl_path = sol.dep_emsdk.path("upstream/emscripten/cache/sysroot/include");
        mod_main.addIncludePath(emsdk_incl_path);
    }

    return .{ .module = mod_main };
}
