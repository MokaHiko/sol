const math = @import("std").math;
const testing = @import("std").testing;

const vector = @import("vector.zig");
const Vec3 = vector.Vec3;
const Vec4 = vector.Vec4;

const matrix = @import("matrix.zig");
const Mat4 = matrix.Mat4;

const Quat = @import("Quaternion.zig");
const Rotation = @import("Rotation.zig");

test "Vec3 equality" {
    const a = Vec3.new(1, 2, 3);
    const b = Vec3.new(1, 2, 3);
    const c = Vec3.new(3, 2, 1);

    try testing.expect(a.eql(b));
    try testing.expect(!a.eql(c));
}

test "Vec3 addition and subtraction" {
    const a = Vec3.new(1, 2, 3);
    const b = Vec3.new(4, 5, 6);

    const sum = a.add(b);
    try testing.expect(sum.eql(Vec3.new(5, 7, 9)));

    const diff = b.sub(a);
    try testing.expect(diff.eql(Vec3.new(3, 3, 3)));
}

test "Vec3 dot and cross product" {
    const a = Vec3.right;
    const b = Vec3.up;

    const dot = Vec3.dot(a, b);
    try testing.expect(dot == 0.0);

    const cross = Vec3.cross(a, b);
    try testing.expect(cross.eql(Vec3.forward));
}

test "Vec3 scale and length" {
    const v = Vec3.new(1, 2, 2);
    const scaled = v.scale(2);
    try testing.expect(scaled.eql(Vec3.new(2, 4, 4)));

    const len = v.len();
    try testing.expect(@abs(len - 3.0) < 1e-6);
}

test "Vec4 equality, addition, and subtraction" {
    const a = Vec4.new(1, 2, 3, 4);
    const b = Vec4.new(1, 2, 3, 4);
    const c = Vec4.new(4, 3, 2, 1);

    try testing.expect(a.eql(b));
    try testing.expect(!a.eql(c));

    try testing.expect(a.add(c).eql(Vec4.new(5, 5, 5, 5)));
    try testing.expect(c.sub(a).eql(Vec4.new(3, 1, -1, -3)));
}

test "Vec4 dot, length, and normalization" {
    const a = Vec4.new(1, 0, 0, 0);
    const b = Vec4.new(0, 1, 0, 0);

    try testing.expect(Vec4.dot(a, b) == 0.0);

    const v = Vec4.new(2, 0, 0, 0);
    try testing.expect(v.len() == 2.0);

    const norm = try v.normalize();
    try testing.expect(@abs(norm.len() - 1.0) < 1e-6);
}

test "Vec4 xyz and xxx shuffles" {
    const v = Vec4.new(1, 2, 3, 4);
    const xyz = v.xyz();
    try testing.expect(xyz.eql(Vec3.new(1, 2, 3)));

    const xxx = v.xxx();
    try testing.expect(xxx.eql(Vec3.new(1, 1, 1)));
}

test "zero matrix has determinant 0" {
    const Z = Mat4.zero();
    try testing.expect(Z.det() == 0.0);
}

test "identity matrix has determinant 1" {
    const I = Mat4.identity();
    try testing.expect(I.det() == 1.0);
}

test "zero matrix is singular" {
    const Z = Mat4.zero();
    try testing.expectError(matrix.Error.SingularMatrix, Z.inverse());
}

test "transformation identity" {
    const T = Mat4.translate(Vec3.new(10, 11, 12));
    const p = Vec4.new(0, 0, 0, 1.0);
    const p_prime = T.mul_vec(p);

    try testing.expect(Vec4.new(10, 11, 12, 1.0).eql(p_prime));
}

test "chained transform inverse gives identity" {
    const T = Mat4.translate(Vec3.new(1, 10, 4));
    const S = Mat4.scale(Vec3.new(5, 5.64, 5.4545));

    const transform = T.mul(S);
    const transform_inverse = try transform.inverse();

    const I = transform_inverse.mul(transform);

    const tolerance = 1e-3;
    try testing.expectApproxEqRel(I.det(), 1.0, tolerance);
}

test "rotation 90deg X axis" {
    const s = math.sqrt(0.5);
    const q = Quat.new(s, 0, 0, s); // 90° X

    const r = Rotation{ ._quat = q };
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
