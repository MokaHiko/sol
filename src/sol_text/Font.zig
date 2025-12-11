const Font = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

const TrueType = @import("TrueType");

const Rect = @import("Rect.zig");
const RectPacker = @import("RectPacker.zig");

const Errors = error{
    GlyphNotFound,
};

pub const Limits = struct {
    pub const min_char_code = 0x21;
    pub const max_char_code = 0x7E;
    pub const char_code_count = max_char_code - min_char_code;
};

pub const Glyph = struct {
    advance_width: f32 = 0,
    offset_x: f32 = 0,
    offset_y: f32 = 0,
};

_rects: [Limits.char_code_count]Rect,
_glyphs: [Limits.char_code_count]Glyph,
_rectPacker: RectPacker,
_buffer: std.ArrayListUnmanaged(u8),

_ttf: TrueType,

pub fn init(allocator: Allocator, comptime ttf_bytes: []const u8) !Font {
    const ttf = try TrueType.load(ttf_bytes);
    const scale = ttf.scaleForPixelHeight(64);

    var buffer: std.ArrayListUnmanaged(u8) = .empty;

    var rects: [Limits.char_code_count]Rect = undefined;
    @memset(&rects, .{});

    var glyphs: [Limits.char_code_count]Glyph = undefined;
    @memset(&glyphs, .{});

    for (Limits.min_char_code..Limits.max_char_code) |codepoint| {
        if (ttf.codepointGlyphIndex(@intCast(codepoint))) |glyph| {
            const dims = try ttf.glyphBitmap(allocator, &buffer, glyph, scale, scale);

            const size_x: i16 = @intCast(dims.width);
            _ = size_x;
            const size_y: i16 = @intCast(dims.height);
            glyphs[@intCast(codepoint - Limits.min_char_code)] = .{
                .advance_width = scale * @as(f32, @floatFromInt(ttf.glyphHMetrics(glyph).advance_width)),
                .offset_y = @as(f32, @floatFromInt(size_y + dims.off_y)),
            };

            rects[@intCast(codepoint - Limits.min_char_code)] = .{
                .x = 0,
                .y = 0,
                .w = dims.width,
                .h = dims.height,
            };
        } else {
            return Errors.GlyphNotFound;
        }
    }

    var packer = RectPacker.make(.{
        .max_width = 512,
        .max_height = 512,
    });
    _ = try packer.pack(allocator, &rects);

    return .{
        ._rects = rects,
        ._glyphs = glyphs,
        ._rectPacker = packer,
        ._buffer = buffer,

        ._ttf = ttf,
    };
}

pub fn kernAdvance(self: Font, l: u8, r: u8) i16 {
    const lglyph = self._ttf.codepointGlyphIndex(@intCast(l)).?;
    const rglyph = self._ttf.codepointGlyphIndex(@intCast(r)).?;

    return self._ttf.glyphKernAdvance(lglyph, rglyph);
}

pub fn deinit(self: *Font, allocator: Allocator) void {
    self._buffer.deinit(allocator);
}
