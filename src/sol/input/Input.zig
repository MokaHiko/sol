const Input = @This();

const std = @import("std");

const sokol = @import("sokol");
const slog = sokol.log;
const sapp = sokol.app;

const sol = @import("../sol.zig");
const EventQueue = @import("../event/EventQueue.zig");

pub const Keycode = sapp.Keycode;
pub const key_count: usize = @as(usize, @intFromEnum(sapp.Keycode.MENU)) + 1;

pub const MouseButton = sapp.Mousebutton;
pub const mouse_button_count: usize = @as(usize, @intFromEnum(sapp.Mousebutton.MIDDLE)) + 1;

pub const InputAxis = enum {
    Horizontal,
    Vertical,
};

pub const Events = struct {
    const KeyDown = struct { key: i32 };
    const KeyUp = struct { key: i32 };
    const MouseDown = struct { btn: i32 };
    const MouseUp = struct { btn: i32 };
    const MouseMove = struct { x: f32, y: f32 };
};

pub const EventIds = enum(u64) {
    const hash = std.hash.Wyhash.hash;
    KeyDown = hash(0, @typeName(Events.KeyDown)),
    KeyUp = hash(0, @typeName(Events.KeyUp)),
    MouseDown = hash(0, @typeName(Events.MouseDown)),
    MouseUp = hash(0, @typeName(Events.MouseUp)),
    MouseMove = hash(0, @typeName(Events.MouseMove)),
    _,
};

pub const Float2 = struct { x: f32, y: f32 };

eq: *EventQueue,
keys: [key_count]bool,
mouse_btns: [mouse_button_count]bool,
mouse_pos: Float2,
mouse_delta: Float2,

pub fn init(eq: *EventQueue) !Input {
    var keys: [key_count]bool = undefined;
    @memset(&keys, false);

    var mouse_btns: [mouse_button_count]bool = undefined;
    @memset(&mouse_btns, false);

    return .{
        .eq = eq,
        .keys = keys,
        .mouse_btns = mouse_btns,
        .mouse_pos = .{ .x = 0, .y = 0 },
        .mouse_delta = .{ .x = 0, .y = 0 },
    };
}

pub fn frame(self: *Input) void {
    var iter = self.eq.iter(EventIds);

    while (iter.next()) |it| {
        const id = it.id;
        const ev = it.ev;

        switch (id) {
            .KeyDown => self.keys[@as(usize, @intCast(ev.*.data.int))] = true,
            .KeyUp => self.keys[@as(usize, @intCast(ev.*.data.int))] = false,

            .MouseDown => self.mouse_btns[@as(usize, @intCast(ev.*.data.int))] = true,
            .MouseUp => self.mouse_btns[@as(usize, @intCast(ev.*.data.int))] = false,

            .MouseMove => {
                self.mouse_delta = .{
                    .x = ev.*.data.float2.@"0" - self.mouse_pos.x,
                    .y = ev.*.data.float2.@"1" - self.mouse_pos.y,
                };

                self.mouse_pos = .{
                    .x = ev.*.data.float2.@"0",
                    .y = ev.*.data.float2.@"1",
                };
            },

            else => @panic("Uknown Key Event!"),
        }

        ev.*.state = .Handled;
    }
}

/// Returns whether 'key' is being pressed.
pub fn isKeyDown(self: Input, key: Keycode) bool {
    const idx: usize = @intCast(@intFromEnum(key));
    return self.keys[idx];
}

/// Returns if mouse button was pressed and captures mouse position.
pub fn isMouseButtonDown(self: Input, btn: MouseButton) ?Float2 {
    const idx: usize = @intCast(@intFromEnum(btn));
    if (!self.mouse_btns[idx]) {
        return null;
    }

    return self.mouse_pos;
}

/// Returns current mouse position.
pub fn MousePosition(self: Input) Float2 {
    return self.mouse_pos;
}

/// Returns mouse delta x and y.
pub fn Axis(self: Input, axis: InputAxis) f32 {
    return switch (axis) {
        .Horizontal => self.mouse_delta.x,
        .Vertical => self.mouse_delta.y,
    };
}

pub fn deinit(self: *Input) void {
    _ = self;
}
