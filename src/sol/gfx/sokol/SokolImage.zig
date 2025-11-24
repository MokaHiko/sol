const Self = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

const sokol = @import("sokol");
const sg = sokol.gfx;

const gfx = @import("../gfx.zig");

_image: sg.Image,

/// Inits an new `Image`.
///
/// Returns `gfx.image.Error!Self` on failure. On success, returns an `Image` instance.
///
/// Note: For attachments use `Image.allocate`.
/// Note: For storage images use `Image.allocate` then `Image.writeAll`.
pub fn init(data: []const u8, w: u32, h: u32, format: gfx.image.Format, opts: gfx.image.Options) gfx.image.Error!Self {
    // Images WITHOUT these options cannot be assigned initial data.
    // Note: Must be called with `Image.allocate`.
    if (opts.usage.color_attachment or opts.usage.storage_image) {
        return gfx.image.Error.FailedToWriteData;
    }

    var desc = sg.ImageDesc{
        .width = @intCast(w),
        .height = @intCast(h),
        .pixel_format = asPixelFormat(format),
        .usage = .{
            .color_attachment = opts.usage.color_attachment,
            .depth_stencil_attachment = opts.usage.depth_stencil_attachment,
            .storage_image = opts.usage.storage_image,
            .immutable = opts.immutable,
            .dynamic_update = !opts.immutable,
        },
    };

    // .data[face][mip_level]
    desc.data.subimage[0][0] = sg.asRange(data);
    return .{ ._image = sg.makeImage(desc) };
}

/// Allocates an new `Image`.
///
/// Returns `gfx.image.Error!Self` on failure. On success, returns an `Image` instance.
///
/// Note: may allocate scratch memory using allocator passed for certain image usages.
pub fn allocate(scratch_allocator: Allocator, w: u32, h: u32, format: gfx.image.Format, opts: gfx.image.Options) gfx.image.Error!Self {
    // Images WITHOUT these options must assign initial data and is equivalent to calling init with [w * h * channel]u8 = zeros
    if (!opts.usage.color_attachment and !opts.usage.storage_image and opts.immutable) {
        const data = try scratch_allocator.alloc(u8, w * h * format.toSize());
        defer scratch_allocator.free(data);
        @memset(data, 0);

        return init(data, w, h, format, opts);
    }

    const desc = sg.ImageDesc{
        .width = @intCast(w),
        .height = @intCast(h),
        .pixel_format = asPixelFormat(format),
        .usage = .{
            .color_attachment = opts.usage.color_attachment,
            .depth_stencil_attachment = opts.usage.depth_stencil_attachment,
            .storage_image = opts.usage.storage_image,
            .immutable = opts.immutable,
            .dynamic_update = !opts.immutable,
        },
    };

    return .{ ._image = sg.makeImage(desc) };
}

pub fn isValid(self: Self) bool {
    const state = sg.queryImageState(self._image);
    switch (state) {
        .INVALID, .INITIAL => return false,
        else => return true,
    }
}

/// Returns the allocated capacity of the image in bytes.
pub fn queryCapacity(self: Self) usize {
    if (!self.isValid()) {
        return 0;
    }

    const desc = sg.queryImageDesc(self._image);

    const format = try asFormat(desc.pixel_format);
    const dim_size: usize = @intCast(desc.width * desc.height);

    return dim_size * format.toSize();
}

/// Writes the entire length of `data` to the image.
///
/// Note: `data.len` must be equal to the image's capacity (see `Image.queryCapacity`).
/// Note: The image must have `color_attachment` or `storage_image` usage enabled.
pub inline fn writeAll(self: *Self, data: []const u8) gfx.image.Error!void {
    if (!self.isValid()) {
        return gfx.image.Error.InvalidResourceHandle;
    }

    const desc = sg.queryImageDesc(self._image);

    const format = try asFormat(desc.pixel_format);
    const dim_size: usize = @intCast(desc.width * desc.height);
    const image_size = dim_size * format.toSize();

    if (image_size != data.len) {
        return gfx.image.Error.WriteOverflow;
    }

    var image_data = sg.ImageData{};
    image_data.subimage[0][0] = sg.asRange(data);

    sg.updateImage(self._image, image_data);
}

/// Returns the native gpu handle of the image as u64.
pub inline fn gpuHandle(self: Self) u64 {
    return self._image.id;
}

/// Frees and invalidates image.
pub fn deinit(self: *Self) void {
    sg.destroyImage(self._image);
    self._image = .{ .id = 0 };
}

/// Converts `sol.gfx.ImageFormat` to `sokol.gfx.PixelFormat`.
fn asPixelFormat(format: gfx.image.Format) sg.PixelFormat {
    switch (format) {
        .RGBA8 => return .RGBA8,
    }
}

/// Converts `sokol.gfx.PixelFormat` to `sol.gfx.ImageFormat`.
fn asFormat(format: sg.PixelFormat) gfx.image.Error!gfx.image.Format {
    switch (format) {
        .RGBA8 => return .RGBA8,
        else => return gfx.image.Error.UnsupportedFormat,
    }
}
