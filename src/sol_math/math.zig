pub const pi = @import("std").math.pi;
pub const tan = @import("std").math.tan;

const vector = @import("vector.zig");
pub const Vec2 = vector.Vec2;
pub const Vec3 = vector.Vec3;
pub const Vec4 = vector.Vec4;

const matrix = @import("matrix.zig");
pub const Mat4 = matrix.Mat4;

pub const Quat = @import("Quaternion.zig");
pub const Rotation = @import("Rotation.zig");
