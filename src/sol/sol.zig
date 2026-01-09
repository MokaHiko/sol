const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const use_docking = @import("build_options").docking;
const ig = if (use_docking) @import("cimgui_docking") else @import("cimgui");
const sokol = @import("sokol");
const slog = sokol.log;
const sapp = sokol.app;
const sglue = sokol.glue;
const simgui = sokol.imgui;

pub var gpa = @import("std").heap.GeneralPurposeAllocator(.{}).init;
pub const allocator = switch (builtin.cpu.arch) {
    .wasm32, .wasm64 => std.heap.c_allocator,
    else => blk: {
        break :blk gpa.allocator();
    },
};

// Built-in API
pub const fs = @import("io/file.zig");
pub const log = @import("logging/logger.zig").Logger(.{ .level = .Debug });

// Temporary alias to the underlying gfx implementation.
// The graphics abstraction layer is still incomplete, so some libraries may need to access
// the raw sokol.gfx API directly.
// TODO: Remove this once sokol is fully wrapped by our abstraction.
pub const gfx_native = sokol.gfx;
pub const gfx = @import("gfx/gfx.zig");

pub const Error = gfx.Error;

pub const App = @import("App.zig");

// Window api
pub fn windowWidth() i32 {
    return sapp.width();
}

pub fn windowHeight() i32 {
    return sapp.height();
}

pub const Options = struct {
    name: []const u8,
    width: i32,
    height: i32,
};
