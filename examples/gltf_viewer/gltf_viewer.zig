const std = @import("std");
const Allocator = std.mem.Allocator;

const sol = @import("sol");
const gfx = sol.gfx;

const math = @import("sol_math");
const Vec3 = math.Vec3;
const Mat4 = math.Mat4;
const Rotation = math.Rotation;

const sol_fetch = @import("sol_fetch");

const sol_camera = @import("sol_camera");
const MainCamera = sol_camera.MainCamera;

const zstbi = @import("zstbi");

// TODO: Move to GLTFLoader

const Gltf = @import("Gltf.zig");

const Error = error{
    NoRootScene,
    EmptyScenes,
    EmptyNodes,
    EmptyMeshes,
    EmptyBuffers,
    EmptyBufferViews,
    EmptyAccessors,
    FailedToParse,
};

pub fn LoadGltf(gpa: Allocator) !void {
    const gltf_json = try std.json.parseFromSlice(
        Gltf,
        gpa,
        @embedFile("DamagedHelmet/glTF/DamagedHelmet.gltf"),
        .{
            .ignore_unknown_fields = true,
        },
    );
    defer gltf_json.deinit();

    const gltf: *const Gltf = &gltf_json.value;

    const scenes = gltf.scenes orelse return Error.EmptyScenes;
    const nodes = gltf.nodes orelse return Error.EmptyNodes;

    const meshes = gltf.meshes orelse return Error.EmptyMeshes;
    // const buffers = gltf.buffers orelse return Error.EmptyBuffers;
    const bufferViews = gltf.bufferViews orelse return Error.EmptyBufferViews;

    const accessors = gltf.accessors orelse return Error.EmptyAccessors;

    const root_scene_idx = gltf.scene orelse return Error.NoRootScene;
    const root_scene = scenes[root_scene_idx];

    // Laod scene

    // Queue load resources

    const scene_nodes = root_scene.nodes orelse return Error.EmptyNodes;
    for (scene_nodes) |nidx| {
        // sol.log.debug("{s}", .{nodes[nidx].name.?});
        // process matrix or TRS

        const midx = nodes[nidx].mesh orelse continue;

        const primitives = meshes[midx].primitives;
        for (primitives) |prim| {
            if (prim.attributes.POSITION) |p| {
                const vidx = accessors[p].bufferView;
                sol.log.debug("position buffer length {B}", .{bufferViews[vidx].byteLength});
            }

            if (prim.indices) |iidx| {
                const vidx = accessors[iidx].bufferView;
                sol.log.debug("buffer length {B}", .{bufferViews[vidx].byteLength});
            }
        }
    }
}

// TODO: Move to gfx
const sg = sol.gfx_native;

// TODO: This is really a mesh primitive
const Mesh = struct {
    vbo: sg.Buffer = .{},
    nvertices: usize = 0,

    ibo: ?sg.Buffer = .{},
    nindices: usize = 0,
};

pub fn IMesh(comptime VertexT: type) type {
    const tinfo = @typeInfo(VertexT);
    switch (tinfo) {
        .@"struct" => {},
        else => @compileError("Vertex type must be of struct!"),
    }

    return struct {
        const Self = @This();

        _mesh: Mesh = .{},

        // TODO: Meta data, comaptible w x or whatever
        // Requires x buffer
        pub const Options = struct {
            save_data: bool = false,
            dynamic: bool = false,
        };

        pub fn init(vertices: []const VertexT, indices: []const u32) !Self {
            const vbo = sg.makeBuffer(.{
                .data = sg.asRange(vertices),
                .usage = .{ .vertex_buffer = true },
            });

            const ibo = sg.makeBuffer(.{
                .data = sg.asRange(indices),
                .usage = .{ .index_buffer = true },
            });

            return .{
                ._mesh = .{
                    .vbo = vbo,
                    .nvertices = vertices.len,
                    .ibo = ibo,
                    .nindices = indices.len,
                },
            };
        }

        pub fn mesh(self: Self) Mesh {
            return self._mesh;
        }

        pub fn deinit(self: *Self) void {
            sg.destroyBuffer(self._mesh.vbo);
            self._mesh.nvertices = 0;

            if (self._mesh.ibo) |ibo| {
                sg.destroyBuffer(ibo);
                self._mesh.nindices = 0;
            }
        }
    };
}

// TODO: One more abstraction back from shader

pub const ShadowPass = struct {};

pub const GBufferPass = struct {
    pip: sg.Pipeline = .{},

    pub fn init() !GBufferPass {
        const pip = sg.makePipeline(.{
            .shader = sg.makeShader(shd.pbrShaderDesc(sg.queryBackend())),
            .index_type = .UINT32,
            .layout = init: {
                var l = sg.VertexLayoutState{};
                l.attrs[shd.ATTR_pbr_position].format = .FLOAT3;
                l.attrs[shd.ATTR_pbr_color].format = .FLOAT4;
                break :init l;
            },
            .depth = .{
                .compare = .LESS_EQUAL,
                .write_enabled = true,
            },
            .cull_mode = .BACK,
        });

        return .{ .pip = pip };
    }

    pub fn deinit(self: *GBufferPass) void {
        sg.destroyPipeline(self.pip);
    }
};

pub const LightingPass = struct {};

pub const TransparencyPass = struct {};

pub const PBR = struct {
    main_camera: *MainCamera,
    gpass: GBufferPass,

    pub const Textures = enum(i32) {
        Albedo = 0,
        Normal,
        Emissive,
    };

    // TODO: Get scene graph/draw list, and render target
    pub fn init(
        main_camera: *MainCamera,
        gpass: GBufferPass,
    ) !PBR {
        return .{
            .main_camera = main_camera,
            .gpass = gpass,
        };
    }

    // TODO: Remove immediate mode drawing
    var time: f32 = 0;
    pub fn draw(self: *PBR, mesh: Mesh, mat: Material) void {
        const camera = self.main_camera.camera();

        sg.applyPipeline(self.gpass.pip);

        const translate = Mat4.translate(Vec3.new(0, 0, -10));

        time += @floatCast(sol.deltaTime());
        const r: f32 = std.math.degreesToRadians(@sin(time) * 180);
        const rotate = Rotation.new(r, r, r).toMat4();

        const mvp = camera.viewProj().mul(translate.mul(rotate));
        sg.applyUniforms(shd.UB_scene_matrices, sg.asRange(&mvp));

        var bindings: sg.Bindings = .{};

        for (0..mat.ntextures) |i| {
            bindings.views[i] = mat.textures[i].view;
        }

        bindings.vertex_buffers[0] = mesh.vbo;
        bindings.index_buffer = mesh.ibo orelse .{};
        sg.applyBindings(bindings);

        if (mesh.ibo) |_| {
            sg.draw(0, @intCast(mesh.nindices), 1);
        } else {
            sg.draw(0, @intCast(mesh.nvertices), 1);
        }
    }

    pub fn frame(self: *PBR) void {
        _ = self;
    }

    pub fn deinit(self: *PBR) void {
        _ = self;
    }
};

const Texture = struct {
    view: sg.View = .{},
    sampler: sg.Sampler = .{},
};

pub const Material = struct {
    pub const Limits = struct {
        const max_textures: usize = 16;
        const max_uniforms: usize = 8;
    };

    textures: [Limits.max_textures]Texture,
    ntextures: u8 = 0,

    // TODO: Maybe moved to implementation,
    // because a lot of the time it's uniform through the entire pass
    //
    // uniform: []u8,
    // nubos: u8 = 0,

    pub fn init() !Material {
        var textures: [Limits.max_textures]Texture = undefined;
        @memset(textures[0..], .{});

        return .{ .textures = textures };
    }
    pub fn deinit(self: *Material) void {
        @memset(self.textures[0..], .{});
        self.ntextures = 0;
    }
};

const shd = @import("pbr_shaders");

pub const PCF32 = struct {
    struct { f32, f32, f32 },
    struct { f32, f32, f32, f32 },
};

const GltfViewer = struct {
    gpa: Allocator,
    input: *sol.Input,
    main_camera: *MainCamera,
    pbr: *PBR,

    cube_mesh: IMesh(PCF32),
    red_mat: Material,

    pub fn init(
        gpa: Allocator,
        input: *sol.Input,
        main_camera: *MainCamera,
        pbr: *PBR,
    ) !GltfViewer {
        LoadGltf(gpa) catch |e| {
            @panic(@errorName(e));
        };

        const vertices = [_]PCF32{
            .{ .{ -1.0, -1.0, -1.0 }, .{ 1.0, 0.0, 0.0, 1.0 } },
            .{ .{ 1.0, -1.0, -1.0 }, .{ 1.0, 0.0, 0.0, 1.0 } },
            .{ .{ 1.0, 1.0, -1.0 }, .{ 1.0, 0.0, 0.0, 1.0 } },
            .{ .{ -1.0, 1.0, -1.0 }, .{ 1.0, 0.0, 0.0, 1.0 } },

            .{ .{ -1.0, -1.0, 1.0 }, .{ 0.0, 1.0, 0.0, 1.0 } },
            .{ .{ 1.0, -1.0, 1.0 }, .{ 0.0, 1.0, 0.0, 1.0 } },
            .{ .{ 1.0, 1.0, 1.0 }, .{ 0.0, 1.0, 0.0, 1.0 } },
            .{ .{ -1.0, 1.0, 1.0 }, .{ 0.0, 1.0, 0.0, 1.0 } },

            .{ .{ -1.0, -1.0, -1.0 }, .{ 0.0, 0.0, 1.0, 1.0 } },
            .{ .{ -1.0, 1.0, -1.0 }, .{ 0.0, 0.0, 1.0, 1.0 } },
            .{ .{ -1.0, 1.0, 1.0 }, .{ 0.0, 0.0, 1.0, 1.0 } },
            .{ .{ -1.0, -1.0, 1.0 }, .{ 0.0, 0.0, 1.0, 1.0 } },

            .{ .{ 1.0, -1.0, -1.0 }, .{ 1.0, 0.5, 0.0, 1.0 } },
            .{ .{ 1.0, 1.0, -1.0 }, .{ 1.0, 0.5, 0.0, 1.0 } },
            .{ .{ 1.0, 1.0, 1.0 }, .{ 1.0, 0.5, 0.0, 1.0 } },
            .{ .{ 1.0, -1.0, 1.0 }, .{ 1.0, 0.5, 0.0, 1.0 } },

            .{ .{ -1.0, -1.0, -1.0 }, .{ 0.0, 0.5, 1.0, 1.0 } },
            .{ .{ -1.0, -1.0, 1.0 }, .{ 0.0, 0.5, 1.0, 1.0 } },
            .{ .{ 1.0, -1.0, 1.0 }, .{ 0.0, 0.5, 1.0, 1.0 } },
            .{ .{ 1.0, -1.0, -1.0 }, .{ 0.0, 0.5, 1.0, 1.0 } },

            .{ .{ -1.0, 1.0, -1.0 }, .{ 1.0, 0.0, 0.5, 1.0 } },
            .{ .{ -1.0, 1.0, 1.0 }, .{ 1.0, 0.0, 0.5, 1.0 } },
            .{ .{ 1.0, 1.0, 1.0 }, .{ 1.0, 0.0, 0.5, 1.0 } },
            .{ .{ 1.0, 1.0, -1.0 }, .{ 1.0, 0.0, 0.5, 1.0 } },
        };

        const indices = [_]u32{
            0,  1,  2,  0,  2,  3,
            6,  5,  4,  7,  6,  4,
            8,  9,  10, 8,  10, 11,
            14, 13, 12, 15, 14, 12,
            16, 17, 18, 16, 18, 19,
            22, 21, 20, 23, 22, 20,
        };

        return .{
            .gpa = gpa,
            .input = input,
            .main_camera = main_camera,
            .pbr = pbr,

            .cube_mesh = try .init(&vertices, &indices),
            .red_mat = try .init(),
        };
    }

    pub fn frame(self: *GltfViewer) void {
        self.pbr.draw(self.cube_mesh.mesh(), self.red_mat);
    }

    pub fn deinit(self: *GltfViewer) void {
        self.cube_mesh.deinit();
    }
};

pub fn main() !void {
    var app = try sol.App.create(
        sol.allocator,
        &[_]sol.App.ModuleDesc{
            sol_camera.module,
            // .{ .T = Text, .opts = .{} },
            // .{ .T = Sprite, .opts = .{} },
            // .{ .T = Scene, .opts = .{} },
            .{ .T = GBufferPass, .opts = .{} },
            .{ .T = PBR, .opts = .{} },
            .{ .T = GltfViewer, .opts = .{} },
        },
        .{
            .name = "GltfViewer",
            .width = 720,
            .height = 480,
        },
    );

    try app.run();
}
