const Fetch = @This();

const std = @import("std");
const builtin = @import("builtin");

const Allocator = std.mem.Allocator;

const sol = @import("sol");

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

pub const Events = struct {
    const RequestComplete = struct { req: Request };
};

pub const EventIds = enum(u64) {
    const hash = std.hash.Wyhash.hash;
    RequestComplete = hash(0, @typeName(Events.RequestComplete)),
    _,
};

gpa: Allocator,

eq: *sol.EventQueue,
requests: std.ArrayList(Request),

pub fn init(gpa: Allocator, eq: *sol.EventQueue) !Fetch {
    return .{
        .gpa = gpa,
        .eq = eq,
        .requests = .initCapacity(gpa, 0),
    };
}

pub fn requestEx(self: *Fetch, opts: Options) !*Request {
    try self.requests.append(
        self.gpa,
        try fetch(self.gpa, opts.uri),
    );
}

pub fn frame(self: *Fetch) void {
    for (self.requests.items) |*req| {
        // TODO: Mark for erase
        if (req.isSuccess()) {
            self.eq.pushEvent(sol.Event.make(
                EventIds.RequestComplete,
                .{ .ext = req },
            ));
        }
    }
}

pub fn request(gpa: Allocator, opts: Options) !*Request {
    return try fetch(gpa, opts.uri);
}

pub const module = sol.App.ModuleDesc{
    .T = Fetch,
    .opts = .{},
};
