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

const tracy = sol.tracy;

const Event = @import("event/Event.zig");
const EventQueue = @import("event/EventQueue.zig");

const Input = sol.Input;

pub const Options = struct {
    name: []const u8,
    width: i32,
    height: i32,
};

opts: Options,
allocator: Allocator,

modules: []Module,
event_queue: EventQueue,

module_deps: [][]usize,
module_names: [][:0]const u8,

// TODO: Move to built in renderer plugin
pass_action: sol.gfx_native.PassAction = .{},
show_first_window: bool = true,
show_second_window: bool = true,

pub const ModuleDesc = struct {
    instance_ptr: ?*anyopaque = null,
    T: type,
    opts: Module.Options,
};

// TODO: Move to SokolRenderer and creeate module
pub const Renderer = struct {
    pass_action: sol.gfx_native.PassAction = .{},
    show_first_window: bool = true,
    show_second_window: bool = true,

    pub const Sampler2D = struct { i32 };

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

    pub fn makeSampler(self: *Renderer, desc: struct {}) Sampler2D {
        _ = self;
        _ = desc;
        return .{@intCast(sol.gfx_native.makeSampler(.{}).id)};
    }

    pub fn destroySampler(self: *Renderer, sampler: Sampler2D) void {
        _ = self;
        sol.gfx_native.destroySampler(.{ .id = @intCast(sampler.@"0") });
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
        .{ .T = Allocator, .opts = .{ .scoped = true } },
        .{ .T = EventQueue, .opts = .{} },
        .{ .T = Input, .opts = .{} },
        .{ .T = Renderer, .opts = .{} },
    } ++ requested_modules;

    // Resolve dependencies at comptime
    var mods = try allocator.alloc(Module, mod_descs.len);
    var mod_names = try allocator.alloc([:0]const u8, mod_descs.len);
    var mod_deps = try allocator.alloc([]usize, mod_descs.len);

    inline for (mod_descs, 0..) |mod, mod_idx| {
        mod_names[mod_idx] = @typeName(mod.T);

        if (mod.instance_ptr) |ptr| {
            mods[mod_idx].ptr = ptr;
        }

        const has_init = @hasDecl(mod.T, mod.opts.init_fn_name);

        const Args = if (has_init) std.meta.ArgsTuple(@TypeOf(mod.T.init)) else struct {};
        mods[mod_idx] = comptime Module.init(mod.T, Args, mod.opts);

        if (!has_init) {
            mod_deps[mod_idx] = try allocator.alloc(usize, 0);
            continue;
        }

        // Parse dependencies via 'init' fn arguments
        const init_info = @typeInfo(@TypeOf(mod.T.init)).@"fn";

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
                if (other.T == dep_type) {
                    dep_id = other_idx;
                    break;
                }
            }

            if (dep_id) |didx| {
                if (didx == mod_idx) {
                    @compileError("Plugin cannot depend on itself!");
                }

                mod_deps[mod_idx][param_idx] = didx;
            } else {
                @compileError(@typeName(mod.T) ++ " has unresolved dependency : '" ++ @typeName(dep_type) ++ "'");
            }
        }
    }

    const app = try allocator.create(App);
    app.* = .{
        .opts = opts,
        .allocator = allocator,
        .modules = mods,
        .module_names = mod_names,
        .module_deps = mod_deps,
        .event_queue = try EventQueue.init(allocator),
    };

    // TODO: Get from description and do not hard code
    app.modules[1].ptr = &app.event_queue;
    app.modules[1].owned = false;

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
    const init_zctx = tracy.beginZone(@src(), .{});
    defer {
        init_zctx.end();
        tracy.frameMark();
    }

    const self: *App = @ptrCast(@alignCast(sapp.userdata().?));

    // Allocate and initialize modules
    for (0..self.modules.len) |mod_idx| {
        if (!self.modules[mod_idx].owned) {
            continue;
        }

        self.modules[mod_idx].ptr = try self.modules[mod_idx].createFn(self.allocator);

        sol.log.debug("[{s}]", .{self.module_names[mod_idx]});
        sol.log.debug("\tDeps: ", .{});

        for (self.module_deps[mod_idx]) |didx| {
            sol.log.debug("- \t {s} ", .{self.module_names[didx]});
        }

        // TODO : Create scratch buffer with the size of arguments instead
        const dep = try self.modules[mod_idx].deps.create(
            self.allocator,
            self.modules,
            self.module_deps[mod_idx],
        );
        defer self.modules[mod_idx].deps.destroy(self.allocator, dep);

        if (self.modules[mod_idx].initFn) |init| {
            try init(self.modules[mod_idx].ptr, dep);
        }
    }

    // Initial clear color.
    self.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{
            .r = 242.0 / 255.0,
            .g = 242.0 / 255.0,
            .b = 242.0 / 255.0,
            .a = 1.0,
        },
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
    // Set up profiling
    const frame_zctx = tracy.beginZone(@src(), .{ .name = "Main" });
    defer {
        frame_zctx.end();
        tracy.frameMark();
    }

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
        _ = ig.igText("fps: %.2f", ig.igGetIO().*.Framerate);
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

    self.event_queue.flush();
}

export fn cleanupCallback() void {
    const self: *App = @ptrCast(@alignCast(sapp.userdata().?));

    self.allocator.free(self.module_names);

    for (self.modules) |*mod| {
        mod.deinit(self.allocator);
    }
    self.allocator.free(self.modules);

    for (self.module_deps) |deps| {
        self.allocator.free(deps);
    }
    self.allocator.free(self.module_deps);

    simgui.shutdown();
    sol.gfx_native.shutdown();

    self.event_queue.deinit();
    self.allocator.destroy(self);

    _ = switch (builtin.cpu.arch) {
        .wasm32, .wasm64 => std.heap.c_allocator,
        else => sol.gpa.deinit(),
    };
}

export fn eventCallback(ev: [*c]const sapp.Event) void {
    const self: *App = @ptrCast(@alignCast(sapp.userdata().?));

    // forward input events to sokol-imgui
    _ = simgui.handleEvent(ev.*);

    const event: Event = switch (ev.*.type) {
        .KEY_DOWN => Event.make(Input.EventIds.KeyDown, .{
            .int = @intFromEnum(ev.*.key_code),
        }),

        .KEY_UP => Event.make(Input.EventIds.KeyUp, .{
            .int = @intFromEnum(ev.*.key_code),
        }),

        .MOUSE_DOWN => Event.make(Input.EventIds.MouseDown, .{
            .int = @intFromEnum(ev.*.mouse_button),
        }),

        .MOUSE_UP => Event.make(Input.EventIds.MouseUp, .{
            .int = @intFromEnum(ev.*.mouse_button),
        }),

        .MOUSE_MOVE => Event.make(Input.EventIds.MouseMove, .{
            .float2 = .{ ev.*.mouse_x, ev.*.mouse_y },
        }),

        // Unhandled events
        else => return,
    };

    self.event_queue.pushEvent(event) catch |e| {
        sol.log.err("Failed to queue event; {s}", .{@errorName(e)});
    };
}
