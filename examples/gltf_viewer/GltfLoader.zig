const Gltf = @import("Gltf.zig");

/// /// JSON object with extension-specific objects.
/// extension: ?std.json.Value = null,
///
/// /// Application-specific data.
/// extras: ?std.json.Value = null,
pub const Handedness = enum {
    Right,
    Left,
};

pub const LoadOptions = struct {
    handedness: Handedness = .Right,
};

pub fn loadFromFile() !Gltf {
    const native_endian = @import("builtin").target.cpu.arch.endian();

    switch (native_endian) {
        .little => {},
        else => @panic("Big Endian machines are unsupported!"),
    }

    // TODO: Check if gltf has minVersion and if minVersin is supported
    return .{};
}
