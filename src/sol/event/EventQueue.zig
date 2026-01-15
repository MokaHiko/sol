//! Event queue used by entire application and modules.
const EventQueue = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Event = @import("Event.zig");

pub fn Iterator(comptime IdType: type) type {
    return struct {
        const Self = @This();

        events: []Event,
        idx: usize,

        pub fn init(events: []Event) Self {
            return .{ .idx = 0, .events = events };
        }

        pub fn next(self: *Self) ?struct { id: IdType, ev: *Event } {
            // Iterate to next unhandled and relevant event
            var id: IdType = undefined;
            while (self.idx < self.events.len) {
                if (self.events[self.idx].state == .Handled) {
                    self.idx += 1;
                    continue;
                }

                id = @enumFromInt(self.events[self.idx].id);
                switch (id) {
                    else => {},

                    _ => {
                        self.idx += 1;
                        continue;
                    },
                }

                break;
            }

            if (self.idx >= self.events.len) {
                return null;
            }

            return .{ .id = id, .ev = &self.events[self.idx] };
        }
    };
}

queue: ArrayList(Event),
allocator: Allocator,

pub fn init(allocator: Allocator) !EventQueue {
    return .{
        .queue = try ArrayList(Event).initCapacity(
            allocator,
            0,
        ),
        .allocator = allocator,
    };
}

pub fn pushEvent(self: *EventQueue, event: Event) !void {
    try self.queue.append(self.allocator, event);
}

/// Returns an iterator of unhandled events in the queue
pub fn iter(self: *EventQueue, comptime EventType: type) Iterator(EventType) {
    return Iterator(EventType).init(self.queue.items);
}

/// Removes all events from queue.
pub fn flush(self: *EventQueue) void {
    self.queue.clearAndFree(self.allocator);
}

pub fn deinit(self: *EventQueue) void {
    self.queue.deinit(self.allocator);
}
