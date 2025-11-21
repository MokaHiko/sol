/// Quat represented as x, y, z, w
const Self = @This();

const math = @import("std").math;

const Vec3 = @import("vector.zig").Vec3;
const Vec4 = @import("vector.zig").Vec4;
const Mat4 = @import("matrix.zig").Mat4;

_v: @Vector(4, f32),

pub fn new(x: f32, y: f32, z: f32, w: f32) Self {
    return .{ ._v = @Vector(4, f32){ x, y, z, w } };
}

pub fn identity() Self {
    return .{ ._v = @Vector(4, f32){ 0, 0, 0, 1.0 } };
}

pub fn asVec4(self: Self) Vec4 {
    return Vec4{ ._v = self._v };
}

pub fn normalize(self: Self) !Self {
    const v4 = try self.asVec4().normalize();
    return .{ ._v = v4._v };
}

pub fn fromAxisAngle(axis: Vec3, radians: f32) Self {
    const rfactor = math.cos(radians / 2.0);
    const ifactor = math.sin(radians / 2.0);
    return .{ ._v = @Vector(4, f32){ ifactor * axis._v[0], ifactor * axis._v[1], ifactor * axis._v[1], rfactor } };
}

pub fn mul(self: Self, other: Self) Self {
    return .{ ._v = @Vector(4, f32){
        self._v[3] * other._v[0] + self._v[0] * other._v[3] + self._v[1] * other._v[2] - self._v[2] * other._v[1],
        self._v[3] * other._v[1] - self._v[0] * other._v[2] + self._v[1] * other._v[3] + self._v[2] * other._v[0],
        self._v[3] * other._v[2] + self._v[0] * other._v[1] - self._v[1] * other._v[0] + self._v[2] * other._v[0],
        self._v[3] * other._v[3] - self._v[0] * other._v[0] - self._v[1] * other._v[1] - self._v[2] * other._v[2],
    } };
}

pub fn scale(self: Self, s: f32) Self {
    return .{ ._v = self._v * @as(@Vector(4, f32), @splat(s)) };
}
