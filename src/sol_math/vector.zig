pub const Vec2 = struct {
    pub const zero: Vec2 = .{ .v = @Vector(2, f32){ 0, 0 } };
    pub const one: Vec2 = .{ .v = @Vector(2, f32){ 1, 1 } };

    v: @Vector(2, f32),
};

pub const Vec3 = struct {
    pub const right = Vec3.new(1, 0, 0);
    pub const up = Vec3.new(0, 1, 0);
    pub const forward = Vec3.new(0, 0, 1);

    pub const zero: Vec3 = .{ .v = @Vector(3, f32){ 0, 0, 0 } };
    pub const one: Vec3 = .{ .v = @Vector(3, f32){ 1, 1, 1 } };

    v: @Vector(3, f32),

    pub fn eql(self: Vec3, other: Vec3) bool {
        return @reduce(.And, self.v == other.v);
    }

    pub fn dot(a: Vec3, b: Vec3) f32 {
        return _dot(a.v, b.v);
    }

    pub fn cross(a: Vec3, b: Vec3) Vec3 {
        return Vec3.new(
            a.v[1] * b.v[2] - a.v[2] * b.v[1],
            a.v[2] * b.v[0] - a.v[0] * b.v[2],
            a.v[0] * b.v[1] - a.v[1] * b.v[0],
        );
    }

    pub fn new(x: f32, y: f32, z: f32) Vec3 {
        return .{ .v = @Vector(3, f32){ x, y, z } };
    }

    pub fn normalize(self: Vec3) !Vec3 {
        const l = self.len();

        if (l == 0.0) {
            return error.DivideByZero;
        }

        return .{ .v = self.v * @as(@Vector(3, f32), @splat(1.0 / l)) };
    }

    pub fn add(self: Vec3, other: Vec3) Vec3 {
        return .{ .v = self.v + other.v };
    }

    pub fn sub(self: Vec3, other: Vec3) Vec3 {
        return .{ .v = self.v - other.v };
    }

    pub fn scale(self: Vec3, s: f32) Vec3 {
        return Vec3.new(self.v[0] * s, self.v[1] * s, self.v[2] * s);
    }

    pub fn len(self: Vec3) f32 {
        return _len(self.v);
    }
};

pub const Vec4 = struct {
    v: @Vector(4, f32),

    pub const zero: Vec4 = .{ .v = @Vector(4, f32){ 0, 0, 0, 0 } };
    pub const one: Vec4 = .{ .v = @Vector(4, f32){ 1, 1, 1, 1 } };

    pub fn dot(a: Vec4, b: Vec4) f32 {
        return _dot(a.v, b.v);
    }

    pub fn new(x: f32, y: f32, z: f32, w: f32) Vec4 {
        return .{ .v = @Vector(4, f32){ x, y, z, w } };
    }

    pub fn normalize(self: Vec4) !Vec4 {
        const l = self.len();

        if (l == 0.0) {
            return error.DivideByZero;
        }

        return .{ .v = self.v * @as(@Vector(4, f32), @splat(1.0 / l)) };
    }

    pub fn xyz(self: Vec4) Vec3 {
        return .{ .v = @shuffle(f32, self.v, undefined, @Vector(3, i32){ 0, 1, 2 }) };
    }

    pub fn xxx(self: Vec4) Vec3 {
        return .{ .v = @shuffle(f32, self.v, undefined, @Vector(3, i32){ 0, 0, 0 }) };
    }

    pub fn eql(self: Vec4, other: Vec4) bool {
        return @reduce(.And, self.v == other.v);
    }

    pub fn add(self: Vec4, other: Vec4) Vec4 {
        return .{ .v = self.v + other.v };
    }

    pub fn sub(self: Vec4, other: Vec4) Vec4 {
        return .{ .v = self.v - other.v };
    }

    pub fn len(self: Vec4) f32 {
        return _len(self.v);
    }
};

fn _dot(a: anytype, b: @TypeOf(a)) @TypeOf(a[0]) {
    const T = @TypeOf(a);
    var sum: @TypeOf(a[0]) = 0;
    inline for (0..@typeInfo(T).vector.len) |i| {
        sum += a[i] * b[i];
    }
    return sum;
}

fn _len2(a: anytype) @TypeOf(a[0]) {
    return _dot(a, a);
}

fn _len(a: anytype) @TypeOf(a[0]) {
    return @sqrt(_len2(a));
}
