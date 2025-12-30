const std = @import("std");
const builtin = @import("builtin");

const Allocator = std.mem.Allocator;

pub const Request = @import("FetchRequest.zig");

const fetch = switch (builtin.cpu.arch) {
    .wasm32, .wasm64 => @import("fetch_emscripten.zig").fetch,
    else => @import("fetch_native.zig").fetch,
};

pub const Method = enum {
    GET,
};

pub const Options = struct {
    uri: []const u8,
    method: Method,
    keep_open: bool = false,
};

pub fn request(gpa: Allocator, opts: Options) !*Request {
    return try fetch(gpa, opts.uri);
}
