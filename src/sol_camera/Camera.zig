const sol = @import("sol");

pub const Camera3D = @import("Camera3D.zig");

pub const MainCamera = struct {
    camera: Camera3D,

    pub fn init() !MainCamera {
        return .{
            .camera = .init(.Orthographic, .{}),
        };
    }
};

pub const module = sol.App.ModuleDesc{
    .T = MainCamera,
    .opts = .{},
};
