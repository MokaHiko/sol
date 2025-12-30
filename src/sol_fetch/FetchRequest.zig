/// FetchRequest holds the thread-safe state of a running request.
///
/// Prefer using the provided accessors (e.g., `isFinished()`, `getData()`)
/// instead of accessing fields directly, to ensure thread safety.
const FetchRequest = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

finished: bool = false,
success: bool = false,
data: []u8 = undefined,

// TODO: Remove
allocator: Allocator,

/// Used only on native platforms.
mtx: ?std.Thread.Mutex,

/// Thread safe check if fetch request has finished.
pub fn isFinished(self: *FetchRequest) bool {
    if (self.mtx) |*mtx| {
        mtx.lock();
        defer mtx.unlock();
        return self.finished;
    }

    return self.finished;
}

/// Thread safe access to fetched data.
///
/// Returns `null` if request is unfinished or paylaod was empty.
pub fn getData(self: *FetchRequest) ?[]u8 {
    if (!self.isFinished()) {
        return null;
    }

    if (self.mtx) |*mtx| {
        mtx.lock();
        defer mtx.unlock();
        return self.data;
    }

    return self.data;
}

/// Thread safe check if request was successful.
pub fn isSuccess(self: *FetchRequest) bool {
    if (self.mtx) |*mtx| {
        mtx.lock();
        defer mtx.unlock();
        return self.success;
    }

    return self.success;
}

pub fn deinit(self: *FetchRequest, allocator: Allocator) void {
    allocator.free(self.data);
    allocator.destroy(self);
}
