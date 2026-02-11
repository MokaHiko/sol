const builtin = @import("builtin");

pub const Image = switch (builtin.os.tag) {
    else => @import("sokol/SokolImage.zig"),
};

pub const ImageView = switch (builtin.os.tag) {
    else => @import("sokol/SokolImageView.zig"),
};

pub const Format = enum {
    R8,
    RGBA8,
    RGBA16,
    DEPTH_STENCIL,

    /// Returns the size of the format in bytes.
    pub fn toSize(self: Format) usize {
        switch (self) {
            .R8 => return 1,
            .RGBA8 => return 4,
            .RGBA16 => return 8,
            .DEPTH_STENCIL => return 0,
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
