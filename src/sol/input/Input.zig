const Input = @This();

const std = @import("std");

const sokol = @import("sokol");
const slog = sokol.log;
const sapp = sokol.app;

const EventQueue = @import("../event/EventQueue.zig");

pub const Keycode = sapp.Keycode;
pub const key_count: usize = @as(usize, @intFromEnum(sapp.Keycode.MENU)) + 1;

pub const MouseButton = sapp.Mousebutton;
pub const mouse_button_count: usize = @as(usize, @intFromEnum(sapp.Mousebutton.MIDDLE)) + 1;

pub const Events = struct {
    const KeyDown = struct { key: i32 };
    const KeyUp = struct { key: i32 };
    const MouseDown = struct { btn: i32 };
    const MouseUp = struct { btn: i32 };
};

pub const EventIds = enum(u64) {
    KeyDown = std.hash.Wyhash.hash(0, @typeName(Events.KeyDown)),
    KeyUp = std.hash.Wyhash.hash(0, @typeName(Events.KeyUp)),
    MouseDown = std.hash.Wyhash.hash(0, @typeName(Events.MouseDown)),
    MouseUp = std.hash.Wyhash.hash(0, @typeName(Events.MouseUp)),
    _,
};

eq: *EventQueue,
keys: [key_count]bool,
mouse_btns: [mouse_button_count]bool,

pub fn init(eq: *EventQueue) !Input {
    var keys: [key_count]bool = undefined;
    @memset(&keys, false);

    var mouse_btns: [mouse_button_count]bool = undefined;
    @memset(&mouse_btns, false);

    return .{
        .eq = eq,
        .keys = keys,
        .mouse_btns = mouse_btns,
    };
}

pub fn frame(self: *Input) void {
    var iter = self.eq.iter(EventIds);

    while (iter.next()) |it| {
        const id = it.id;
        const ev = it.ev;

        switch (id) {
            .KeyDown => self.keys[@as(usize, @intCast(ev.*.data.i32))] = true,
            .KeyUp => self.keys[@as(usize, @intCast(ev.*.data.i32))] = false,

            .MouseDown => self.mouse_btns[@as(usize, @intCast(ev.*.data.i32))] = true,
            .MouseUp => self.mouse_btns[@as(usize, @intCast(ev.*.data.i32))] = false,

            else => @panic("WTF"),
        }

        ev.*.state = .Handled;
    }
}

pub fn isKeyDown(self: Input, key: Keycode) bool {
    const idx: usize = @intCast(@intFromEnum(key));
    return self.keys[idx];
}

pub fn isMouseButtonDown(self: Input, btn: MouseButton) bool {
    const idx: usize = @intCast(@intFromEnum(btn));
    return self.mouse_btns[idx];
}

pub fn deinit(self: *Input) void {
    _ = self;
}
