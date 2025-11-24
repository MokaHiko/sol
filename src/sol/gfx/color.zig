const std = @import("std");

///
/// Internaly stores colors as f32 to 0 - 1.0
///
pub const RGBA = struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,

    pub const black: RGBA = RGBA.new(0.0, 0.0, 0.0, 0.0);

    pub fn new(r: f32, g: f32, b: f32, a: f32) RGBA {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }

    pub fn toU32(self: RGBA) u32 {
        const r: u8 = @intFromFloat(self.r * 255.0);
        const g: u8 = @intFromFloat(self.g * 255.0);
        const b: u8 = @intFromFloat(self.b * 255.0);

        return @as(u32, r) << 8 | @as(u32, g) << 16 | @as(u32, b);
    }

    pub fn fromHex(hex: *const [6]u8) !RGBA {
        var c = std.mem.zeroes([4]f32);
        var c_idx: usize = 0;

        var i: usize = 0;
        while (i < hex.len) : (i += 2) {
            const hi = hexToInt(hex[i]);
            const lo = hexToInt(hex[i]);

            const val = (hi << 4) | lo;
            c[c_idx] = @as(f32, @floatFromInt(val)) / 255.0;
            c_idx = c_idx + 1;
        }

        return .{ .r = c[0], .g = c[1], .b = c[2], .a = c[3] };
    }

    fn hexToInt(d: u8) u8 {
        if (d >= '0' and d <= '9') return d - '0';
        if (d >= 'A' and d <= 'F') return d - 'A' + 10;
        if (d >= 'a' and d <= 'f') return d - 'a' + 10;
        return 0;
    }
};
