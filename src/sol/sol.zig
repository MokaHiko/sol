const use_docking = @import("build_options").docking;
const ig = if (use_docking) @import("cimgui_docking") else @import("cimgui");
const sokol = @import("sokol");
const slog = sokol.log;
const sapp = sokol.app;
const sglue = sokol.glue;
const simgui = sokol.imgui;

const state = struct {
    var pass_action: sg.PassAction = .{};
    var show_first_window: bool = true;
    var show_second_window: bool = true;
};

const std = @import("std");
const builtin = @import("builtin");

// API
pub const fs = @import("io/file.zig");
pub const gfx = @import("gfx/gfx.zig");
pub const log = @import("logging/logger.zig").Logger(.{
    .level = .Debug,
    .prefix = "[" ++ @typeName(@This()) ++ "] ",
});

var gpa = @import("std").heap.GeneralPurposeAllocator(.{}).init;
pub const allocator = switch (builtin.cpu.arch) {
    .wasm32, .wasm64 => std.heap.c_allocator,
    else => blk: {
        break :blk gpa.allocator();
    },
};

// TODO: Remove, Exposed for now until gfx is wrapped
pub const sg = sokol.gfx;

/// Window fns
pub fn windowWidth() i32 {
    return sapp.width();
}

pub fn windowHeight() i32 {
    return sapp.height();
}

pub fn app_init() !void {
    // initialize sokol-gfx
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });
    // initialize sokol-imgui
    simgui.setup(.{
        .logger = .{ .func = slog.func },
    });
    if (use_docking) {
        ig.igGetIO().*.ConfigFlags |= ig.ImGuiConfigFlags_DockingEnable;
    }

    // initial clear color
    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0.0, .g = 0.5, .b = 1.0, .a = 1.0 },
    };

    log.trace("Gfx: {s}", .{@tagName(sg.queryBackend())});

    // Gfx
    const limits = sg.queryLimits();
    const features = sg.queryFeatures();
    log.trace(" - max vertex attrs: {d}", .{limits.max_vertex_attrs});
    log.trace(" - max image size: {d} b", .{limits.max_image_size_2d});
    log.trace(" - compute: {s}", .{if (features.compute) "true" else "false"});

    // Fs
    const buffer = try fs.read(allocator, "assets/scripts/app.lua", .{});
    defer allocator.free(buffer);

    log.trace("size: {d}", .{buffer.len});
    log.trace("output: {s}", .{buffer});
}

export fn init() void {
    app_init() catch |e| {
        log.err("{s}", .{@errorName(e)});
    };
}

export fn frame() void {
    // call simgui.newFrame() before any ImGui calls
    simgui.newFrame(.{
        .width = sapp.width(),
        .height = sapp.height(),
        .delta_time = sapp.frameDuration(),
        .dpi_scale = sapp.dpiScale(),
    });

    const backendName: [*c]const u8 = switch (sg.queryBackend()) {
        .D3D11 => "Direct3D11",
        .GLCORE => "OpenGL",
        .GLES3 => "OpenGLES3",
        .METAL_IOS => "Metal iOS",
        .METAL_MACOS => "Metal macOS",
        .METAL_SIMULATOR => "Metal Simulator",
        .WGPU => "WebGPU",
        .DUMMY => "Dummy",
    };

    //=== UI CODE STARTS HERE
    ig.igSetNextWindowPos(.{ .x = 10, .y = 10 }, ig.ImGuiCond_Once);
    ig.igSetNextWindowSize(.{ .x = 400, .y = 100 }, ig.ImGuiCond_Once);
    if (ig.igBegin("Hello Dear ImGui!", &state.show_first_window, ig.ImGuiWindowFlags_None)) {
        _ = ig.igColorEdit3("Background", &state.pass_action.colors[0].clear_value.r, ig.ImGuiColorEditFlags_None);
        _ = ig.igText("Dear ImGui Version: %s", ig.IMGUI_VERSION);
    }
    ig.igEnd();

    ig.igSetNextWindowPos(.{ .x = 50, .y = 120 }, ig.ImGuiCond_Once);
    ig.igSetNextWindowSize(.{ .x = 400, .y = 100 }, ig.ImGuiCond_Once);
    if (ig.igBegin("Another Window", &state.show_second_window, ig.ImGuiWindowFlags_None)) {
        _ = ig.igText("Sokol Backend: %s", backendName);
    }
    ig.igEnd();
    //=== UI CODE ENDS HERE

    // call simgui.render() inside a sokol-gfx pass
    sg.beginPass(.{ .action = state.pass_action, .swapchain = sglue.swapchain() });
    simgui.render();
    sg.endPass();
    sg.commit();
}

export fn cleanup() void {
    simgui.shutdown();
    sg.shutdown();

    _ = switch (builtin.cpu.arch) {
        .wasm32, .wasm64 => std.heap.c_allocator,
        else => gpa.deinit(),
    };
}

export fn event(ev: [*c]const sapp.Event) void {
    // forward input events to sokol-imgui
    _ = simgui.handleEvent(ev.*);
}

pub fn run() !void {
    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = event,
        .window_title = "Sol App",
        .width = 800,
        .height = 600,
        .icon = .{ .sokol_default = true },
        .logger = .{ .func = slog.func },
    });
}
