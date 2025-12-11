const std = @import("std");
const Build = std.Build;
const OptimizeMode = std.builtin.OptimizeMode;
const ResolvedTarget = Build.ResolvedTarget;
const Dependency = Build.Dependency;
const sokol = @import("sokol");
const cimgui = @import("cimgui");

const Config = @import("src/build/Config.zig");

const SolMath = @import("src/build/SolMath.zig");

const ShaderBuilder = @import("src/build/ShaderBuilder.zig");
const SolText = @import("src/build/SolText.zig");

pub fn build(b: *Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const config = Config{
        .target = target,
        .optimize = optimize,
    };

    const opt_docking = b.option(bool, "docking", "Build with docking support") orelse false;

    // Get the matching Zig module name, C header search path and C library for
    // vanilla imgui vs the imgui docking branch.
    const cimgui_conf = cimgui.getConfig(opt_docking);

    // note that the sokol dependency is built with `.with_sokol_imgui = true`
    const dep_sokol = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
        .with_sokol_imgui = true,
    });

    const dep_cimgui = b.dependency("cimgui", .{
        .target = target,
        .optimize = optimize,
    });

    const dep_ztsbi = b.dependency("zstbi", .{
        .target = target,
        .optimize = optimize,
    });

    // inject the cimgui header search path into the sokol C library compile step
    dep_sokol.artifact("sokol_clib").addIncludePath(dep_cimgui.path(cimgui_conf.include_dir));

    const shader_builder = try ShaderBuilder.init(b, dep_sokol);

    const mod = b.addModule("sol", .{
        .target = target,
        .root_source_file = b.path("src/sol/sol.zig"),
        .imports = &.{
            .{ .name = "sokol", .module = dep_sokol.module("sokol") },
            .{ .name = cimgui_conf.module_name, .module = dep_cimgui.module(cimgui_conf.module_name) },
            .{ .name = "shaders", .module = try shader_builder.createModule("assets/shaders/sol_shaders.glsl") },
            .{ .name = "ztsbi", .module = dep_ztsbi.module("root") },
        },
    });
    const mod_options = b.addOptions();
    mod_options.addOption(bool, "docking", opt_docking);
    mod.addOptions("build_options", mod_options);

    const tlib = b.addLibrary(.{
        .name = "sol",
        .root_module = mod,
    });

    const install_docs = b.addInstallDirectory(.{
        .source_dir = tlib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    const docs_step = b.step("docs", "Generate documentation");
    docs_step.dependOn(&install_docs.step);

    // Core
    const sol_math = try SolMath.init(b, config);

    // Extra
    const sol_text = try SolText.init(
        b,
        config,
        sol_math,
        shader_builder,
    );

    // main module with sokol and cimgui imports
    const mod_main = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "sol", .module = mod },
            .{ .name = "sol_math", .module = sol_math.module },
            .{ .name = "sol_text", .module = sol_text.module },
        },
    });

    // from here on different handling for native vs wasm builds
    if (target.result.cpu.arch.isWasm()) {
        try buildWasm(b, .{
            .mod_main = mod_main,
            .dep_sokol = dep_sokol,
            .dep_cimgui = dep_cimgui,
            .cimgui_clib_name = cimgui_conf.clib_name,
            .dep_zstbi = dep_ztsbi,
        });
    } else {
        try buildNative(b, mod_main);
    }
}

fn buildNative(b: *Build, mod: *Build.Module) !void {
    const exe = b.addExecutable(.{
        .name = "demo",
        .root_module = mod,
    });
    b.installArtifact(exe);
    b.step("run", "Run demo").dependOn(&b.addRunArtifact(exe).step);
}

const BuildWasmOptions = struct {
    mod_main: *Build.Module,
    dep_sokol: *Dependency,
    dep_cimgui: *Dependency,
    cimgui_clib_name: []const u8,
    dep_zstbi: *Dependency,
};

fn buildWasm(b: *Build, opts: BuildWasmOptions) !void {
    // build the main file into a library, this is because the WASM 'exe'
    // needs to be linked in a separate build step with the Emscripten linker
    const demo = b.addLibrary(.{
        .name = "demo",
        .root_module = opts.mod_main,
    });

    // get the Emscripten SDK dependency from the sokol dependency
    const dep_emsdk = opts.dep_sokol.builder.dependency("emsdk", .{});

    // need to inject the Emscripten system header include path into
    // the C libraries otherwise the C/C++ code won't find C stdlib headers
    const emsdk_incl_path = dep_emsdk.path("upstream/emscripten/cache/sysroot/include");
    opts.dep_cimgui.artifact(opts.cimgui_clib_name).addSystemIncludePath(emsdk_incl_path);
    opts.dep_zstbi.module("root").addIncludePath(emsdk_incl_path);

    // all C libraries need to depend on the sokol library, when building for
    // WASM this makes sure that the Emscripten SDK has been setup before
    // C compilation is attempted (since the sokol C library depends on the
    // Emscripten SDK setup step)
    opts.dep_cimgui.artifact(opts.cimgui_clib_name).step.dependOn(&opts.dep_sokol.artifact("sokol_clib").step);

    // create a build step which invokes the Emscripten linker
    const link_step = try sokol.emLinkStep(b, .{
        .lib_main = demo,
        .target = opts.mod_main.resolved_target.?,
        .optimize = opts.mod_main.optimize.?,
        .emsdk = dep_emsdk,
        .use_webgl2 = true,
        .use_emmalloc = true,
        .use_filesystem = true,
        .shell_file_path = opts.dep_sokol.path("src/sokol/web/shell.html"),
        .extra_args = &[_][]const u8{ "-sALLOW_MEMORY_GROWTH", "--preload-file", "assets@/assets" },
    });
    // attach to default target
    b.getInstallStep().dependOn(&link_step.step);

    // special run step to start the web build output via 'emrun'
    const run = sokol.emRunStep(b, .{ .name = "demo", .emsdk = dep_emsdk });
    run.step.dependOn(&link_step.step);
    b.step("run", "Run demo").dependOn(&run.step);
}
