const Texture = @This();
const gfx = @import("gfx.zig");

/// Controls resource ownership and cleanup behavior for a `Texture`.
pub const Options = packed struct {
    /// If `true`, the underlying `gfx.Image` will be destroyed when `deinit` is called.
    destroy_image: bool = true,
    /// If `true`, the `gfx.Sampler` will be destroyed when `deinit` is called.
    destroy_sampler: bool = false,
};

/// The image view used for sampling this texture.
view: gfx.ImageView = .{},
/// The sampler that controls filtering, wrapping, and mip-mapping.
sampler: gfx.Sampler = .{},
/// The underlying GPU image resource.
img: gfx.Image = .{},
/// Ownership and destruction options for this texture.
opts: Options = .{},

/// Creates a `Texture` from an existing `gfx.Image` and `gfx.Sampler`.
///
/// An `ImageView` is automatically created from `image`. Ownership of `image`
/// and `sampler` is governed by `opts` — by default, only the image is
/// destroyed on `deinit`.
///
/// Returns an error if the `ImageView` cannot be initialized.
pub fn init(image: gfx.Image, sampler: gfx.Sampler, opts: Options) !Texture {
    return .{
        .view = try .init(image, .{}),
        .sampler = sampler,
        .img = image,
        .opts = opts,
    };
}

/// Destroys the texture and releases GPU resources according to `opts`.
///
/// The `ImageView` is always destroyed. The `Image` and `Sampler` are
/// destroyed only if `opts.destroy_image` and `opts.destroy_sampler` are
/// `true`, respectively.
pub fn deinit(self: *Texture) void {
    self.view.deinit();
    if (self.opts.destroy_image) self.img.deinit();
    if (self.opts.destroy_sampler) self.sampler.deinit();
}
