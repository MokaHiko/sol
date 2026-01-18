//! MainCamera
//!
//! Wrapper around `Camera3D`
//!
//! Designed to be passed into rendering systems, allowing multiple
//! camera instances without global state.
const sol = @import("sol");

pub const Camera3D = @import("Camera3D.zig");

pub const MainCamera = struct {
    _camera: Camera3D,

    pub fn init() !MainCamera {
        return .{
            ._camera = .init(.Orthographic, .{}),
        };
    }

    pub fn camera(self: *MainCamera) *Camera3D {
        return &self._camera;
    }

    pub fn frame(self: *MainCamera) void {
        self._camera.calcView();
    }
};

pub const module = sol.App.ModuleDesc{
    .T = MainCamera,
    .opts = .{},
};
