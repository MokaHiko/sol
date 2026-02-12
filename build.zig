const std = @import("std");
const Build = std.Build;
const OptimizeMode = std.builtin.OptimizeMode;
const ResolvedTarget = Build.ResolvedTarget;
const Dependency = Build.Dependency;
const sokol = @import("sokol");
const cimgui = @import("cimgui");

const Config = @import("src/build/Config.zig");
const Tracy = @import("src/build/Tracy.zig");
const ZStbi = @import("src/build/ZStbi.zig");

const Sol = @import("src/build/Sol.zig");
const SolMath = @import("src/build/SolMath.zig");
const ShaderBuilder = @import("src/build/ShaderBuilder.zig");

const SolCamera = @import("src/build/SolCamera.zig");
const SolShape = @import("src/build/SolShape.zig");
const SolText = @import("src/build/SolText.zig");
const SolFetch = @import("src/build/SolFetch.zig");

pub fn build(b: *Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const opt_examples = b.option(bool, "examples", "Build examples") orelse true;

    const config = Config{
        .target = target,
        .optimize = optimize,
    };

    const sol: Sol = try .init(b, config, try .init(b, config));
    const sol_math: SolMath = try .init(b, config);

    // Extra
    const zstbi: ZStbi = try .init(b, config, sol);

    const sol_camera = try SolCamera.init(
        b,
        config,
        sol,
        sol_math,
    );

    const sol_text = try SolText.init(
        b,
        config,
        sol,
        sol_math,
        sol.shader_builder,
    );

    const sol_shape: SolShape = try .init(
        b,
        config,
        sol,
        sol_math,
        sol_camera,
        sol.shader_builder,
    );

    const sol_fetch: SolFetch = try .init(
        b,
        config,
        sol,
    );

    if (opt_examples) {
        const TextExample = @import("src/build/SolTextExample.zig");
        const text_example: TextExample = try .init(
            b,
            config,
            sol,
            sol_math,
            sol_text,
        );

        const ShapeExample = @import("src/build/SolShapeExample.zig");
        const shape_example: ShapeExample = try .init(
            b,
            config,
            sol,
            sol_math,
            sol_camera,
            sol_shape,
            sol_fetch,
            zstbi,
        );

        const GltfViewer = @import("src/build/GltfViewer.zig");
        const gltf_viewer: GltfViewer = try .init(
            b,
            config,
            sol,
            sol_math,
            sol_camera,
            sol.shader_builder,
            zstbi,
        );

        const examples_modules = [_]struct { name: []const u8, mod: *Build.Module }{
            .{ .name = "ex_text", .mod = text_example.module },
            .{ .name = "ex_shape", .mod = shape_example.module },
            .{ .name = "gltf_viewer", .mod = gltf_viewer.module },
        };

        for (examples_modules) |ex| {
            if (target.result.cpu.arch.isWasm()) {
                try buildWasm(b, .{
                    .mod_main = ex.mod,
                    .sol = sol,
                }, ex.name);
            } else {
                try buildNative(b, ex.mod, ex.name);
            }
        }
    }
}

fn buildNative(b: *Build, mod: *Build.Module, name: []const u8) !void {
    const exe = b.addExecutable(.{
        .name = name,
        .root_module = mod,
    });

    b.installArtifact(exe);
    b.step(name, name).dependOn(&b.addRunArtifact(exe).step);
}

const BuildWasmOptions = struct {
    mod_main: *Build.Module,
    sol: Sol,
};

fn buildWasm(b: *Build, opts: BuildWasmOptions, name: []const u8) !void {
    // build the main file into a library, this is because the WASM 'exe'
    // needs to be linked in a separate build step with the Emscripten linker
    const demo = b.addLibrary(.{
        .name = name,
        .root_module = opts.mod_main,
    });

    // create a build step which invokes the Emscripten linker
    const link_step = try sokol.emLinkStep(b, .{
        .lib_main = demo,
        .target = opts.mod_main.resolved_target.?,
        .optimize = opts.mod_main.optimize.?,
        .emsdk = opts.sol.dep_emsdk,
        .use_webgl2 = true,
        .use_emmalloc = true,
        .shell_file_path = opts.sol.shell_file_path,
        .extra_args = &[_][]const u8{ "-sALLOW_MEMORY_GROWTH", "-sFETCH=1" },
    });

    // attach to default target
    b.getInstallStep().dependOn(&link_step.step);

    // special run step to start the web build output via 'emrun'
    const run = sokol.emRunStep(b, .{ .name = name, .emsdk = opts.sol.dep_emsdk });
    run.step.dependOn(&link_step.step);

    b.step(name, name).dependOn(&run.step);
}
