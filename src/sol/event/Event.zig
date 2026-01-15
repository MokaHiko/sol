const Event = @This();

pub const State = enum {
    Default,
    Ignored,
    Handled,
};

const Data = union {
    ext: *anyopaque,
    imm: struct { u32, u32 },
    i32: i32,
};

state: State,
id: u64,
data: Data,

///
/// comptime EventId: type - Event Enum
///
pub fn make(comptime EventId: anytype, opts: Data) Event {
    return .{
        .id = @intFromEnum(EventId),
        .state = .Default,
        .data = opts,
    };
}
