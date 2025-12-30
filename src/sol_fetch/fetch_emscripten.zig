const FetchRequest = @import("FetchRequest.zig");

const std = @import("std");
const Allocator = std.mem.Allocator;

const c = @cImport({
    @cInclude("emscripten.h");
    @cInclude("emscripten/fetch.h");
});

export fn downloadSucceeded(em_fetch: [*c]c.emscripten_fetch_t) void {
    var req: *FetchRequest = @ptrCast(@alignCast(em_fetch.*.userData));
    req.finished = true;

    req.data = req.allocator.alloc(u8, @intCast(em_fetch.*.numBytes)) catch {
        req.success = false;
        _ = c.emscripten_fetch_close(em_fetch); // Free and close
        return;
    };

    req.success = true;
    @memcpy(req.data, em_fetch.*.data);
    _ = c.emscripten_fetch_close(em_fetch); // Free and close
}

export fn downloadFailed(em_fetch: [*c]c.emscripten_fetch_t) void {
    const req: *FetchRequest = @ptrCast(@alignCast(em_fetch.*.userData));
    req.finished = true;
    req.success = false;
    _ = c.emscripten_fetch_close(em_fetch); // Free and close
}

pub fn fetch(allocator: Allocator, uri: []const u8) !*FetchRequest {
    const request = try allocator.create(FetchRequest);
    request.* = .{
        .allocator = allocator,
        .mtx = null,
    };

    var attr: c.emscripten_fetch_attr_t = .{};
    c.emscripten_fetch_attr_init(&attr);

    const method: []const u8 = "GET";
    @memcpy(attr.requestMethod[0..method.len], method);

    attr.attributes = c.EMSCRIPTEN_FETCH_LOAD_TO_MEMORY;
    attr.onsuccess = downloadSucceeded;
    attr.onerror = downloadFailed;
    attr.userData = request;

    _ = c.emscripten_fetch(&attr, uri.ptr);
    return request;
}
