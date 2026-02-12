const std = @import("std");
const Allocator = std.mem.Allocator;

const sol = @import("sol");
const gfx = sol.gfx;

const math = @import("sol_math");
const Vec3 = math.Vec3;
const Mat4 = math.Mat4;
const Quat = math.Quat;
const Rotation = math.Rotation;

const sol_renderer = @import("sol_renderer");
// const Renderer = sol_renderer.Renderer;

const sol_fetch = @import("sol_fetch");

const sol_camera = @import("sol_camera");
const MainCamera = sol_camera.MainCamera;

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
        var nindices: usize = 0;
        var index_type: sg.IndexType = .NONE;

        if (desc.view.indices) |indices_view| {
            switch (indices_view.uint) {
                .UNSIGNED_SHORT => {
                    index_type = .UINT16;
                    nindices = desc.indices.?.len / @sizeOf(u16);
                },

                .UNSIGNED_INT => {
                    index_type = .UINT32;
                    nindices = desc.indices.?.len / @sizeOf(u32);
                },

                else => @panic("Unsupported index type!"),
            }
        }

        return .{
            .view = desc.view,
            .nvertices = desc.vertices.len,
            .vbo = sg.makeBuffer(.{
                .usage = .{ .vertex_buffer = true },
                .data = sg.asRange(desc.vertices),
            }),

            .nindices = nindices,
            .index_type = index_type,
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

const Gltf = @import("zigltf").Gltf;
const zstbi = @import("zstbi");

pub const LinearSampler = struct {
    sampler: gfx.Sampler,

    pub fn init() !LinearSampler {
        return .{
            .sampler = try .init(.{}),
        };
    }

    pub fn deinit(self: *LinearSampler) void {
        self.sampler.deinit();
    }
};

pub const DefaultWhiteTexture = struct {
    img: gfx.Image,
    texture: gfx.Texture,

    pub fn init(linear_sampler: LinearSampler) !DefaultWhiteTexture {
        const rgba_white = [4]u8{ 255, 255, 255, 255 };
        const img: gfx.Image = try .init(&rgba_white, 1, 1, .RGBA8, .{});
        const texture: gfx.Texture = try .init(img, linear_sampler.sampler);

        return .{ .img = img, .texture = texture };
    }

    pub fn deinit(self: *DefaultWhiteTexture) void {
        self.texture.deinit();
    }
};

pub const BlitColorAttachment = struct {
    image: gfx.Image,
    attachment: gfx.RenderAttachment,

    pub fn init(
        gpa: Allocator,
    ) !BlitColorAttachment {
        const color = try gfx.Image.allocate(
            gpa,
            1080,
            720,
            .RGBA8,
            .{
                .usage = .{
                    .color_attachment = true,
                },
            },
        );

        const color_attachment: gfx.RenderAttachment = try .init(color, .Color);

        return .{
            .image = color,
            .attachment = color_attachment,
        };
    }

    pub fn deinit(self: *BlitColorAttachment) void {
        self.attachment.deinit();
        self.image.deinit();
    }
};

pub const GColorAttachment = struct {
    image: gfx.Image,
    attachment: gfx.RenderAttachment,
    texture: gfx.Texture,

    pub fn init(
        gpa: Allocator,
        linearSampler: LinearSampler,
    ) !GColorAttachment {
        const color = try gfx.Image.allocate(
            gpa,
            sol.windowWidth(),
            sol.windowHeight(),
            .RGBA16,
            .{
                .usage = .{
                    .color_attachment = true,
                },
            },
        );

        const color_attachment: gfx.RenderAttachment = try .init(color, .Color);

        const color_texture: gfx.Texture = try .init(color, linearSampler.sampler);

        return .{
            .image = color,
            .attachment = color_attachment,
            .texture = color_texture,
        };
    }

    pub fn deinit(self: *GColorAttachment) void {
        self.attachment.deinit();
        self.image.deinit();
    }
};

pub const GBufferPass = struct {
    const PipelineOptions = packed struct {
        /// If true, pass indices will be `u16` and `u32` otherwise.
        short_indices: bool = false,

        /// If true, pass will draw in using indices.
        instanced: bool = false,
    };

    color_attachment: *GColorAttachment,

    depth_stencil: gfx.Image,
    depth_stencil_attachment: gfx.RenderAttachment,

    /// Pipeline variants based on `PipelineOptions`.
    pips: std.AutoHashMap(PipelineOptions, sg.Pipeline),

    /// Last drawn pipeline
    prev_opts: ?PipelineOptions = .{},

    pub fn init(
        gpa: Allocator,
        color_attachment: *GColorAttachment,
    ) !GBufferPass {
        const depth_stencil = try gfx.Image.allocate(
            gpa,
            1080,
            720,
            .DEPTH_STENCIL,
            .{
                .usage = .{
                    .depth_stencil_attachment = true,
                },
            },
        );

        const depth_attachment: gfx.RenderAttachment = try .init(depth_stencil, .DepthStencil);

        // const render_target = try renderer.makeRenderTarget(.{
        //     .color_attachments = &[_]Renderer.RenderAttachment{
        //         color_attachment.attachment,
        //             //emissive_texture, //
        //     },
        //     .depth_attachment = depth_attachment,
        // });

        return .{
            .color_attachment = color_attachment,
            .depth_stencil = depth_stencil,
            .depth_stencil_attachment = depth_attachment,

            .pips = .init(gpa),
        };
    }

    pub fn begin(self: *GBufferPass) void {
        var pass: sg.Pass = .{};
        pass.attachments.colors[0] = self.color_attachment.attachment.gpuHandle();
        pass.attachments.depth_stencil = self.depth_stencil_attachment.gpuHandle();
        sg.beginPass(pass);

        self.prev_opts = null;
    }

    pub fn drawCulledAndSorted(
        self: *GBufferPass,
        camera: sol_camera.Camera3D,
        primitive: Primitive,
        material: Material,
        transform: Mat4,
    ) !void {
        const opts: PipelineOptions = .{
            .short_indices = primitive.index_type == .UINT16,
            .instanced = false,
        };

        const is_bound = if (self.prev_opts) |prev| prev == opts else false;
        if (!is_bound) {
            self.prev_opts = opts;

            const pip = self.pips.get(opts) orelse blk: {
                var desc: sg.PipelineDesc = .{
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
                };

                desc.colors[0].pixel_format = .RGBA16;
                desc.depth.pixel_format = .DEPTH_STENCIL;

                const pip = sg.makePipeline(desc);
                try self.pips.put(opts, pip);

                break :blk pip;
            };

            sg.applyPipeline(pip);
        }

        const mvp = camera.proj.mul(camera.view.mul(transform));
        sg.applyUniforms(shd.UB_scene_matrices, sg.asRange(&mvp));

        var bindings: sg.Bindings = .{};

        const base_color = @intFromEnum(PBRMaterial.Textures.Albedo);
        bindings.samplers[shd.SMP_linear] = material.textures[base_color].sampler.gpuHandle();
        bindings.views[shd.VIEW_abledo] = material.textures[base_color].view.gpuHandle();

        bindings.vertex_buffers[shd.ATTR_pbr_position] = primitive.vbo;
        bindings.index_buffer = primitive.ibo orelse .{};
        sg.applyBindings(bindings);

        sg.applyUniforms(shd.UB_material_parameters, sg.asRange(material.uniform));

        const elem_count: u32 = @intCast(if (primitive.ibo) |_| primitive.nindices else primitive.nvertices);
        sg.draw(0, elem_count, 1);
    }

    pub fn end(self: *GBufferPass) void {
        _ = self;
        sg.endPass();
    }

    pub fn deinit(self: *GBufferPass) void {
        self.depth_stencil_attachment.deinit();

        // TODO: Change to renderer image call
        self.depth_stencil.deinit();

        var it = self.pips.valueIterator();
        while (it.next()) |pip| {
            sg.destroyPipeline(pip.*);
        }

        self.pips.deinit();
    }
};

pub const ShadowPass = struct {};

pub const LightingPass = struct {};

pub const TransparencyPass = struct {};

pub const BlitPass = struct {
    color_attachment: *BlitColorAttachment,
    gcolor_attachment: *GColorAttachment,
    linear_sampler: *LinearSampler,

    pip: sg.Pipeline = .{},
    bindings: sg.Bindings = .{},

    pub fn init(
        color_attachment: *BlitColorAttachment,
        gcolor_attachment: *GColorAttachment,
        linear_sampler: *LinearSampler,
    ) !BlitPass {
        const pip = blk: {
            const desc: sg.PipelineDesc = .{
                .shader = sg.makeShader(shd.fsqShaderDesc(sg.queryBackend())),
                .depth = .{
                    .compare = .ALWAYS,
                },
                .cull_mode = .BACK,
            };

            break :blk sg.makePipeline(desc);
        };

        return .{
            .color_attachment = color_attachment,
            .gcolor_attachment = gcolor_attachment,
            .linear_sampler = linear_sampler,

            .pip = pip,
        };
    }

    pub fn draw(self: *BlitPass) void {
        const sglue = sol.glue;
        var action: sg.PassAction = .{};
        action.colors[0] = .{
            .load_action = .CLEAR,
            .clear_value = .{
                .r = 242.0 / 255.0,
                .g = 242.0 / 255.0,
                .b = 242.0 / 255.0,
                .a = 1.0,
            },
        };
        sg.beginPass(.{
            .action = action,
            .swapchain = sglue.swapchain(),
        });

        self.bindings.views[shd.VIEW_tex] = self.gcolor_attachment.texture.view.gpuHandle();
        self.bindings.samplers[shd.SMP_smp] = self.linear_sampler.sampler.gpuHandle();

        sg.applyPipeline(self.pip);
        sg.applyBindings(self.bindings);

        sg.draw(0, 6, 4);

        sg.endPass();
    }

    pub fn deinit(self: *BlitPass) void {
        sg.destroyPipeline(self.pip);
    }
};

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

    textures: [@intFromEnum(Textures.Count)]gfx.Texture,
    parameters: Parameters,

    pub const Options = struct {
        parameters: Parameters = .{},
        albedo: ?gfx.Texture = null,
        normal: ?gfx.Texture = null,
        emissive: ?gfx.Texture = null,
    };

    pub fn init(opts: Options) PBRMaterial {
        return .{
            .textures = [_]gfx.Texture{
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

pub const Material = struct {
    // Slice of textures used by material.
    textures: []const gfx.Texture,

    // Type erased slice of bytes used by material.
    uniform: []const u8,
};

const shd = @import("pbr_shaders");

// Implementation Note for Real-Time Rasterizers Real-time rasterizers typically use depth buffers and mesh sorting to support alpha modes. The following describe the expected behavior for these types of renderers. •
// OPAQUE - A depth value is written for every pixel and mesh sorting is not required for correct output. •
// MASK - A depth value is not written for a pixel that is discarded after the alpha test. A depth value is written for all other pixels. Mesh sorting is not required for correct output. •
// BLEND - Support for this mode varies. There is no perfect and fast solution that works for all cases. Client implementations should try to achieve the correct blending output for as many situations as possible. Whether depth value is written or whether to sort is up to the implementation. For example, implementations may discard pixels that have zero or close to zero alpha value to avoid sorting issues.

// Priority of textures
// Texture Rendering impact when feature is not supported
// Normal Geometry will appear less detailed than authored.
// Occlusion Model will appear brighter in areas that are intended to be darker.
// Emissive Model with lights will not be lit. For example, the headlights of a car model will be off instead of on.
const GltfViewer = struct {
    gpa: Allocator,
    input: *sol.Input,
    main_camera: *MainCamera,

    gltf: Gltf,

    images: []gfx.Image,
    samplers: []gfx.Sampler,
    textures: []gfx.Texture,
    materials: []PBRMaterial,
    meshes: []Mesh,

    gpass: *GBufferPass,
    blit_pass: *BlitPass,

    pub fn init(
        gpa: Allocator,
        input: *sol.Input,
        main_camera: *MainCamera,
        linear_sampler: LinearSampler,
        white_texture: DefaultWhiteTexture,
        g_pass: *GBufferPass,
        blit_pass: *BlitPass,
    ) !GltfViewer {
        const raw = try sol.fs.read(gpa, "2.0/DamagedHelmet/glTF/DamagedHelmet.gltf", .{});
        defer gpa.free(raw);

        // const gltf = try Gltf.init(gpa, raw, .{ .relative_directory = "2.0/DamagedHelmet/glTF" });
        const gltf = try Gltf.init(gpa, raw, .{ .relative_directory = "2.0/DamagedHelmet/glTF" });
        // const gltf = try Gltf.init(gpa, "2.0/MetalRoughSpheres/glTF/MetalRoughSpheres.gltf");

        zstbi.init(gpa);
        defer zstbi.deinit();

        const images = try gpa.alloc(gfx.Image, gltf.images.items.len);
        for (gltf.images.items, 0..) |img, i| {
            // TODO :Recycle memory as ring buffer
            sol.log.debug(
                "Loading {s} ({B})",
                .{ img.buffer.uri, img.buffer.bytes.len },
            );

            var stb_data: zstbi.Image = try .loadFromMemory(img.buffer.bytes, 4);
            defer stb_data.deinit();

            images[i] = try .init(
                stb_data.data,
                @intCast(stb_data.width),
                @intCast(stb_data.height),
                .RGBA8,
                .{},
            );
        }

        // HACK: gfx.Sampler must take in actual options isntead of hard injecting native.
        const samplers = try gpa.alloc(
            gfx.Sampler,
            gltf.samplers.len + 1,
        );
        samplers[samplers.len - 1] = .{ .sampler = sg.makeSampler(.{}) };
        for (gltf.samplers, 0..) |sampler, i| {
            var desc: sg.SamplerDesc = .{};

            if (sampler.magFilter) |mag_filter| {
                desc.mag_filter = switch (mag_filter) {
                    .LINEAR => .LINEAR,
                    .NEAREST => .NEAREST,
                    else => .DEFAULT,
                };
            }

            if (sampler.minFilter) |mag_filter| {
                desc.min_filter = switch (mag_filter) {
                    .LINEAR => .LINEAR,
                    .NEAREST => .NEAREST,

                    else => .DEFAULT,
                };
            }

            desc.wrap_u = switch (sampler.wrapS) {
                .CLAMP_TO_EDGE => .CLAMP_TO_EDGE,
                .MIRRORED_REPEAT => .MIRRORED_REPEAT,
                .REPEAT => .REPEAT,
            };

            samplers[i] = .{ .sampler = sg.makeSampler(desc) };
        }

        const textures = try gpa.alloc(gfx.Texture, gltf.textures.len);
        for (gltf.textures, 0..) |texture, i| {
            // textures[i] = try .init(images[texture.source], if (texture.sampler) |idx| samplers[idx] else linear_sampler.sampler);
            _ = linear_sampler;
            textures[i] = try .init(images[texture.source], if (texture.sampler) |idx| samplers[idx] else unreachable);
        }

        const materials = try gpa.alloc(PBRMaterial, gltf.materials.len);
        for (gltf.materials, 0..) |mat, i| {
            const pbr_params = mat.pbrMetallicRoughness orelse @panic("NOIMPL");
            materials[i] = PBRMaterial.init(.{
                .albedo = if (pbr_params.baseColorTexture) |text| textures[text.index] else white_texture.texture,
                .normal = if (mat.normalTexture) |text| textures[text.index] else white_texture.texture,
                .emissive = if (mat.emissiveTexture) |text| textures[text.index] else white_texture.texture,
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

        var arena: std.heap.ArenaAllocator = .init(gpa);
        const allocator = arena.allocator();
        defer arena.deinit();

        var node_it = gltf.rootsDFS(allocator) orelse unreachable;
        while (node_it.next()) |it| {
            var gtransform: Mat4 = .identity;

            switch (it.node.transform) {
                .Matrix => |mtx| {
                    for (0..16) |i| {
                        const x = i % 4;
                        const y = i / 4;
                        gtransform.set(.{ x, y }, mtx[x * 4 + y]);
                    }
                },

                .Component => |c| {
                    const translate: Mat4 = .translate(.new(
                        c.translation[0],
                        c.translation[1],
                        c.translation[2],
                    ));

                    const scale: Mat4 = .scale(.new(
                        c.scale[0],
                        c.scale[1],
                        c.scale[2],
                    ));

                    // const rotate : Mat4 =
                    const quat: Quat = .new(
                        c.rotation[0],
                        c.rotation[1],
                        c.rotation[2],
                        c.rotation[3],
                    );

                    const rotate: Mat4 = Rotation.fromQuat(quat).toMat4();
                    gtransform = gtransform.mul(translate.mul(rotate.mul(scale.mul(gtransform))));
                },
            }

            if (it.parent) |parent| {
                switch (parent.transform) {
                    .Matrix => |mtx| {
                        for (0..16) |i| {
                            const x = i % 4; // column
                            const y = i / 4; // row
                            gtransform.set(.{ x, y }, mtx[x * 4 + y]);
                        }
                    },

                    .Component => |c| {
                        const translate: Mat4 = .translate(.new(
                            c.translation[0],
                            c.translation[1],
                            c.translation[2],
                        ));

                        const scale: Mat4 = .scale(.new(
                            c.scale[0],
                            c.scale[1],
                            c.scale[2],
                        ));

                        // const rotate : Mat4 =
                        const quat: Quat = .new(
                            c.rotation[0],
                            c.rotation[1],
                            c.rotation[2],
                            c.rotation[3],
                        );

                        const rotate: Mat4 = Rotation.fromQuat(quat).toMat4();

                        const parent_transform: Mat4 = translate.mul(rotate.mul(scale.mul(gtransform)));
                        gtransform = parent_transform.mul(gtransform);
                    },
                }
            }
        }

        sol.log.debug("max depth : {d}", .{node_it.max_depth});

        // HACK: camera position should dynamocally adjust based on gltf bounding box.
        main_camera.camera().position = main_camera.camera().position.add(.new(0, 0, -1));

        return .{
            .gpa = gpa,
            .input = input,
            .main_camera = main_camera,
            .gpass = g_pass,
            .blit_pass = blit_pass,

            .gltf = gltf,
            .meshes = meshes,
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

        const gpass = self.gpass;
        const blit_pass = self.blit_pass;

        // FIX: Allocate on stack; Breaks on web by exceeding default stack size
        var arena_buffer: [1024]u8 = undefined;
        @memset(&arena_buffer, 0);

        var fba: std.heap.FixedBufferAllocator = .init(&arena_buffer);
        const allocator = fba.allocator();

        var node_it = self.gltf.rootsDFS(allocator) orelse unreachable;

        gpass.begin();

        while (node_it.next()) |it| {
            var gtransform: Mat4 = .identity;

            switch (it.node.transform) {
                .Matrix => |mtx| {
                    for (0..16) |i| {
                        const x = i % 4; // column
                        const y = i / 4; // row
                        gtransform.set(.{ x, y }, mtx[x * 4 + y]); // <- column-major indexing
                    }
                },

                .Component => |c| {
                    const translate: Mat4 = .translate(.new(
                        c.translation[0],
                        c.translation[1],
                        c.translation[2],
                    ));

                    const scale: Mat4 = .scale(.new(
                        c.scale[0],
                        c.scale[1],
                        c.scale[2],
                    ));

                    // const rotate : Mat4 =
                    const quat: Quat = .new(
                        c.rotation[0],
                        c.rotation[1],
                        c.rotation[2],
                        c.rotation[3],
                    );

                    const rotate: Mat4 = Rotation.fromQuat(quat).toMat4();
                    gtransform = gtransform.mul(translate.mul(rotate.mul(scale.mul(gtransform))));
                },
            }

            if (it.parent) |parent| {
                switch (parent.transform) {
                    .Matrix => |mtx| {
                        for (0..16) |i| {
                            const x = i % 4; // column
                            const y = i / 4; // row
                            gtransform.set(.{ x, y }, mtx[x * 4 + y]); // <- column-major indexing
                        }
                    },

                    .Component => |c| {
                        const translate: Mat4 = .translate(.new(
                            c.translation[0],
                            c.translation[1],
                            c.translation[2],
                        ));

                        const scale: Mat4 = .scale(.new(
                            c.scale[0],
                            c.scale[1],
                            c.scale[2],
                        ));

                        // const rotate : Mat4 =
                        const quat: Quat = .new(
                            c.rotation[0],
                            c.rotation[1],
                            c.rotation[2],
                            c.rotation[3],
                        );

                        const rotate: Mat4 = Rotation.fromQuat(quat).toMat4();

                        const parent_transform: Mat4 = translate.mul(rotate.mul(scale.mul(gtransform)));
                        gtransform = parent_transform.mul(gtransform);
                    },
                }
            }

            if (it.node.mesh_idx) |idx| {
                for (self.meshes[idx].primitives) |primitive| {
                    self.gpass.drawCulledAndSorted(
                        self.main_camera.camera().*,
                        primitive,
                        self.materials[primitive.material_id].material(),
                        gtransform,
                    ) catch unreachable;
                }
            }
        }

        gpass.end();

        blit_pass.draw();
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
            sampler.deinit();
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
            // sol_renderer.module,
            .{ .T = LinearSampler, .opts = .{} },
            .{ .T = DefaultWhiteTexture, .opts = .{} },

            .{ .T = GColorAttachment, .opts = .{} },
            .{ .T = GBufferPass, .opts = .{} },

            .{ .T = BlitColorAttachment, .opts = .{} },
            .{ .T = BlitPass, .opts = .{} },

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
