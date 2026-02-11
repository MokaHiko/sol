//! MainCamera
//!
//! Wrapper around `Camera3D`
//!
//! Designed to be passed into rendering systems, allowing multiple
//! camera instances without global state.
const sol = @import("sol");

pub const Camera3D = @import("Camera3D.zig");

pub const MainCamera = struct {
    camera_3d: Camera3D,

    pub fn init() !MainCamera {
        return .{
            .camera_3d = .init(.Orthographic, .{}),
        };
    }

    pub fn camera(self: *MainCamera) *Camera3D {
        return &self.camera_3d;
    }

    pub fn frame(self: *MainCamera) void {
        self.camera_3d.calcView();
    }
};

pub const module = sol.App.ModuleDesc{
    .T = MainCamera,
    .opts = .{},
};
