const Camera3D = @This();

const sol = @import("sol");
const math = @import("sol_math");

const Vec3 = math.Vec3;
const Mat4 = math.Mat4;

const ProjectionType = enum {
    Orthographic,
    Perspective,
};

position: math.Vec3 = .zero,

view: math.Mat4 = .identity,
proj: math.Mat4 = .identity,
proj_type: ProjectionType = .Orthographic,

const Options = struct {
    starting_position: Vec3 = .zero,
};

pub fn init(proj_type: ProjectionType, opts: Options) Camera3D {
    var camera = Camera3D{
        .position = opts.starting_position,
    };

    switch (proj_type) {
        .Orthographic => {
            camera.setOrthogonal(1.0, 0.05, 4000);
        },
        .Perspective => {
            const w: f32 = @floatFromInt(sol.windowWidth());
            const h: f32 = @floatFromInt(sol.windowHeight());
            camera.setPerspective(
                90,
                w / h,
                0.05,
                1000,
            );
        },
    }

    return camera;
}

// src: https://github.com/HandmadeMath/HandmadeMath
pub fn lookat(self: *Camera3D, eye: Vec3, center: Vec3, up: Vec3) void {
    var res: Mat4 = .zero;

    const f = Vec3.normalize(Vec3.sub(center, eye)) catch unreachable;
    const s = Vec3.normalize(Vec3.cross(f, up)) catch unreachable;
    const u = Vec3.cross(s, f);

    res.m[0][0] = s.v[0];
    res.m[0][1] = u.v[0];
    res.m[0][2] = -f.v[0];

    res.m[1][0] = s.v[1];
    res.m[1][1] = u.v[1];
    res.m[1][2] = -f.v[1];

    res.m[2][0] = s.v[2];
    res.m[2][1] = u.v[2];
    res.m[2][2] = -f.v[2];

    res.m[3][0] = -Vec3.dot(s, eye);
    res.m[3][1] = -Vec3.dot(u, eye);
    res.m[3][2] = Vec3.dot(f, eye);
    res.m[3][3] = 1.0;

    self.view = res;
}

pub fn setOrthogonal(self: *Camera3D, size: f32, z_near: f32, z_far: f32) void {
    self.proj_type = .Orthographic;

    const window_width: f32 = @floatFromInt(sol.windowWidth());
    const window_height: f32 = @floatFromInt(sol.windowHeight());
    const aspect_ratio: f32 = window_height / window_width;

    const width = 10.0 / size;
    const height = width * aspect_ratio;

    const half_width: f32 = width / 2.0;
    const half_height: f32 = height / 2.0;

    self.proj = Mat4.orthoRH(
        -half_width,
        half_width,
        -half_height,
        half_height,
        z_near,
        z_far,
    );
}

/// Sets the camera in a perspective projectin with fov in degrees.
pub fn setPerspective(self: *Camera3D, fov: f32, aspect: f32, near: f32, far: f32) void {
    var res: Mat4 = .identity;
    const t = math.tan(fov * (math.pi / 360.0));

    res.m[0][0] = 1.0 / t;
    res.m[1][1] = aspect / t;
    res.m[2][3] = -1.0;
    res.m[2][2] = (near + far) / (near - far);
    res.m[3][2] = (2.0 * near * far) / (near - far);
    res.m[3][3] = 0.0;

    self.proj = res;
}

pub fn calcView(self: *Camera3D) void {
    _ = self;
    // self.view = Mat4.translate(Vec3.new(
    //     -self.position.v[0],
    //     -self.position.v[1],
    //     -self.position.v[2],
    // ));
}
