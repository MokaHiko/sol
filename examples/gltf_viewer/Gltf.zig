const Gltf = @This();

const std = @import("std");

const Node = struct {
    name: ?[]const u8 = null,
    children: ?u32 = null,

    // TODO: Only one must be present
    matrix: ?[16]f32 = null,
    TRS: ?[16]f32 = null,
};

asset: struct {
    version: []u8,
    minVersion: ?[]const u8 = null,
    generator: ?[]const u8 = null,
    copyright: ?[]const u8 = null,
},

scene: ?u32 = null,
scenes: ?[]struct {
    name: []const u8,
    nodes: []u32,
},

buffers: ?[]struct {
    byteLength: u32,
    uri: []const u8,
} = null,

bufferViews: ?[]struct {
    buffer: u32,
    byteLength: u32,
    byteOffset: u32,
} = null,

pub const Handedness = enum {
    Right,
    Left,
};

pub const LoadOptions = struct {
    handedness: Handedness = .Right,
};

pub fn loadFromFile() !Gltf {

    // TODO: Check if gltf has minVersion and if minVersin is supported
    return .{};
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const allocator = gpa.allocator();

    const gltf_json = try std.json.parseFromSlice(
        Gltf,
        allocator,
        @embedFile("DamagedHelmet/glTF/DamagedHelmet.gltf"),
        .{
            .ignore_unknown_fields = true,
        },
    );
    defer gltf_json.deinit();

    if (gltf_json.value.buffers) |buffers| {
        std.log.debug("{s}", .{buffers[0].uri});
    }
}
