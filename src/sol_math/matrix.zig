const Vec2 = @import("math.zig").Vec2;
const Vec3 = @import("math.zig").Vec3;
const Vec4 = @import("math.zig").Vec4;

pub const Error = error{
    SingularMatrix,
};

pub const Mat4 = struct {
    _m: [4]@Vector(4, f32),

    /// Returns the identity matrix.
    pub const identity: Mat4 = .{ ._m = .{
        @Vector(4, f32){ 1, 0, 0, 0 },
        @Vector(4, f32){ 0, 1, 0, 0 },
        @Vector(4, f32){ 0, 0, 1, 0 },
        @Vector(4, f32){ 0, 0, 0, 1 },
    } };

    /// Returns a matrix filled with only zeros.
    pub const zero: Mat4 = .{ ._m = .{
        @Vector(4, f32){ 0, 0, 0, 0 },
        @Vector(4, f32){ 0, 0, 0, 0 },
        @Vector(4, f32){ 0, 0, 0, 0 },
        @Vector(4, f32){ 0, 0, 0, 0 },
    } };

    pub fn translate(p: Vec3) Mat4 {
        return .{ ._m = [4]@Vector(4, f32){
            @Vector(4, f32){ 1, 0, 0, 0 },
            @Vector(4, f32){ 0, 1, 0, 0 },
            @Vector(4, f32){ 0, 0, 1, 0 },
            @Vector(4, f32){ p._v[0], p._v[1], p._v[2], 1 },
        } };
    }

    pub fn scale(s: Vec3) Mat4 {
        return .{ ._m = [4]@Vector(4, f32){
            @Vector(4, f32){ s._v[0], 0, 0, 0 },
            @Vector(4, f32){ 0, s._v[1], 0, 0 },
            @Vector(4, f32){ 0, 0, s._v[2], 0 },
            @Vector(4, f32){ 0, 0, 0, 1 },
        } };
    }

    pub fn ortho_rh(l: f32, r: f32, b: f32, t: f32, n: f32, f: f32) Mat4 {
        return .{ ._m = [4]@Vector(4, f32){
            @Vector(4, f32){ 2 / (r - l), 0, 0, 0 },
            @Vector(4, f32){ 0, 2 / (t - b), 0, 0 },
            @Vector(4, f32){ 0, 0, 1 / (f - n), 0 },
            @Vector(4, f32){ (l + r) / (l - r), (b + t) / (b - t), n / (n - f), 1 },
        } };
    }

    /// Multiplies this matrix (`self`) by another matrix (`right`) and returns the result.
    ///
    /// Mathematically:
    /// `result = self * right`
    pub fn mul(self: Mat4, right: Mat4) Mat4 {
        var result = Mat4.zero;

        for (0..4) |c| {
            const rcol = right._m[c];

            result._m[c] =
                self._m[0] * @Vector(4, f32){ rcol[0], rcol[0], rcol[0], rcol[0] } +
                self._m[1] * @Vector(4, f32){ rcol[1], rcol[1], rcol[1], rcol[1] } +
                self._m[2] * @Vector(4, f32){ rcol[2], rcol[2], rcol[2], rcol[2] } +
                self._m[3] * @Vector(4, f32){ rcol[3], rcol[3], rcol[3], rcol[3] };
        }

        return result;
    }

    pub fn mul_vec(self: Mat4, right: Vec4) Vec4 {
        return Vec4{ ._v = self._m[0] * @as(@Vector(4, f32), @splat(right._v[0])) +
            self._m[1] * @as(@Vector(4, f32), @splat(right._v[1])) +
            self._m[2] * @as(@Vector(4, f32), @splat(right._v[2])) +
            self._m[3] * @as(@Vector(4, f32), @splat(right._v[3])) };
    }

    /// Returns the element at the given coordinates (row, col).
    /// The matrix is stored in column-major order, so internally this reads
    /// from `self._m[col][row]`.
    pub fn at(self: Mat4, coords: struct { usize, usize }) f32 {
        const row: usize = coords.@"0";
        const col: usize = coords.@"1";

        if (row > 3 or col > 3) {
            return -1;
        }

        return self._m[col][row];
    }

    /// Sets the element at the given coordinates (row, col) = `val`.
    /// The matrix is stored in column-major order, so internally this reads
    /// from `self._m[col][row] = val`.
    pub fn set(self: *Mat4, coords: struct { u64, u64 }, val: f32) void {
        self._m[coords.@"1"][coords.@"0"] = val;
    }

    /// Returns the transpose of the matrix.
    pub fn transpose(self: Mat4) Mat4 {
        var result = Mat4.zero;

        for (0..4) |c| {
            for (0..4) |r| {
                result._m[r][c] = self._m[c][r];
            }
        }

        return result;
    }

    pub fn det(self: Mat4) f32 {
        // zig fmt: off
        const c0 = self.at(.{ 0, 0 }) * (
            (self.at(.{ 1, 1 }) * self.at(.{ 2, 2 }) * self.at(.{ 3, 3 })) +
            (self.at(.{ 1, 2 }) * self.at(.{ 2, 3 }) * self.at(.{ 3, 1 })) +
            (self.at(.{ 1, 3 }) * self.at(.{ 2, 1 }) * self.at(.{ 3, 2 })) -
            (self.at(.{ 1, 3 }) * self.at(.{ 2, 2 }) * self.at(.{ 3, 1 })) -
            (self.at(.{ 1, 2 }) * self.at(.{ 2, 1 }) * self.at(.{ 3, 3 })) -
            (self.at(.{ 1, 1 }) * self.at(.{ 2, 3 }) * self.at(.{ 3, 2 }))
        );

        const c1 = -self.at(.{ 1, 0 }) * (
            (self.at(.{ 0, 1 }) * self.at(.{ 2, 2 }) * self.at(.{ 3, 3 })) +
            (self.at(.{ 0, 2 }) * self.at(.{ 2, 3 }) * self.at(.{ 3, 1 })) +
            (self.at(.{ 0, 3 }) * self.at(.{ 2, 1 }) * self.at(.{ 3, 2 })) -
            (self.at(.{ 0, 3 }) * self.at(.{ 2, 2 }) * self.at(.{ 3, 1 })) -
            (self.at(.{ 0, 2 }) * self.at(.{ 2, 1 }) * self.at(.{ 3, 3 })) -
            (self.at(.{ 0, 1 }) * self.at(.{ 2, 3 }) * self.at(.{ 3, 2 }))
        );

        const c2 = self.at(.{ 2, 0 }) * (
            (self.at(.{ 0, 1 }) * self.at(.{ 1, 2 }) * self.at(.{ 3, 3 })) +
            (self.at(.{ 0, 2 }) * self.at(.{ 1, 3 }) * self.at(.{ 3, 1 })) +
            (self.at(.{ 0, 3 }) * self.at(.{ 1, 1 }) * self.at(.{ 3, 2 })) -
            (self.at(.{ 0, 3 }) * self.at(.{ 1, 2 }) * self.at(.{ 3, 1 })) -
            (self.at(.{ 0, 2 }) * self.at(.{ 1, 1 }) * self.at(.{ 3, 3 })) -
            (self.at(.{ 0, 1 }) * self.at(.{ 1, 3 }) * self.at(.{ 3, 2 }))
        );

        const c3 = -self.at(.{ 3, 0 }) * (
            (self.at(.{ 0, 1 }) * self.at(.{ 1, 2 }) * self.at(.{ 2, 3 })) +
            (self.at(.{ 0, 2 }) * self.at(.{ 1, 3 }) * self.at(.{ 2, 1 })) +
            (self.at(.{ 0, 3 }) * self.at(.{ 1, 1 }) * self.at(.{ 2, 2 })) -
            (self.at(.{ 0, 3 }) * self.at(.{ 1, 2 }) * self.at(.{ 2, 1 })) -
            (self.at(.{ 0, 2 }) * self.at(.{ 1, 1 }) * self.at(.{ 2, 3 })) -
            (self.at(.{ 0, 1 }) * self.at(.{ 1, 3 }) * self.at(.{ 2, 2 }))
        );

        // zig fmt: on
        return c0 + c1 + c2 + c3;
    }

    /// Source - https://stackoverflow.com/a
    /// Posted by shoosh, modified by community. See post 'Timeline' for change history
    /// Retrieved 2025-11-10, License - CC BY-SA 3.0
    pub fn inverse(self: Mat4) Error!Mat4 {
        var result = Mat4.zero;

        var inv = @as(*[16]f32, @ptrCast(&result));
        const m = @as(*const [16]f32, @ptrCast(&self));

        var row_det: f32 = 0.0;

        // zig fmt: off
        inv[0] = m[5]  * m[10] * m[15] -
                 m[5]  * m[11] * m[14] -
                 m[9]  * m[6]  * m[15] +
                 m[9]  * m[7]  * m[14] +
                 m[13] * m[6]  * m[11] -
                 m[13] * m[7]  * m[10];

        inv[4] = -m[4]  * m[10] * m[15] +
                  m[4]  * m[11] * m[14] +
                  m[8]  * m[6]  * m[15] -
                  m[8]  * m[7]  * m[14] -
                  m[12] * m[6]  * m[11] +
                  m[12] * m[7]  * m[10];

        inv[8] = m[4]  * m[9] * m[15] -
                 m[4]  * m[11] * m[13] -
                 m[8]  * m[5] * m[15] +
                 m[8]  * m[7] * m[13] +
                 m[12] * m[5] * m[11] -
                 m[12] * m[7] * m[9];

        inv[12] = -m[4]  * m[9] * m[14] +
                   m[4]  * m[10] * m[13] +
                   m[8]  * m[5] * m[14] -
                   m[8]  * m[6] * m[13] -
                   m[12] * m[5] * m[10] +
                   m[12] * m[6] * m[9];

        inv[1] = -m[1]  * m[10] * m[15] +
                  m[1]  * m[11] * m[14] +
                  m[9]  * m[2] * m[15] -
                  m[9]  * m[3] * m[14] -
                  m[13] * m[2] * m[11] +
                  m[13] * m[3] * m[10];

        inv[5] = m[0]  * m[10] * m[15] -
                 m[0]  * m[11] * m[14] -
                 m[8]  * m[2] * m[15] +
                 m[8]  * m[3] * m[14] +
                 m[12] * m[2] * m[11] -
                 m[12] * m[3] * m[10];

        inv[9] = -m[0]  * m[9] * m[15] +
                  m[0]  * m[11] * m[13] +
                  m[8]  * m[1] * m[15] -
                  m[8]  * m[3] * m[13] -
                  m[12] * m[1] * m[11] +
                  m[12] * m[3] * m[9];

        inv[13] = m[0]  * m[9] * m[14] -
                  m[0]  * m[10] * m[13] -
                  m[8]  * m[1] * m[14] +
                  m[8]  * m[2] * m[13] +
                  m[12] * m[1] * m[10] -
                  m[12] * m[2] * m[9];

        inv[2] = m[1]  * m[6] * m[15] - m[1]  * m[7] * m[14] - m[5]  * m[2] * m[15] +
                 m[5]  * m[3] * m[14] +
                 m[13] * m[2] * m[7] -
                 m[13] * m[3] * m[6];

        inv[6] = -m[0]  * m[6] * m[15] +
                  m[0]  * m[7] * m[14] +
                  m[4]  * m[2] * m[15] -
                  m[4]  * m[3] * m[14] -
                  m[12] * m[2] * m[7] +
                  m[12] * m[3] * m[6];

        inv[10] = m[0]  * m[5] * m[15] -
                  m[0]  * m[7] * m[13] -
                  m[4]  * m[1] * m[15] +
                  m[4]  * m[3] * m[13] +
                  m[12] * m[1] * m[7] -
                  m[12] * m[3] * m[5];

        inv[14] = -m[0]  * m[5] * m[14] +
                   m[0]  * m[6] * m[13] +
                   m[4]  * m[1] * m[14] -
                   m[4]  * m[2] * m[13] -
                   m[12] * m[1] * m[6] +
                   m[12] * m[2] * m[5];

        inv[3] = -m[1] * m[6] * m[11] +
                  m[1] * m[7] * m[10] +
                  m[5] * m[2] * m[11] -
                  m[5] * m[3] * m[10] -
                  m[9] * m[2] * m[7] +
                  m[9] * m[3] * m[6];

        inv[7] = m[0] * m[6] * m[11] -
                 m[0] * m[7] * m[10] -
                 m[4] * m[2] * m[11] +
                 m[4] * m[3] * m[10] +
                 m[8] * m[2] * m[7] -
                 m[8] * m[3] * m[6];

        inv[11] = -m[0] * m[5] * m[11] +
                   m[0] * m[7] * m[9] +
                   m[4] * m[1] * m[11] -
                   m[4] * m[3] * m[9] -
                   m[8] * m[1] * m[7] +
                   m[8] * m[3] * m[5];

        inv[15] = m[0] * m[5] * m[10] -
                  m[0] * m[6] * m[9] -
                  m[4] * m[1] * m[10] +
                  m[4] * m[2] * m[9] +
                  m[8] * m[1] * m[6] -
                  m[8] * m[2] * m[5];

        row_det = m[0] * inv[0] + m[1] * inv[4] + m[2] * inv[8] + m[3] * inv[12];
        // zig fmt: on

        if (row_det == 0.0) {
            return Error.SingularMatrix;
        }

        const d_factor = 1.0 / row_det;
        for (0..16) |i| {
            inv[i] = inv[i] * d_factor;
        }

        return result;
    }
};

pub const Mat3 = struct {
    _m: [3]@Vector(3, f32),

    /// Returns the identity matrix.
    pub const identity: Mat3 = .{ ._m = .{
        @Vector(3, f32){ 1, 0, 0 },
        @Vector(3, f32){ 0, 1, 0 },
        @Vector(3, f32){ 0, 0, 1 },
    } };

    pub const zero: Mat4 = .{ ._m = .{
        @Vector(3, f32){ 0, 0, 0 },
        @Vector(3, f32){ 0, 0, 0 },
        @Vector(3, f32){ 0, 0, 0 },
    } };

    pub fn translate(p: Vec2) Mat3 {
        return .{ ._m = [4]@Vector(4, f32){
            @Vector(4, f32){ 1, 0, 0, 0 },
            @Vector(4, f32){ 0, 1, 0, 0 },
            @Vector(4, f32){ 0, 0, 1, 0 },
            @Vector(4, f32){ p._v[0], p._v[1], p._v[2], 1 },
        } };
    }

    pub fn scale(s: Vec2) Mat4 {
        return .{ ._m = [4]@Vector(4, f32){
            @Vector(3, f32){ s._v[0], 0, 0 },
            @Vector(3, f32){ 0, s._v[1], 0 },
            @Vector(3, f32){ 0, 0, s._v[2] },
        } };
    }

    /// Multiplies this matrix (`self`) by another matrix (`right`) and returns the result.
    ///
    /// Mathematically:
    /// `result = self * right`
    pub fn mul(self: Mat3, right: Mat3) Mat3 {
        var result = Mat3.zero;

        for (0..3) |c| {
            const rcol = right._m[c];

            result._m[c] =
                self._m[0] * @Vector(3, f32){ rcol[0], rcol[0], rcol[0] } +
                self._m[1] * @Vector(3, f32){ rcol[1], rcol[1], rcol[1] } +
                self._m[2] * @Vector(3, f32){ rcol[2], rcol[2], rcol[2] };
        }

        return result;
    }

    pub fn mul_vec(self: Mat3, right: Vec3) Vec3 {
        return Vec3{ ._v = self._m[0] * @as(@Vector(3, f32), @splat(right._v[0])) +
            self._m[1] * @as(@Vector(3, f32), @splat(right._v[1])) +
            self._m[2] * @as(@Vector(3, f32), @splat(right._v[2])) };
    }
};
