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

_view: math.Mat4 = .identity,
_proj: math.Mat4 = .identity,
_proj_type: ProjectionType = .Orthographic,

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

        else => {
            @panic("Unimplemented Perspective!");
        },
    }

    return camera;
}

pub fn view(self: Camera3D) math.Mat4 {
    return self._view;
}

pub fn proj(self: Camera3D) math.Mat4 {
    return self._proj;
}

pub fn viewProj(self: Camera3D) math.Mat4 {
    return self.proj().mul(self.view());
}

pub fn setOrthogonal(self: *Camera3D, size: f32, z_near: f32, z_far: f32) void {
    self._proj_type = .Orthographic;

    const window_width: f32 = @floatFromInt(sol.windowWidth());
    const window_height: f32 = @floatFromInt(sol.windowHeight());
    const aspect_ratio: f32 = window_height / window_width;

    const width = 10.0 / size;
    const height = width * aspect_ratio;

    const half_width: f32 = width / 2.0;
    const half_height: f32 = height / 2.0;

    self._proj = Mat4.ortho_rh(
        -half_width,
        half_width,
        -half_height,
        half_height,
        z_near,
        z_far,
    );
}

pub fn calcView(self: *Camera3D) void {
    self._view = Mat4.translate(Vec3.new(
        -self.position._v[0],
        -self.position._v[1],
        -self.position._v[2],
    ));
}
