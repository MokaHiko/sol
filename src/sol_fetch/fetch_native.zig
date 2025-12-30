const FetchRequest = @import("FetchRequest.zig");

const std = @import("std");
const Allocator = std.mem.Allocator;

fn fetchWorker(gpa: Allocator, req: *FetchRequest, uri: []const u8) !void {
    var client = std.http.Client{
        .allocator = gpa,
    };
    defer client.deinit();

    var buffer = std.Io.Writer.Allocating.init(gpa);
    defer buffer.deinit();

    const res = try client.fetch(.{
        .location = .{
            .uri = try std.Uri.parse(uri),
        },
        .response_writer = &buffer.writer,
    });

    if (req.mtx) |*mtx| {
        mtx.lock();
        defer mtx.unlock();

        req.*.finished = true;
        switch (res.status) {
            .ok => {
                req.*.success = true;
                req.*.data = try buffer.toOwnedSlice();
            },

            else => req.*.success = false,
        }
    }
}

pub fn fetch(gpa: Allocator, uri: []const u8) !*FetchRequest {
    const request = try gpa.create(FetchRequest);
    request.* = .{
        .allocator = gpa,
        .mtx = std.Thread.Mutex{},
    };

    var fetch_thread = std.Thread.spawn(
        .{},
        fetchWorker,
        .{ gpa, request, uri },
    ) catch {
        try fetchWorker(gpa, request, uri);
        return request;
    };

    fetch_thread.detach();
    return request;
}
