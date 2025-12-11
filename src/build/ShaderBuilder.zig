const ShaderBuilder = @This();
const std = @import("std");
const builtin = @import("builtin");
const Build = std.Build;

const sokol = @import("sokol");

b: *Build,
dep_sokol: *Build.Dependency,

pub fn init(b: *Build, dep_sokol: *Build.Dependency) !ShaderBuilder {
    return .{
        .b = b,
        .dep_sokol = dep_sokol,
    };
}

pub fn createModule(self: ShaderBuilder, comptime path: []const u8) !*Build.Module {
    const mod_sokol = self.dep_sokol.module("sokol");
    const dep_shdc = self.dep_sokol.builder.dependency("shdc", .{});

    const file_name = comptime std.fs.path.basename(path);
    const ext_idx = comptime std.mem.indexOfAny(u8, file_name, ".").?;
    const name = file_name[0..ext_idx];

    return sokol.shdc.createModule(self.b, path, mod_sokol, .{
        .shdc_dep = dep_shdc,
        .input = path,
        .output = name ++ ".zig",
        .slang = .{
            .glsl410 = true,
            .glsl300es = true,
            .hlsl4 = true,
            .metal_macos = true,
            .wgsl = true,
        },
    });
}
