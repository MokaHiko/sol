const Sol = @This();

const std = @import("std");
const Build = std.Build;

const Config = @import("Config.zig");
const cimgui = @import("cimgui");

const Tracy = @import("Tracy.zig");
const ShaderBuilder = @import("ShaderBuilder.zig");

shader_builder: ShaderBuilder,
module: *Build.Module,

dep_emsdk: *Build.Dependency,
shell_file_path: Build.LazyPath,

pub fn init(b: *std.Build, config: Config, tracy: Tracy) !Sol {
    const opt_docking = b.option(bool, "docking", "Build with docking support") orelse false;

    // Get the matching Zig module name, C header search path and C library for
    // vanilla imgui vs the imgui docking branch.
    const cimgui_conf = cimgui.getConfig(opt_docking);

    // note that the sokol dependency is built with `.with_sokol_imgui = true`
    const dep_sokol = b.dependency("sokol", .{
        .target = config.target,
        .optimize = config.optimize,
        .with_sokol_imgui = true,
    });

    const dep_cimgui = b.dependency("cimgui", .{
        .target = config.target,
        .optimize = config.optimize,
    });

    // inject the cimgui header search path into the sokol C library compile step
    dep_sokol.artifact("sokol_clib").addIncludePath(dep_cimgui.path(cimgui_conf.include_dir));

    const shader_builder = try ShaderBuilder.init(b, dep_sokol);

    const mod = b.addModule("sol", .{
        .target = config.target,
        .root_source_file = b.path("src/sol/sol.zig"),
        .imports = &.{
            .{ .name = "sokol", .module = dep_sokol.module("sokol") },
            .{ .name = cimgui_conf.module_name, .module = dep_cimgui.module(cimgui_conf.module_name) },
            .{ .name = "shaders", .module = try shader_builder.createModule("assets/shaders/sol_shaders.glsl") },
            .{ .name = "tracy", .module = tracy.module },
        },
    });

    if (tracy.enabled) {
        mod.link_libcpp = true;
        mod.linkLibrary(tracy.artifact);
    }

    const mod_options = b.addOptions();
    mod_options.addOption(bool, "docking", opt_docking);
    mod.addOptions("build_options", mod_options);

    if (config.target.result.cpu.arch.isWasm()) {
        // get the Emscripten SDK dependency from the sokol dependency
        const dep_emsdk = dep_sokol.builder.dependency("emsdk", .{});

        // need to inject the Emscripten system header include path into
        // the C libraries otherwise the C/C++ code won't find C stdlib headers
        const emsdk_incl_path = dep_emsdk.path("upstream/emscripten/cache/sysroot/include");
        dep_cimgui.artifact(cimgui_conf.clib_name).addSystemIncludePath(emsdk_incl_path);

        // all C libraries need to depend on the sokol library, when building for
        // WASM this makes sure that the Emscripten SDK has been setup before
        // C compilation is attempted (since the sokol C library depends on the
        // Emscripten SDK setup step)
        dep_cimgui.artifact(cimgui_conf.clib_name).step.dependOn(&dep_sokol.artifact("sokol_clib").step);

        return .{
            .module = mod,
            .shader_builder = shader_builder,
            .dep_emsdk = dep_emsdk,
            .shell_file_path = dep_sokol.path("src/sokol/web/shell.html"),
        };
    }

    return .{
        .module = mod,
        .shader_builder = shader_builder,
        .shell_file_path = dep_sokol.path("src/sokol/web/shell.html"),
        .dep_emsdk = undefined,
    };
}
