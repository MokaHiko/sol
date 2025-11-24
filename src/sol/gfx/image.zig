const builtin = @import("builtin");

pub const Image = switch (builtin.os.tag) {
    else => @import("sokol/SokolImage.zig"),
};

pub const Format = enum {
    RGBA8,

    /// Returns the size of the format in bytes.
    pub fn toSize(self: Format) usize {
        switch (self) {
            .RGBA8 => return 4,
        }
    }
};

pub const Error = error{
    OutOfMemory,

    InvalidResourceHandle,
    UnsupportedFormat,
    FailedToWriteData,
    WriteOverflow,
};

pub const Options = struct {
    immutable: bool = true,
    usage: packed struct {
        storage_image: bool = false,
        color_attachment: bool = false,
        resolve_attachment: bool = false,
        depth_stencil_attachment: bool = false,
    } = .{},
};
