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

// TODO: Move to renderer module
const sg = sol.gfx_native;

const Primitive = struct {
    view: *const Gltf.PrimitiveView,
    vbo: sg.Buffer = .{},

    ibo: ?sg.Buffer = .{},
    index_type: sg.IndexType = .NONE,

    nvertices: usize = 0,
    nindices: usize = 0,

    material_id: u32 = 0,

    const Description = struct {
        vertices: []const u8,
        view: *const Gltf.PrimitiveView,
        indices: ?[]const u8 = null,
    };

    pub fn init(desc: Description) Primitive {
        return .{
            .view = desc.view,
            .nvertices = desc.vertices.len,
            .vbo = sg.makeBuffer(.{
                .usage = .{ .vertex_buffer = true },
                .data = sg.asRange(desc.vertices),
            }),

            .nindices = if (desc.indices) |b| b.len else 0,
            .index_type = if (desc.view.indices) |iview| switch (iview.uint) {
                .UNSIGNED_SHORT => .UINT16,
                .UNSIGNED_INT => .UINT32,

                else => @panic("Unsupported index type!"),
            } else .NONE,
            .ibo = if (desc.indices) |b| sg.makeBuffer(.{
                .usage = .{ .index_buffer = true },
                .data = sg.asRange(b),
            }) else .{},
        };
    }

    pub fn deinit(self: *Primitive) void {
        sg.destroyBuffer(self.vbo);
        self.nvertices = 0;

        if (self.ibo) |ibo| {
            sg.destroyBuffer(ibo);
            self.nindices = 0;
        }
    }
};

const Mesh = struct {
    primitives: []Primitive,

    pub fn deinit(self: *Mesh, gpa: Allocator) void {
        for (self.primitives) |*primitive| {
            primitive.deinit();
        }
        gpa.free(self.primitives);
    }
};

const Node = struct {
    local_matrix: math.Mat4,
    meshes: []const Mesh,
};

// const Gltf = @import("Gltf.zig");
const Gltf = @import("sol_gltf").Gltf;
const zstbi = @import("zstbi");

// TODO: One more abstraction back from shader
pub const LinearSampler = struct {
    renderer: *sol.App.Renderer,

    sampler: sol.App.Renderer.Sampler2D,

    pub fn init(renderer: *sol.App.Renderer) !LinearSampler {
        return .{
            .renderer = renderer,
            .sampler = renderer.makeSampler(.{}),
        };
    }

    pub fn deinit(self: *LinearSampler) void {
        self.renderer.destroySampler(self.sampler);
    }
};

pub const DefaultWhiteTexture = struct {
    img: gfx.Image,
    texture: Texture,

    pub fn init(linear_sampler: LinearSampler) !DefaultWhiteTexture {
        const rgba_white = [4]u8{ 255, 255, 255, 255 };
        const img: gfx.Image = try .init(&rgba_white, 1, 1, .RGBA8, .{});
        const texture: Texture = try .init(img, .{ .id = @intCast(linear_sampler.sampler.@"0") });

        return .{ .img = img, .texture = texture };
    }

    pub fn deinit(self: *DefaultWhiteTexture) void {
        self.texture.deinit();
        self.texture = .{};
    }
};

pub const ShadowPass = struct {};

pub const GBufferPass = struct {
    const PipelineOptions = packed struct {
        /// If true, pass indices will be `u16` and `u32` otherwise.
        short_indices: bool = false,

        /// If true, pass will draw in indexed mode
        instanced: bool = false,
    };

    /// Pipeline variants based on `PipelineOptions`.
    pips: std.AutoHashMap(PipelineOptions, sg.Pipeline),

    pub fn init(gpa: Allocator) !GBufferPass {
        return .{ .pips = .init(gpa) };
    }

    // TODO: Make sure CULLED and sorted
    // TODO: Remove immediate mode drawing
    var time: f32 = 0;
    pub fn drawCulledAndSorted(
        self: *GBufferPass,
        camera: sol_camera.Camera3D,
        primitive: Primitive,
        mat: Material,
    ) !void {
        const opts: PipelineOptions = .{
            .short_indices = primitive.index_type == .UINT16,
            .instanced = false,
        };

        // TODO: When draing multiple, store previous opts to not re query map.
        // Move to function with return union type
        const pip = self.pips.get(opts) orelse blk: {
            const pip = sg.makePipeline(.{
                .shader = sg.makeShader(shd.pbrShaderDesc(sg.queryBackend())),
                .index_type = primitive.index_type,
                .layout = init: {
                    var l = sg.VertexLayoutState{};

                    l.attrs[shd.ATTR_pbr_position].format = .FLOAT3;
                    l.attrs[shd.ATTR_pbr_normal].format = .FLOAT3;

                    for (primitive.view.texcoords) |opt_tc| {
                        const tc = opt_tc orelse {
                            sol.log.err("Vertex missing TEXCOORD_0 attribute!", .{});
                            continue;
                        };

                        l.attrs[shd.ATTR_pbr_texcoord].format = switch (tc.float) {
                            .FLOAT => .FLOAT2,
                            .UNSIGNED_SHORT => .USHORT2N,
                            .UNSIGNED_BYTE => .INVALID,
                            else => .INVALID,
                        };

                        break;
                    }

                    l.buffers[0].stride = @intCast(primitive.view.vertexSize());
                    break :init l;
                },
                .depth = .{
                    .compare = .LESS_EQUAL,
                    .write_enabled = true,
                },
                .cull_mode = .BACK,
            });

            try self.pips.put(opts, pip);
            break :blk pip;
        };

        sg.applyPipeline(pip);

        const translate = Mat4.translate(Vec3.new(0, 0, 10));

        time += @floatCast(sol.deltaTime());
        const r: f32 = std.math.degreesToRadians(@sin(time) * 180);
        const rotate = Rotation.new(r, r, r).toMat4();

        const mvp = camera.viewProj().mul(translate.mul(rotate));
        sg.applyUniforms(shd.UB_scene_matrices, sg.asRange(&mvp));

        // material bindings
        var bindings: sg.Bindings = .{};
        const base_color = @intFromEnum(PBRMaterial.Textures.Albedo);
        bindings.samplers[shd.SMP_linear] = mat.textures[base_color].sampler;
        bindings.views[shd.VIEW_abledo] = mat.textures[base_color].view;

        bindings.vertex_buffers[0] = primitive.vbo;
        bindings.index_buffer = primitive.ibo orelse .{};
        sg.applyBindings(bindings);

        sg.applyUniforms(
            shd.UB_material_parameters,
            sg.asRange(mat.uniform),
        );

        if (primitive.ibo) |_| {
            sg.draw(0, @intCast(primitive.nindices), 1);
        } else {
            sg.draw(0, @intCast(primitive.nvertices), 1);
        }
    }

    pub fn deinit(self: *GBufferPass) void {
        var it = self.pips.valueIterator();
        while (it.next()) |pip| {
            sg.destroyPipeline(pip.*);
        }

        self.pips.deinit();
    }
};

pub const LightingPass = struct {};

pub const TransparencyPass = struct {};

pub const PBRMaterial = struct {
    pub const Textures = enum(usize) {
        Albedo = 0,
        Normal,
        Emissive,
        Count,
    };

    const Parameters = struct {
        base_color: [4]f32 = [_]f32{ 1.0, 1.0, 1.0, 1.0 },
    };

    textures: [@intFromEnum(Textures.Count)]Texture,
    parameters: Parameters,

    pub const Options = struct {
        parameters: Parameters = .{},
        albedo: ?Texture = null,
        normal: ?Texture = null,
        emissive: ?Texture = null,
    };

    pub fn init(opts: Options) PBRMaterial {
        return .{
            .textures = [_]Texture{
                opts.albedo orelse undefined,
                opts.normal orelse undefined,
                opts.emissive orelse undefined,
            },
            .parameters = opts.parameters,
        };
    }

    pub fn material(self: *PBRMaterial) Material {
        return .{
            .textures = &self.textures,
            .uniform = @as([*]u8, @ptrCast(&self.parameters))[0..@sizeOf(Parameters)],
        };
    }

    pub fn deinit(self: *PBRMaterial) void {
        _ = self;
    }
};

// Implementation Note for Real-Time Rasterizers Real-time rasterizers typically use depth buffers and mesh sorting to support alpha modes. The following describe the expected behavior for these types of renderers. •
// OPAQUE - A depth value is written for every pixel and mesh sorting is not required for correct output. •
// MASK - A depth value is not written for a pixel that is discarded after the alpha test. A depth value is written for all other pixels. Mesh sorting is not required for correct output. •
// BLEND - Support for this mode varies. There is no perfect and fast solution that works for all cases. Client implementations should try to achieve the correct blending output for as many situations as possible. Whether depth value is written or whether to sort is up to the implementation. For example, implementations may discard pixels that have zero or close to zero alpha value to avoid sorting issues.

// Priority of textures
// Texture Rendering impact when feature is not supported
// Normal Geometry will appear less detailed than authored.
// Occlusion Model will appear brighter in areas that are intended to be darker.
// Emissive Model with lights will not be lit. For example, the headlights of a car model will be off instead of on.
pub const PBRMetallicRoughness = struct {
    main_camera: *MainCamera,
    gpass: *GBufferPass,

    // TODO: Get scene graph/draw list, and render target
    pub fn init(
        main_camera: *MainCamera,
        gpass: *GBufferPass,
    ) !PBRMetallicRoughness {
        return .{
            .main_camera = main_camera,
            .gpass = gpass,
        };
    }

    pub fn draw(self: *PBRMetallicRoughness, mesh: Primitive, mat: Material) void {
        self.gpass.drawCulledAndSorted(self.main_camera.*._camera, mesh, mat) catch unreachable;
    }

    pub fn frame(self: *PBRMetallicRoughness) void {
        _ = self;
    }

    pub fn deinit(self: *PBRMetallicRoughness) void {
        _ = self;
    }
};

// TODO: Move to gfx INCLUDING REMOVING _ for private
const Texture = struct {
    view: sg.View = .{},
    sampler: sg.Sampler = .{},

    pub fn init(img: gfx.Image, sampler: sg.Sampler) !Texture {
        return .{
            .view = sg.makeView(.{ .texture = .{ .image = img._image } }),
            .sampler = sampler,
        };
    }

    pub fn deinit(self: *Texture) void {
        sg.destroyView(self.view);
    }
};

pub const Material = struct {
    // Slice of textures used by material.
    textures: []const Texture,

    // Type erased slice of bytes used by material.
    uniform: []const u8,
};

const shd = @import("pbr_shaders");

const GltfViewer = struct {
    gpa: Allocator,
    input: *sol.Input,
    main_camera: *MainCamera,
    pbr: *PBRMetallicRoughness,

    gltf: Gltf,

    images: []gfx.Image,
    samplers: []sg.Sampler,
    textures: []Texture,
    materials: []PBRMaterial,
    meshes: []Mesh,
    nodes: []Node,

    pub fn init(
        gpa: Allocator,
        input: *sol.Input,
        main_camera: *MainCamera,
        pbr: *PBRMetallicRoughness,
        linear_sampler: LinearSampler,
    ) !GltfViewer {
        const gltf = Gltf.init(
            gpa,
            "examples/gltf_viewer/DamagedHelmet/glTF/DamagedHelmet.gltf",
        ) catch @panic("Failed to load gltf");

        zstbi.init(gpa);
        defer zstbi.deinit();

        const images = try gpa.alloc(gfx.Image, gltf.images.items.len);
        for (gltf.images.items, 0..) |img, i| {
            sol.log.debug(
                "Loading {s} ({B})",
                .{ img.buffer.uri, img.buffer.bytes.len },
            );

            var stbi_img: zstbi.Image = try .loadFromMemory(img.buffer.bytes, 4);
            defer stbi_img.deinit();

            images[i] = try .init(
                stbi_img.data,
                @intCast(stbi_img.width),
                @intCast(stbi_img.height),
                .RGBA8,
                .{},
            );
        }

        const samplers = try gpa.alloc(
            sg.Sampler,
            gltf.samplers.len + 1,
        );
        samplers[samplers.len - 1] = sg.makeSampler(.{});

        for (gltf.samplers, 0..) |smpler, i| {
            var desc: sg.SamplerDesc = .{};

            if (smpler.magFilter) |mag_filter| {
                desc.mag_filter = switch (mag_filter) {
                    .LINEAR => .LINEAR,
                    .NEAREST => .NEAREST,
                    else => .DEFAULT,
                };
            }

            if (smpler.minFilter) |mag_filter| {
                desc.min_filter = switch (mag_filter) {
                    .LINEAR => .LINEAR,
                    .NEAREST => .NEAREST,

                    else => .DEFAULT,
                };
            }

            desc.wrap_u = switch (smpler.wrapS) {
                .CLAMP_TO_EDGE => .CLAMP_TO_EDGE,
                .MIRRORED_REPEAT => .MIRRORED_REPEAT,
                .REPEAT => .REPEAT,
            };

            samplers[i] = sg.makeSampler(desc);
        }

        const textures = try gpa.alloc(Texture, gltf.textures.len);
        for (gltf.textures, 0..) |texture, i| {
            // textures[i] = try .init(images[texture.source], if (texture.sampler) |idx| samplers[idx] else linear_sampler.sampler);
            _ = linear_sampler;
            textures[i] = try .init(images[texture.source], if (texture.sampler) |idx| samplers[idx] else unreachable);
        }

        const materials = try gpa.alloc(PBRMaterial, gltf.materials.len);
        for (gltf.materials, 0..) |mat, i| {
            const pbr_params = mat.pbrMetallicRoughness orelse @panic("NOIMPL");
            materials[i] = PBRMaterial.init(.{
                .albedo = textures[if (pbr_params.baseColorTexture) |text| text.index else unreachable],
                .normal = textures[if (mat.normalTexture) |text| text.index else unreachable],
            });
        }

        const meshes = try gpa.alloc(Mesh, gltf.meshes.items.len);
        for (gltf.meshes.items, meshes) |*mesh_view, *mesh| {
            mesh.primitives = try gpa.alloc(Primitive, mesh_view.primitives.len);
            for (mesh_view.primitives, 0..) |*prim_view, i| {
                // calculate vertex count
                const pattr = prim_view.positions orelse {
                    sol.log.err("Failed to load primitive!", .{});
                    continue;
                };
                const ivertex: usize = pattr.bytes.len / pattr.stride;
                const stride: u32 = prim_view.vertexSize();

                // copy vertex attributes into interleaved vertices buffer
                const vertices = try gpa.alloc(u8, ivertex * stride);
                defer gpa.free(vertices);

                var vidx: u32 = 0; // vertex index
                var voffset: u32 = 0; // offset into vertex buffer

                while (voffset < vertices.len) {
                    if (prim_view.positions) |_| {
                        const attr_size = @sizeOf(f32) * 3;

                        @memcpy(
                            vertices[voffset .. voffset + attr_size],
                            pattr.bytes[(vidx * pattr.stride) .. (vidx * pattr.stride) + attr_size],
                        );

                        voffset += attr_size;
                    }

                    if (prim_view.normals) |attr| {
                        const attr_size = @sizeOf(f32) * 3;

                        @memcpy(
                            vertices[voffset .. voffset + @sizeOf(f32) * 3],
                            attr.bytes[(vidx * attr.stride) .. (vidx * attr.stride) + attr_size],
                        );

                        voffset += attr_size;
                    }

                    for (prim_view.texcoords) |tattr| {
                        const attr = tattr orelse continue;

                        const attr_size: u32 = switch (attr.float) {
                            .UNSIGNED_BYTE => @sizeOf(u8) * 2,
                            .UNSIGNED_SHORT => @sizeOf(u16) * 2,
                            .FLOAT => @sizeOf(f32) * 2,
                            else => unreachable,
                        };

                        @memcpy(
                            vertices[voffset .. voffset + attr_size],
                            attr.bytes[(vidx * attr.stride) .. (vidx * attr.stride) + attr_size],
                        );

                        voffset += attr_size;
                    }

                    vidx += 1;
                }

                mesh.primitives[i] = .init(.{
                    .vertices = vertices,
                    .view = prim_view,
                    .indices = if (mesh_view.primitives[i].indices) |buffer| buffer.bytes else null,
                });
            }
        }

        return .{
            .gpa = gpa,
            .input = input,
            .main_camera = main_camera,
            .pbr = pbr,
            .gltf = gltf,
            .meshes = meshes,
            .nodes = undefined,
            .images = images,
            .samplers = samplers,
            .textures = textures,
            .materials = materials,
        };
    }

    pub fn frame(self: *GltfViewer) void {
        const input = self.input;

        if (input.isKeyDown(.ESCAPE)) {
            sol.quit();
        }

        self.pbr.draw(
            self.meshes[0].primitives[0],
            self.materials[self.meshes[0].primitives[0].material_id].material(),
        );
    }

    pub fn deinit(self: *GltfViewer) void {
        for (self.materials) |*mat| {
            mat.deinit();
        }
        self.gpa.free(self.materials);

        for (self.textures) |*texture| {
            texture.deinit();
        }
        self.gpa.free(self.textures);

        for (self.images) |*img| {
            img.deinit();
        }
        self.gpa.free(self.images);

        for (self.samplers) |sampler| {
            sg.destroySampler(sampler);
        }
        self.gpa.free(self.samplers);

        for (self.meshes) |*mesh| {
            mesh.deinit(self.gpa);
        }
        self.gpa.free(self.meshes);

        self.gltf.deinit(self.gpa);
    }
};

pub fn main() !void {
    var app = try sol.App.create(
        sol.allocator,
        &[_]sol.App.ModuleDesc{
            sol_camera.module,
            .{ .T = LinearSampler, .opts = .{} },
            .{ .T = DefaultWhiteTexture, .opts = .{} },
            .{ .T = GBufferPass, .opts = .{} },
            .{ .T = PBRMetallicRoughness, .opts = .{} },
            .{ .T = GltfViewer, .opts = .{} },
        },
        .{
            .name = "GltfViewer",
            .width = 1080,
            .height = 720,
        },
    );

    try app.run();
}
