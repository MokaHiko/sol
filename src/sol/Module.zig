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
        std.debug.assert(arg_info.is_tuple);

        const IDependencies = struct {
            pub fn create(
                allocator: Allocator,
                modules: []const Module,
                module_deps: []usize,
            ) error{OutOfMemory}!*anyopaque {
                var args = try allocator.create(Args);

                std.debug.assert(arg_info.fields.len == module_deps.len);
                inline for (arg_info.fields, 0..) |field, didx| {
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

initFn: *const fn (ptr: *anyopaque, deps: *anyopaque) sol.Error!void,
deinitFn: *const fn (ptr: *anyopaque) void,

frameFn: ?*const fn (ptr: *anyopaque) void,

deps: Dependencies,
ptr: *anyopaque,

pub const Type = enum {
    Resource,
    System,
};

pub const Options = struct {
    mod_type: Type,
    singleton: bool = false,
    scoped: bool = false,
    comptime init_fn_name: []const u8 = "init",
    comptime frame_fn_name: []const u8 = "frame",
};

pub fn initSystem(T: type, Args: type, opts: Options) Module {
    _ = opts;

    const IModule = struct {
        fn create(allocator: Allocator) error{OutOfMemory}!*anyopaque {
            return try allocator.create(T);
        }

        fn destroy(ptr: *anyopaque, allocator: Allocator) void {
            const module: *T = @ptrCast(@alignCast(ptr));
            allocator.destroy(module);
        }

        fn init(ptr: *anyopaque, args_ptr: *anyopaque) sol.Error!void {
            const module: *T = @ptrCast(@alignCast(ptr));
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

        fn frame(ptr: *anyopaque) void {
            var module: *T = @ptrCast(@alignCast(ptr));
            module.frame();
        }

        fn deinit(ptr: *anyopaque) void {
            var module: *T = @ptrCast(@alignCast(ptr));
            module.deinit();
        }
    };

    return .{
        .ptr = undefined,
        .deps = Dependencies.init(Args),

        .createFn = IModule.create,
        .destroyFn = IModule.destroy,

        .initFn = IModule.init,
        .frameFn = IModule.frame,
        .deinitFn = IModule.deinit,
    };
}

pub fn initResource(T: type, Args: type, opts: Options) Module {
    _ = opts;

    const IResource = struct {
        fn create(allocator: Allocator) error{OutOfMemory}!*anyopaque {
            return try allocator.create(T);
        }

        fn destroy(ptr: *anyopaque, allocator: Allocator) void {
            const module: *T = @ptrCast(@alignCast(ptr));
            allocator.destroy(module);
        }

        fn init(ptr: *anyopaque, args_ptr: *anyopaque) sol.Error!void {
            const module: *T = @ptrCast(@alignCast(ptr));
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

        fn deinit(ptr: *anyopaque) void {
            var module: *T = @ptrCast(@alignCast(ptr));
            module.deinit();
        }
    };

    return .{
        .ptr = undefined,
        .deps = Dependencies.init(Args),

        .createFn = IResource.create,
        .destroyFn = IResource.destroy,

        .initFn = IResource.init,
        .frameFn = null,
        .deinitFn = IResource.deinit,
    };
}

pub fn deinit(self: *Module, allocator: Allocator) void {
    self.deinitFn(self.ptr);
    self.destroyFn(self.ptr, allocator);
}
