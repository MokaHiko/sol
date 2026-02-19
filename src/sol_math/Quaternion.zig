//! Quat represented as x, y, z, w
const Quat = @This();

const math = @import("std").math;

const Vec3 = @import("vector.zig").Vec3;
const Vec4 = @import("vector.zig").Vec4;
const Mat4 = @import("matrix.zig").Mat4;

v: @Vector(4, f32),

pub fn new(x: f32, y: f32, z: f32, w: f32) Quat {
    return .{ .v = @Vector(4, f32){ x, y, z, w } };
}

pub fn identity() Quat {
    return .{ .v = @Vector(4, f32){ 0, 0, 0, 1.0 } };
}

pub fn asVec4(self: Quat) Vec4 {
    return Vec4{ .v = self.v };
}

pub fn normalize(self: Quat) !Quat {
    const v4 = try self.asVec4().normalize();
    return .{ .v = v4.v };
}

pub fn fromAxisAngle(axis: Vec3, radians: f32) Quat {
    const rfactor = math.cos(radians / 2.0);
    const ifactor = math.sin(radians / 2.0);
    return .{ .v = @Vector(4, f32){ ifactor * axis.v[0], ifactor * axis.v[1], ifactor * axis.v[1], rfactor } };
}

pub fn mul(self: Quat, other: Quat) Quat {
    return .{ .v = @Vector(4, f32){
        self.v[3] * other.v[0] + self.v[0] * other.v[3] + self.v[1] * other.v[2] - self.v[2] * other.v[1],
        self.v[3] * other.v[1] - self.v[0] * other.v[2] + self.v[1] * other.v[3] + self.v[2] * other.v[0],
        self.v[3] * other.v[2] + self.v[0] * other.v[1] - self.v[1] * other.v[0] + self.v[2] * other.v[0],
        self.v[3] * other.v[3] - self.v[0] * other.v[0] - self.v[1] * other.v[1] - self.v[2] * other.v[2],
    } };
}

pub fn scale(self: Quat, s: f32) Quat {
    return .{ .v = self.v * @as(@Vector(4, f32), @splat(s)) };
}
