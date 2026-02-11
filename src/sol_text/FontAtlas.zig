const FontAtlas = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

const sol = @import("sol");
const image = sol.gfx.image;

const Image = image.Image;
const Font = @import("Font.zig");

atlas: Image = .{},
view: sol.gfx_native.View,

pub fn init(allocator: Allocator, font: Font) !FontAtlas {
    const atlas_w = font._rectPacker._opts.max_width;
    const atlas_h = font._rectPacker._opts.max_height;

    const format: image.Format = .R8;
    const format_size = format.toSize();

    const area: usize = @as(usize, @intCast(atlas_w)) * atlas_h;
    var staging = try allocator.alloc(u8, area * format_size);
    defer allocator.free(staging);
    @memset(staging, 0);

    var rect_src = font._buffer.items;
    var src_offset: usize = 0;
    for (font._rects) |rect| {
        const copy_len = rect.w * rect.h * format_size;

        // Update src to current rect slice
        rect_src = font._buffer.items[src_offset .. src_offset + copy_len];

        // Copy by row reversed to account for y down
        var it: usize = 0;
        var rit: usize = rect.h - 1;
        while (it < rect.h) : (it += 1) {
            const rect_offset = rect.w * rit;

            const dst_offset = (atlas_w * (rect.y + it) + rect.x) * format_size;
            @memcpy(staging[dst_offset .. dst_offset + rect.w], rect_src[rect_offset .. rect_offset + rect.w]);

            if (rit == 0) break;
            rit -= 1;
        }

        src_offset = src_offset + copy_len;
    }

    const atlas = try Image.init(
        staging,
        atlas_w,
        atlas_h,
        .R8,
        .{
            .immutable = false,
        },
    );

    const view = sol.gfx_native.makeView(.{
        .texture = .{
            .image = .{ .id = atlas.gpuHandle() },
        },
    });

    return .{ .atlas = atlas, .view = view };
}

pub fn deinit(self: *FontAtlas) void {
    self.atlas.deinit();
}
