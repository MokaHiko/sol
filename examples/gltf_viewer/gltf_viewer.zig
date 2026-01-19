const std = @import("std");
const Allocator = std.mem.Allocator;

const sol = @import("sol");
const gfx = sol.gfx;

const math = @import("sol_math");
const sol_fetch = @import("sol_fetch");

const sol_camera = @import("sol_camera");
const MainCamera = sol_camera.MainCamera;

const zstbi = @import("zstbi");

// TODO: Move to gfx
const sg = sol.gfx_native;

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
// pub const shader  = struct {desc : sg.ShaderDesc};
//
// _start_canary: u32 = 0,
// vertex_func: ShaderFunction = .{},
// fragment_func: ShaderFunction = .{},
// compute_func: ShaderFunction = .{},
// attrs: [16]ShaderVertexAttr = [_]ShaderVertexAttr{.{}} ** 16,
// uniform_blocks: [8]ShaderUniformBlock = [_]ShaderUniformBlock{.{}} ** 8,
// views: [28]ShaderView = [_]ShaderView{.{}} ** 28,
// samplers: [16]ShaderSampler = [_]ShaderSampler{.{}} ** 16,
// texture_sampler_pairs: [16]ShaderTextureSamplerPair = [_]ShaderTextureSamplerPair{.{}} ** 16,
// mtl_threads_per_threadgroup: MtlShaderThreadsPerThreadgroup = .{},
// label: [*c]const u8 = null,
// _end_canary: u32 = 0,

pub const Pipeline = struct {
    handle: sg.Pipeline = .{},

    pub fn deinit(self: *Pipeline) void {
        sg.destroyPipeline(self.handle);
    }
};

// TODO: JUST GET THE FIXED PIPELINES WORKING FIRST PROPERLY BEFORE ABSTRACTING IT YOU DUMBASS!
pub const PBRPipeline = struct {
    pip: Pipeline = .{},

    pub const TextureType = enum(i32) {
        Albedo = 0,
    };

    pub fn init() !PBRPipeline {
        // TODO: std.StaticStringMap(comptime V: type)
        // const sd = shaders.pbrShaderDesc(sg.queryBackend());
        // for (sd.uniform_blocks, 0..) |ub, ubidx| {
        //     if (ub.stage == .NONE) break;
        //     std.log.debug("ub: {d}, size : {d}", .{ ubidx, ub.size });
        //     for (ub.glsl_uniforms) |u| {
        //         if (u.type == .INVALID) break;
        //         std.log.debug(" - {s}", .{u.glsl_name});
        //     }
        // }

        if (true) return error.Fuck;

        const pip = sg.makePipeline(.{
            .shader = sg.makeShader(shaders.pbrShaderDesc(sg.queryBackend())),
        });

        return .{
            .pip = .{ .handle = pip },
        };
    }

    pub fn pipeline(self: PBRPipeline) Pipeline {
        return self.pip;
    }

    pub fn deinit(self: *Pipeline) void {
        self.pip.deinit();
    }
};

const Texture = struct {
    view: sg.View = .{},
    sampler: sg.Sampler = .{},
};

// TODO: maybe force enum on each texture?
pub const Material = struct {
    pub const Limits = struct {
        const max_textures: u8 = 16;
    };

    // TODO: textures each pipeline
    textures: [@intCast(Limits.max_textures)]Texture,
    ntextures: u8 = 0,

    // TODO: Multiple pipelines
    pip: Pipeline = .{},

    pub fn init(pip: Pipeline) !Material {
        var textures: [@intCast(Limits.max_textures)]Texture = undefined;
        @memset(textures[0..], .{});

        return .{ .textures = textures, .pip = pip };
    }
};

const MeshRenderer = struct {
    // render_target : RenderTarget
    pub fn draw(self: *MeshRenderer, mesh: Mesh, mat: Material) void {
        _ = self;

        var bindings: sg.Bindings = .{};

        for (0..mat.ntextures) |i| {
            bindings.views[i] = mat.textures[i].view;
        }

        bindings.vertex_buffers[0] = mesh.vbo;
        bindings.index_buffer = mesh.ibo orelse .{};

        sg.applyPipeline(mat.pip.handle);
        sg.applyBindings(bindings);

        if (mesh.ibo) |_| {
            sg.draw(0, @intCast(mesh.nvertices), 1);
        } else {
            sg.draw(0, @intCast(mesh.nindices), 1);
        }
    }
};

const shaders = @import("pbr_shaders");

pub const PCF32 = struct {
    struct { f32, f32, f32 },
    struct { f32, f32, f32, f32 },
};

const GltfViewer = struct {
    gpa: Allocator,
    input: *sol.Input,
    main_camera: *MainCamera,

    mesh_renderer: *MeshRenderer,

    cube_mesh: IMesh(PCF32),
    pbr_mat: Material,
    pbr_pip: PBRPipeline,

    pub fn init(
        gpa: Allocator,
        input: *sol.Input,
        main_camera: *MainCamera,
        mesh_renderer: *MeshRenderer,
    ) !GltfViewer {
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

        const indices = [_]u32{ 0, 1, 2, 0, 2, 3, 6, 5, 4, 7, 6, 4, 8, 9, 10, 8, 10, 11, 14, 13, 12, 15, 14, 12, 16, 17, 18, 16, 18, 19, 22, 21, 20, 23, 22, 20 };

        // TODO: Probably DI inject this
        const pbr: PBRPipeline = try .init();

        return .{
            .gpa = gpa,
            .input = input,
            .main_camera = main_camera,
            .mesh_renderer = mesh_renderer,

            .cube_mesh = try .init(&vertices, &indices),
            .pbr_pip = pbr,
            .pbr_mat = try .init(pbr.pipeline()),
        };
    }

    pub fn frame(self: *GltfViewer) void {
        self.mesh_renderer.draw(
            self.cube_mesh.mesh(),
            self.pbr_mat,
        );
    }

    pub fn deinit(self: *GltfViewer) void {
        self.cube_mesh.deinit();
    }
};

// TODO: DI Inject a PBR Renderer
// PBR Renderer, Sprite Renderer, Text renderer will be an example of the flexible render Pipeline
// i.e ubiquitous defaults
pub fn main() !void {
    var app = try sol.App.create(
        sol.allocator,
        &[_]sol.App.ModuleDesc{
            sol_camera.module,
            .{ .T = MeshRenderer, .opts = .{} },
            .{ .T = GltfViewer, .opts = .{} },
        },
        .{
            .name = "GltfViewer",
            .width = 1920,
            .height = 1080,
        },
    );

    try app.run();
}
