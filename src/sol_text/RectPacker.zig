const RectPacker = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

const Rect = @import("Rect.zig");

const u16_max = std.math.maxInt(u16);

const Errors = error{
    SpaceNotFound,
};

const Options = struct {
    max_width: u16 = u16_max,
    max_height: u16 = u16_max,

    /// If true, the packer may reorder the rectangles to improve packing efficiency.
    /// If false, order provided will be preserved.
    sort: bool = false,
};

_opts: Options,

pub fn make(opts: Options) RectPacker {
    return .{
        ._opts = opts,
    };
}

pub fn pack(self: *RectPacker, allocator: Allocator, rects: []Rect) !Rect {
    if (self._opts.sort) {
        std.sort.insertion(Rect, rects, {}, heightDescendingFn);
    }

    const max_width = self._opts.max_width;
    const max_height = self._opts.max_height;

    var packing_height: u16 = 0;

    const Point = struct { x: u16, y: u16 };

    const skl_capacity = if (max_height != u16_max and max_width != u16_max) max_width * 2 else 0;
    var skl = try allocator.alloc(Point, skl_capacity);
    defer allocator.free(skl);

    skl[0] = .{ .x = 0, .y = 0 };
    var nskl: usize = 1;

    for (0..rects.len) |ri| {
        const rect = rects[ri];

        // Candidate skyline coords
        var cx: u16 = u16_max;
        var cy: u16 = u16_max;
        var skli: usize = u16_max;

        // Last crossed skyline point
        var sklli: usize = u16_max;

        for (0..nskl) |cur| {
            // Bounds check
            if (skl[cur].y + rect.h > max_height or
                skl[cur].x + rect.w > max_width)
            {
                continue;
            }

            // Check if has a chance to beat candidate
            if (skli != u16_max and cy <= skl[cur].y) {
                continue;
            }

            // Raise y over colliding skyline points
            var raise = skl[cur].y;
            const x_advance = skl[cur].x + rect.w;
            var next = cur + 1;
            while (next < nskl) : (next = next + 1) {
                // We do not overlap next skyline point
                if (x_advance <= skl[next].x) {
                    break;
                }

                raise = @max(raise, skl[next].y);
            }

            if (cy <= raise) {
                continue;
            }

            cx = skl[cur].x;
            cy = raise;
            skli = cur;
            sklli = next;
        }

        if (skli == u16_max) {
            return Errors.SpaceNotFound;
        }

        // Update rect
        rects[ri].x = cx;
        rects[ri].y = cy;

        packing_height = @max(packing_height, cy + rect.h);

        const nremoved: usize = sklli - skli;
        var nadded: usize = 1;

        // Check if and calculate bottom right point
        const x_advance = cx + rect.w;
        var bry: u16 = 0;
        if (sklli < nskl) {
            // Divides last segment
            if (x_advance < skl[sklli].x) {
                nadded = nadded + 1;
                bry = skl[sklli - 1].y;
            }
        } else {
            // Divides previous skypoint at edge
            if (x_advance < max_width) {
                nadded = nadded + 1;
                bry = skl[nskl - 1].y;
            }
        }

        const tl: Point = .{ .x = cx, .y = cy + rect.h };
        const br: Point = .{ .x = cx + rect.w, .y = bry };

        if (nadded > nremoved) {
            // Allocate space by shift right
            const net = nadded - nremoved;

            var rit = nskl - 1;
            while (rit > skli) : (rit = rit - 1) {
                skl[rit + net] = skl[rit];
            }

            nskl += net;
        } else if (nadded < nremoved) {
            // // Shrink skyline by shift left
            const net = nremoved - nadded;

            for (skli + 1..nskl - net) |i| {
                skl[i] = skl[i + net];
            }

            nskl -= net;
        }

        skl[skli] = tl;
        if (nadded > 1) {
            skl[skli + 1] = br;
        }
    }

    self._opts.max_height = packing_height;

    return .{
        .x = 0,
        .y = 0,
        .w = max_width,
        .h = packing_height,
    };
}

fn heightDescendingFn(_: void, a: Rect, b: Rect) bool {
    return @max(a.w, a.h) > @max(b.w, b.h);
}
