const App = @This();

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

const sol = @import("sol.zig");
const Module = @import("Module.zig");

pub const Options = struct {
    name: []const u8,
    width: i32,
    height: i32,
};

opts: Options,
allocator: Allocator,

modules: []Module = undefined,
module_deps: [][]usize = undefined,
module_names: [][]const u8 = undefined,

// TODO: Move to built in renderer plugin
pass_action: sol.gfx_native.PassAction = .{},
show_first_window: bool = true,
show_second_window: bool = true,

pub const ModuleDesc = struct {
    T: type,
    opts: Module.Options,
};

pub const Renderer = struct {
    pass_action: sol.gfx_native.PassAction = .{},
    show_first_window: bool = true,
    show_second_window: bool = true,

    pub fn init() !Renderer {
        // Initialize sokol-gfx.
        sol.gfx_native.setup(.{
            .environment = sglue.environment(),
            .logger = .{ .func = slog.func },
        });

        // Initialize sokol-imgui.
        simgui.setup(.{
            .logger = .{ .func = slog.func },
        });

        if (use_docking) {
            ig.igGetIO().*.ConfigFlags |= ig.ImGuiConfigFlags_DockingEnable;
        }
        return .{};
    }

    pub fn frame(self: *Renderer) void {
        _ = self;
    }

    pub fn deinit(self: *Renderer) void {
        _ = self;
    }
};

pub fn create(allocator: Allocator, requested_modules: []const ModuleDesc, opts: Options) !*App {
    const mod_descs = [_]ModuleDesc{
        // Built-in modules
        .{
            .T = Renderer,
            .opts = .{ .mod_type = .System },
        },
    } ++ requested_modules;

    // Resolve dependencies at comptime
    var mods = try allocator.alloc(Module, mod_descs.len);
    var mod_names = try allocator.alloc([]const u8, mod_descs.len);
    var mod_deps = try allocator.alloc([]usize, mod_descs.len);

    inline for (mod_descs, 0..) |mod, mod_idx| {
        mod_names[mod_idx] = @typeName(mod.T);

        if (!@hasDecl(mod.T, "init")) {
            continue;
        }

        const init_info = @typeInfo(@TypeOf(mod.T.init)).@"fn";

        const Args = std.meta.ArgsTuple(@TypeOf(mod.T.init));

        mods[mod_idx] = switch (mod_descs[mod_idx].opts.mod_type) {
            .Resource => Module.initResource(mod.T, Args, mod.opts),
            .System => Module.initSystem(mod.T, Args, mod.opts),
        };

        // Parse dependencies via 'init' fn arguments
        mod_deps[mod_idx] = try allocator.alloc(usize, init_info.params.len);
        inline for (init_info.params, 0..) |param, param_idx| {
            const param_type = param.type orelse break;

            // Handle ptrs
            const dep_type = switch (@typeInfo(param_type)) {
                .pointer => |p| p.child,
                else => param_type,
            };

            comptime var dep_id: ?usize = null;
            inline for (mod_descs, 0..) |other, other_idx| {
                if (other_idx == mod_idx) {
                    @compileError("Plugin cannot depend on itself!");
                }

                if (other.T == dep_type) {
                    dep_id = other_idx;
                    break;
                }
            }

            mod_deps[mod_idx][param_idx] = dep_id orelse @compileError(
                @typeName(mod.T) ++ " has unresolved dependency : '" ++ @typeName(dep_type) ++ "'",
            );
        }
    }

    const app = try allocator.create(App);
    app.* = .{
        .opts = opts,
        .allocator = allocator,
        .modules = mods,
        .module_deps = mod_deps,
        .module_names = mod_names,
    };

    return app;
}

pub fn run(self: *App) !void {
    sapp.run(.{
        .init_cb = initCallback,
        .frame_cb = frameCallback,
        .cleanup_cb = cleanupCallback,
        .event_cb = eventCallback,
        .window_title = self.opts.name.ptr,
        .width = self.opts.width,
        .height = self.opts.height,
        .icon = .{ .sokol_default = true },
        .logger = .{ .func = slog.func },
        .user_data = self,
    });
}

fn initWError() !void {
    const self: *App = @ptrCast(@alignCast(sapp.userdata().?));

    // Allocate and initialize modules
    for (0..self.modules.len) |mod_idx| {
        self.modules[mod_idx].ptr = try self.modules[mod_idx].createFn(self.allocator);

        sol.log.debug("[{s}]", .{self.module_names[mod_idx]});
        sol.log.debug("\tDeps: ", .{});

        for (self.module_deps[mod_idx]) |didx| {
            sol.log.debug("- \t {s} ", .{self.module_names[didx]});
        }

        const dep = try self.modules[mod_idx].deps.create(
            self.allocator,
            self.modules,
            self.module_deps[mod_idx],
        );
        defer self.modules[mod_idx].deps.destroy(self.allocator, dep);

        try self.modules[mod_idx].initFn(self.modules[mod_idx].ptr, dep);
    }

    // Initial clear color.
    self.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 242.0 / 255.0, .g = 242.0 / 255.0, .b = 242.0 / 255.0, .a = 255.0 },
    };

    sol.log.trace("Gfx: {s}", .{@tagName(sol.gfx_native.queryBackend())});

    // Gfx
    const limits = sol.gfx_native.queryLimits();
    const features = sol.gfx_native.queryFeatures();
    sol.log.trace(" - max vertex attrs: {d}", .{limits.max_vertex_attrs});
    sol.log.trace(" - max image size: {d} b", .{limits.max_image_size_2d});
    sol.log.trace(" - compute: {s}", .{if (features.compute) "true" else "false"});
}

export fn initCallback() void {
    initWError() catch |e| {
        sol.log.err("{s}", .{@errorName(e)});
    };
}

export fn frameCallback() void {
    const self: *App = @ptrCast(@alignCast(sapp.userdata().?));

    // call simgui.newFrame() before any ImGui calls
    simgui.newFrame(.{
        .width = sapp.width(),
        .height = sapp.height(),
        .delta_time = sapp.frameDuration(),
        .dpi_scale = sapp.dpiScale(),
    });

    const backendName: [*c]const u8 = switch (sol.gfx_native.queryBackend()) {
        .D3D11 => "Direct3D11",
        .GLCORE => "OpenGL",
        .GLES3 => "OpenGLES3",
        .METAL_IOS => "Metal iOS",
        .METAL_MACOS => "Metal macOS",
        .METAL_SIMULATOR => "Metal Simulator",
        .WGPU => "WebGPU",
        .DUMMY => "Dummy",
    };

    // ImGui.
    ig.igSetNextWindowPos(.{ .x = 10, .y = 10 }, ig.ImGuiCond_Once);
    ig.igSetNextWindowSize(.{ .x = 400, .y = 100 }, ig.ImGuiCond_Once);
    if (ig.igBegin("Hello Dear ImGui!", &self.show_first_window, ig.ImGuiWindowFlags_None)) {
        _ = ig.igColorEdit3("Background", &self.pass_action.colors[0].clear_value.r, ig.ImGuiColorEditFlags_None);
        _ = ig.igText("Dear ImGui Version: %s", ig.IMGUI_VERSION);
    }
    ig.igEnd();

    ig.igSetNextWindowPos(.{ .x = 50, .y = 120 }, ig.ImGuiCond_Once);
    ig.igSetNextWindowSize(.{ .x = 400, .y = 100 }, ig.ImGuiCond_Once);
    if (ig.igBegin("Profile", &self.show_second_window, ig.ImGuiWindowFlags_None)) {
        _ = ig.igText("Backend: %s", backendName);
        _ = ig.igText("FPS: %.2f", ig.igGetIO().*.Framerate);
        _ = ig.igText("ms: %.2f", 1000.0 / ig.igGetIO().*.Framerate);
    }
    ig.igEnd();

    // Main pass.
    sol.gfx_native.beginPass(.{ .action = self.pass_action, .swapchain = sglue.swapchain() });

    for (self.modules) |mod| {
        if (mod.frameFn) |frame| {
            frame(mod.ptr);
        }
    }

    simgui.render();
    sol.gfx_native.endPass();
    sol.gfx_native.commit();
}

export fn cleanupCallback() void {
    const self: *App = @ptrCast(@alignCast(sapp.userdata().?));

    for (self.modules) |*mod| {
        mod.deinit(self.allocator);
    }
    self.allocator.free(self.modules);

    for (self.module_deps) |deps| {
        self.allocator.free(deps);
    }
    self.allocator.free(self.module_deps);

    self.allocator.free(self.module_names);

    simgui.shutdown();
    sol.gfx_native.shutdown();

    self.allocator.destroy(self);

    _ = switch (builtin.cpu.arch) {
        .wasm32, .wasm64 => std.heap.c_allocator,
        else => sol.gpa.deinit(),
    };
}

export fn eventCallback(ev: [*c]const sapp.Event) void {
    // forward input events to sokol-imgui
    _ = simgui.handleEvent(ev.*);
}
