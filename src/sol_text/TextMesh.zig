const TextMesh = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

const sg = @import("sol").gfx_native;

const Font = @import("Font.zig");

/// The TrueType Font to use when rendering the text.
font: ?*const Font = null,

vb: sg.Buffer = .{},
ib: sg.Buffer = .{},
char_count: u32 = 0,

pub fn init(allocator: Allocator, font: *const Font, text: []const u8) !TextMesh {
    var font_vertices = try allocator.alloc(struct {
        x: f32,
        y: f32,
        uv_x: f32,
        uv_y: f32,
    }, text.len * 4);
    defer allocator.free(font_vertices);

    var font_indices = try allocator.alloc(u16, text.len * 6);
    defer allocator.free(font_indices);

    const cursor_y: f32 = 250;
    var cursor_x: f32 = 0;

    const tex_w: f32 = @floatFromInt(font._rectPacker._opts.max_width);
    const tex_h: f32 = @floatFromInt(font._rectPacker._opts.max_height);

    for (text, 0..) |c, i| {
        const rect = font._rects[c - Font.Limits.min_char_code];
        const glyph = font._glyphs[c - Font.Limits.min_char_code];

        const x: f32 = cursor_x + glyph.offset_x;
        const y: f32 = cursor_y - glyph.offset_y;

        const w: f32 = @floatFromInt(rect.w);
        const h: f32 = @floatFromInt(rect.h);

        const tex_x: f32 = @floatFromInt(rect.x);
        const tex_y: f32 = @floatFromInt(rect.y);

        const vbi = i * 4;
        const ibi = i * 6;

        // Top left
        font_vertices[vbi] = .{
            .x = x,
            .y = y,
            .uv_x = tex_x / tex_w,
            .uv_y = tex_y / tex_h,
        };

        // Top right
        font_vertices[vbi + 1] = .{
            .x = x + w,
            .y = y,
            .uv_x = (tex_x + w) / tex_w,
            .uv_y = tex_y / tex_h,
        };

        // Bottom left
        font_vertices[vbi + 2] = .{
            .x = x,
            .y = y + h,
            .uv_x = tex_x / tex_w,
            .uv_y = (tex_y + h) / tex_h,
        };

        // Bottom right
        font_vertices[vbi + 3] = .{
            .x = x + w,
            .y = y + h,
            .uv_x = (tex_x + w) / tex_w,
            .uv_y = (tex_y + h) / tex_h,
        };

        font_indices[ibi] = @intCast(vbi);
        font_indices[ibi + 1] = @intCast(vbi + 1);
        font_indices[ibi + 2] = @intCast(vbi + 2);
        font_indices[ibi + 3] = @intCast(vbi + 2);
        font_indices[ibi + 4] = @intCast(vbi + 1);
        font_indices[ibi + 5] = @intCast(vbi + 3);

        cursor_x += @floatCast(glyph.advance_width);

        if (i + 1 < text.len) {
            cursor_x += @floatFromInt(font.kernAdvance(text[i], text[i + 1]));
        }
    }

    return .{
        .font = font,
        .char_count = @intCast(text.len),

        .vb = sg.makeBuffer(.{
            .usage = .{ .vertex_buffer = true },
            .data = sg.asRange(font_vertices),
        }),

        .ib = sg.makeBuffer(.{
            .usage = .{ .index_buffer = true },
            .data = sg.asRange(font_indices),
        }),
    };
}

pub fn deinit(self: *TextMesh) void {
    sg.destroyBuffer(self.vb);
    sg.destroyBuffer(self.ib);
}
