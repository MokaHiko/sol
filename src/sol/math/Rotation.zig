const Self = @This();

const Quat = @import("Quaternion.zig");
const Mat4 = @import("matrix.zig").Mat4;
const Vec3 = @import("vector.zig").Vec3;

_quat: Quat,

/// Create a rotation from Euler angles given in radians.
/// The angles are applied in intrinsic Y-X-Z order: - yaw (y) around the up (Y) axis
/// - pitch (x) around the right (X) axis
/// - roll (z) around the forward (Z) axis
///
/// This is equivalent to a world/extrinsic Z-Y-X rotation.
/// The resulting quaternion is normalized to ensure unit length.
pub fn new(x: f32, y: f32, z: f32) Self {
    const yaw = Quat.from_axis_angle(Vec3.up, y);
    const pitch = Quat.from_axis_angle(Vec3.right, x);
    const roll = Quat.from_axis_angle(Vec3.forward, z);

    // Y - X - Z intrinsic
    return .{ ._quat = yaw.mul(pitch.mul(roll)).normalize() catch unreachable };
}

pub fn toMat4(self: Self) Mat4 {
    const q = self._quat._v;
    const x = q[0];
    const y = q[1];
    const z = q[2];
    const w = q[3];

    return .{
        ._m = .{
            @Vector(4, f32){
                1 - 2 * y * y - 2 * z * z,
                2 * x * y + 2 * z * w,
                2 * x * z - 2 * y * w,
                0,
            },
            @Vector(4, f32){
                2 * x * y - 2 * z * w,
                1 - 2 * x * x - 2 * z * z,
                2 * y * z + 2 * x * w,
                0,
            },

            @Vector(4, f32){
                2 * x * z + 2 * y * w,
                2 * y * z - 2 * x * w,
                1 - 2 * x * x - 2 * y * y,
                0,
            },

            @Vector(4, f32){ 0, 0, 0, 1 },
        },
    };
}

const testing = @import("std").testing;
const math = @import("std").math;

test "Rotation 90deg X axis" {
    const s = math.sqrt(0.5);
    const q = Quat.new(s, 0, 0, s); // 90° X

    const r = Self{ ._quat = q };
    const m = r.toMat4();

    const expected = Mat4{
        ._m = .{
            @Vector(4, f32){ 1, 0, 0, 0 },
            @Vector(4, f32){ 0, 0, 1, 0 },
            @Vector(4, f32){ 0, -1, 0, 0 },
            @Vector(4, f32){ 0, 0, 0, 1 },
        },
    };

    for (0..4) |i| {
        for (0..4) |j| {
            try testing.expect(@abs(expected._m[i][j] - m._m[i][j]) <= 0.0001);
        }
    }
}
