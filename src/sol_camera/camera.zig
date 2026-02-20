//! MainCamera
//!
//! Wrapper around `Camera3D`
//!
//! Designed to be passed into rendering systems, allowing multiple
//! camera instances without global state.
const sol = @import("sol");

pub const Camera3D = @import("Camera3D.zig");

pub const MainCamera = struct {
    camera: Camera3D,

    pub fn init() !MainCamera {
        return .{
            .camera = .init(.Perspective, .{}),
        };
    }

    pub fn frame(self: *MainCamera) void {
        self.camera.calcView();
    }
};

pub const module = sol.App.ModuleDesc{
    .T = MainCamera,
    .opts = .{},
};
