//! Type-erased compile time module interface
//!
//! This module defines a lightweight, allocation-aware module handle that
//! erases the concrete module type behind a set of function pointers.
//!
//! A module type `T` is expected to provide the following interface:
//!
//! ```zig
//! pub fn init() !T
//! pub fn frame(self: *T) !void
//! pub fn deinit(self: *T) void
//! ```
const Module = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

const sol = @import("sol.zig");

pub const Dependencies = struct {
    create: *const fn (
        allocator: Allocator,
        modules: []const Module,
        module_deps: []usize,
    ) error{OutOfMemory}!*anyopaque,

    destroy: *const fn (
        allocator: Allocator,
        ptr: *anyopaque,
    ) void,

    pub fn init(Args: type) Dependencies {
        const arg_info = @typeInfo(Args).@"struct";

        const IDependencies = struct {
            pub fn create(
                allocator: Allocator,
                modules: []const Module,
                module_deps: []usize,
            ) error{OutOfMemory}!*anyopaque {
                var args = try allocator.create(Args);

                std.debug.assert(arg_info.fields.len == module_deps.len);

                inline for (arg_info.fields, 0..) |field, didx| {
                    if (field.type == Allocator) {
                        @field(args, field.name) = allocator;
                        break;
                    }

                    @field(args, field.name) = switch (@typeInfo(field.type)) {
                        .pointer => @ptrCast(@alignCast(modules[module_deps[didx]].ptr)),
                        else => blk: {
                            const ptr: *field.type = @ptrCast(@alignCast(modules[module_deps[didx]].ptr));
                            break :blk ptr.*;
                        },
                    };
                }

                return args;
            }

            pub fn destroy(allocator: Allocator, ptr: *anyopaque) void {
                const args: *Args = @ptrCast(@alignCast(ptr));
                allocator.destroy(args);
            }
        };

        return .{
            .create = IDependencies.create,
            .destroy = IDependencies.destroy,
        };
    }
};

createFn: *const fn (allocator: Allocator) error{OutOfMemory}!*anyopaque,
destroyFn: *const fn (ptr: *anyopaque, allocator: Allocator) void,

initFn: ?*const fn (ptr: *anyopaque, deps: *anyopaque) sol.Error!void,
deinitFn: ?*const fn (ptr: *anyopaque) void,

frameFn: ?*const fn (ptr: *anyopaque) void,

deps: Dependencies,

/// Pointer to the instance of the module.
ptr: *anyopaque,

/// True if ptr was initialized by app.
owned: bool,

pub const Options = struct {
    singleton: bool = false,
    scoped: bool = false,
    owned: bool = true,
    comptime init_fn_name: []const u8 = "init",
    comptime deinit_fn_name: []const u8 = "deinit",
    comptime frame_fn_name: []const u8 = "frame",
};

pub fn init(comptime T: type, comptime Args: type, comptime opts: Options) Module {
    var createFn: *const fn (allocator: Allocator) error{OutOfMemory}!*anyopaque = undefined;
    var destroyFn: *const fn (ptr: *anyopaque, allocator: Allocator) void = undefined;

    var initFn: ?*const fn (ptr: *anyopaque, deps: *anyopaque) sol.Error!void = null;
    var frameFn: ?*const fn (ptr: *anyopaque) void = null;
    var deinitFn: ?*const fn (ptr: *anyopaque) void = null;

    if (opts.owned) {
        const IOwned = struct {
            fn create(allocator: Allocator) error{OutOfMemory}!*anyopaque {
                return try allocator.create(T);
            }

            fn destroy(mod_ptr: *anyopaque, allocator: Allocator) void {
                const module: *T = @ptrCast(@alignCast(mod_ptr));
                allocator.destroy(module);
            }
        };

        createFn = IOwned.create;
        destroyFn = IOwned.destroy;
    }

    const tinfo = @typeInfo(T);
    switch (tinfo) {
        .@"struct" => |s| {
            for (s.decls) |decl| {
                if (std.mem.eql(u8, decl.name, opts.init_fn_name)) {
                    const IInit = struct {
                        fn init(mod_ptr: *anyopaque, args_ptr: *anyopaque) sol.Error!void {
                            const module: *T = @ptrCast(@alignCast(mod_ptr));
                            const args: *Args = @ptrCast(@alignCast(args_ptr));

                            if (@sizeOf(Args) > 0) {
                                module.* = @call(.auto, T.init, args.*) catch |e| {
                                    const err_str = @errorName(e);
                                    @panic(err_str);
                                };
                            } else {
                                module.* = T.init() catch |e| {
                                    const err_str = @errorName(e);
                                    @panic(err_str);
                                };
                            }
                        }
                    };

                    initFn = IInit.init;
                }

                if (std.mem.eql(u8, decl.name, opts.frame_fn_name)) {
                    const IFrame = struct {
                        fn frame(mod_ptr: *anyopaque) void {
                            var module: *T = @ptrCast(@alignCast(mod_ptr));
                            module.frame();
                        }
                    };

                    frameFn = IFrame.frame;
                }

                if (std.mem.eql(u8, decl.name, opts.deinit_fn_name)) {
                    const IDeinit = struct {
                        fn deinit(mod_ptr: *anyopaque) void {
                            var module: *T = @ptrCast(@alignCast(mod_ptr));
                            module.deinit();
                        }
                    };

                    deinitFn = IDeinit.deinit;
                }
            }
        },

        else => @compileError("Module must be of 'Struct'!"),
    }

    return .{
        .ptr = undefined,
        .owned = opts.owned,

        .deps = Module.Dependencies.init(Args),

        .createFn = createFn,
        .destroyFn = destroyFn,

        .initFn = initFn,
        .frameFn = frameFn,
        .deinitFn = deinitFn,
    };
}

pub fn deinit(self: *Module, allocator: Allocator) void {
    if (!self.owned) {
        return;
    }

    if (self.deinitFn) |deinit_fn| {
        deinit_fn(self.ptr);
    }

    self.destroyFn(self.ptr, allocator);
}
