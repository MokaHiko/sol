const std = @import("std");
const Allocator = @import("std").mem.Allocator;

pub const Error = error{};

pub const Options = struct {};

/// Reads an entire file into a newly allocated buffer.
/// The caller owns the returned slice and must free it.
pub fn read(allocator: Allocator, path: []const u8, opts: Options) ![]u8 {
    _ = opts;

    var f = try std.fs.cwd().openFile(
        path,
        .{
            .mode = .read_only,
        },
    );
    defer f.close();

    const stat = try f.stat();

    const buffer = try allocator.alloc(u8, @intCast(stat.size));

    var reader = f.reader(buffer);
    try reader.interface.readSliceAll(buffer);

    return buffer;
}
