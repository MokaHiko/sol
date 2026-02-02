const Gltf = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

const sol = @import("sol");

const GltfJson = @import("GltfJson.zig");

const Error = error{
    InvalidAttributeType,
    InvalidAttributeComponent,
    InvalidAccessorType,

    NoRootScene,
    InvalidIndexTarget,
    EmptyScenes,
    EmptyNodes,
    EmptyMeshes,
    EmptyBuffers,
    EmptyBufferViews,
    EmptyAccessors,
    FailedToParse,
};

pub const Options = struct {
    handedness: Handedness = .Right,
};

pub const Limits = struct {
    const max_texture_coords = 2;
};

pub const Handedness = enum {
    Right,
    Left,
};

const Buffer = struct {
    bytes: []u8,
    uri: []const u8,
};

const Image = struct {
    buffer: Buffer,
};

const Sampler = GltfJson.Sampler;

const Material = GltfJson.Material;

const Texture = GltfJson.Texture;

// TODO: Move to gfx.Primitive.View
pub const PrimitiveView = struct {
    /// POSITIONs are assumed to be of component `vec3`  and type `f32` without extensions.
    positions: ?struct {
        bytes: []u8,
        stride: u32,
    },

    /// NORMALs are assumed to be of component `vec3`  and type `f32` without extensions.
    normals: ?struct {
        bytes: []u8,
        stride: u32,
    },

    /// TEXCOORDs are assumed to be of component `vec2`  and type `float, ushort, ubyte` normalized unsigned without extensions.
    texcoords: [Limits.max_texture_coords]?struct {
        float: GltfJson.ComponentType,
        bytes: []u8,
        stride: u32,
    },

    /// COLORs are assumed to be of component `vec3`/`vec4`  and type `float, ushort, ubyte` normalized unsigned without extensions.
    color: ?struct {
        float: GltfJson.ComponentType,
        has_alpha: bool,
        bytes: []u8,
        stride: u32,
    },

    /// INDICEs must be an UNSIGNED_BYTE/SHORT/INT indicate int the `uint` field.
    indices: ?struct {
        uint: GltfJson.ComponentType,
        bytes: []u8,
        stride: u32,
    },

    /// Returns the tightly-packed size of a single vertex in bytes.
    pub fn vertexSize(self: PrimitiveView) u32 {
        var s: u32 = @sizeOf(f32) * 3;

        if (self.normals) |_| s += @sizeOf(f32) * 3;

        for (self.texcoords) |tattrib| {
            const attr = tattrib orelse continue;
            s += switch (attr.float) {
                .UNSIGNED_BYTE => @sizeOf(u8) * 2,
                .UNSIGNED_SHORT => @sizeOf(u16) * 2,
                .FLOAT => @sizeOf(f32) * 2,
                else => unreachable,
            };
        }

        return @intCast(s);
    }
};

const MeshDescription = struct {
    primitives: []PrimitiveView,
    name: []const u8,
};

json: std.json.Parsed(GltfJson),

samplers: []Sampler,
textures: []Texture,
materials: []Material,

buffers: std.ArrayList(Buffer),
images: std.ArrayList(Image),
meshes: std.ArrayList(MeshDescription),

// TODO: Init for m path
pub fn init(gpa: Allocator, path: []const u8) !Gltf {
    // TODO: Free pass ownership of buffer along with json
    const raw_gltf = try sol.fs.read(gpa, path, .{});
    // defer gpa.free(raw_gltf);

    const parsed = try std.json.parseFromSlice(
        GltfJson,
        gpa,
        raw_gltf,
        .{
            .ignore_unknown_fields = true,
        },
    );
    const json: *const GltfJson = &parsed.value;

    // Queue load resources

    // transient allocator for joining paths
    //TODO: Handle longer path lengths
    const path_buffer = try gpa.alloc(u8, @min(64, path.len) * 2);
    defer gpa.free(path_buffer);

    var fba: std.heap.FixedBufferAllocator = .init(path_buffer);
    const path_allocator = fba.allocator();

    var buffers: std.ArrayList(Buffer) = try .initCapacity(
        gpa,
        if (json.buffers) |buffers| buffers.len else 0,
    );

    var images: std.ArrayList(Image) = try .initCapacity(
        gpa,
        if (json.images) |images| images.len else 0,
    );

    if (json.buffers) |gltf_buffers| {
        for (gltf_buffers) |gltf_buffer| {
            const uri = gltf_buffer.uri orelse continue;
            const dir = std.fs.path.dirname(path) orelse @panic("Unimplemented uri type");

            const file_path = try std.fs.path.join(
                path_allocator,
                &[_][]const u8{ dir, uri },
            );
            defer path_allocator.free(file_path);

            try buffers.append(gpa, .{
                .uri = uri,
                .bytes = try sol.fs.read(gpa, file_path, .{}),
            });
        }
    }

    if (json.images) |gltf_images| {
        for (gltf_images) |gltf_img| {
            if (gltf_img.uri) |uri| {
                const dir = std.fs.path.dirname(path) orelse @panic("Unimplemented uri type");

                const file_path = try std.fs.path.join(
                    path_allocator,
                    &[_][]const u8{ dir, uri },
                );
                defer path_allocator.free(file_path);

                try buffers.append(gpa, .{
                    .uri = uri,
                    .bytes = try sol.fs.read(gpa, file_path, .{}),
                });

                try images.append(gpa, .{
                    .buffer = buffers.getLast(),
                });
            } else if (gltf_img.bufferView) |_| unreachable else unreachable;
        }
    }

    const bufferViews = json.bufferViews orelse return Error.EmptyBufferViews;
    const accessors = json.accessors orelse return Error.EmptyAccessors;

    var meshes: std.ArrayList(MeshDescription) = if (json.meshes) |meshes| try .initCapacity(gpa, meshes.len) else .{};
    if (json.meshes) |gltf_meshes| {
        for (gltf_meshes) |gltf_mesh| {
            const primitives = try gpa.alloc(PrimitiveView, gltf_mesh.primitives.len);
            for (gltf_mesh.primitives, 0..) |gltf_primitive, pidx| {
                if (gltf_primitive.attributes.POSITION) |aidx| {
                    const accessor = &accessors[aidx];

                    const vidx = accessor.bufferView;
                    const view = &bufferViews[vidx];
                    const buffer = buffers.items[view.buffer];

                    const accessor_type = std.meta.stringToEnum(
                        GltfJson.AccesorType,
                        accessor.type,
                    ) orelse return Error.FailedToParse;

                    switch (accessor_type) {
                        .VEC3 => {},
                        else => return Error.InvalidAccessorType,
                    }

                    const stride = view.byteStride orelse blk: {
                        // accessor type enum is equivalent to element count.
                        const count: u32 = @intFromEnum(accessor_type);

                        break :blk switch (accessor.componentType) {
                            .FLOAT => count * @sizeOf(f32),
                            else => return Error.InvalidAttributeComponent,
                        };
                    };

                    primitives[pidx].positions = .{
                        .bytes = buffer.bytes[view.byteOffset .. view.byteOffset + view.byteLength],
                        .stride = stride,
                    };
                }

                if (gltf_primitive.attributes.NORMAL) |aidx| {
                    const accessor = &accessors[aidx];

                    const vidx = accessor.bufferView;
                    const view = &bufferViews[vidx];
                    const buffer = buffers.items[view.buffer];

                    const accessor_type = std.meta.stringToEnum(
                        GltfJson.AccesorType,
                        accessor.type,
                    ) orelse return Error.FailedToParse;

                    switch (accessor_type) {
                        .VEC3 => {},
                        else => return Error.InvalidAccessorType,
                    }

                    const stride = view.byteStride orelse blk: {
                        // accessor type enum is equivalent to element count.
                        const count: u32 = @intFromEnum(accessor_type);

                        break :blk switch (accessor.componentType) {
                            .FLOAT => count * @sizeOf(f32),
                            else => return Error.InvalidAttributeComponent,
                        };
                    };

                    primitives[pidx].normals = .{
                        .bytes = buffer.bytes[view.byteOffset .. view.byteOffset + view.byteLength],
                        .stride = stride,
                    };
                }

                if (gltf_primitive.attributes.TEXCOORD_0) |aidx| {
                    const accessor = &accessors[aidx];

                    const vidx = accessor.bufferView;
                    const view = &bufferViews[vidx];
                    const buffer = buffers.items[view.buffer];

                    const accessor_type = std.meta.stringToEnum(
                        GltfJson.AccesorType,
                        accessor.type,
                    ) orelse return Error.FailedToParse;

                    switch (accessor_type) {
                        .VEC2 => {},
                        else => return Error.InvalidAccessorType,
                    }

                    const stride = view.byteStride orelse blk: {
                        // accessor type enum is equivalent to element count.
                        const count: u32 = @intFromEnum(accessor_type);

                        break :blk switch (accessor.componentType) {
                            .UNSIGNED_BYTE => count,
                            .UNSIGNED_SHORT => count * @sizeOf(u16),
                            .FLOAT => count * @sizeOf(f32),
                            else => return Error.InvalidAttributeComponent,
                        };
                    };

                    primitives[pidx].texcoords[0] = .{
                        .float = accessor.componentType,
                        .bytes = buffer.bytes[view.byteOffset .. view.byteOffset + view.byteLength],
                        .stride = stride,
                    };
                } else primitives[pidx].texcoords[0] = null;

                if (gltf_primitive.attributes.TEXCOORD_1) |aidx| {
                    const accessor = &accessors[aidx];

                    const vidx = accessor.bufferView;
                    const view = &bufferViews[vidx];
                    const buffer = buffers.items[view.buffer];

                    const accessor_type = std.meta.stringToEnum(
                        GltfJson.AccesorType,
                        accessor.type,
                    ) orelse return Error.FailedToParse;

                    switch (accessor_type) {
                        .VEC2 => {},
                        else => return Error.InvalidAccessorType,
                    }

                    const stride = view.byteStride orelse blk: {
                        // accessor type enum is equivalent to element count.
                        const count: u32 = @intFromEnum(accessor_type);

                        break :blk switch (accessor.componentType) {
                            .UNSIGNED_BYTE => count,
                            .UNSIGNED_SHORT => count * @sizeOf(u16),
                            .FLOAT => count * @sizeOf(f32),
                            else => return Error.InvalidAttributeComponent,
                        };
                    };

                    primitives[pidx].texcoords[1] = .{
                        .float = accessor.componentType,
                        .bytes = buffer.bytes[view.byteOffset .. view.byteOffset + view.byteLength],
                        .stride = stride,
                    };
                } else primitives[pidx].texcoords[1] = null;

                if (gltf_primitive.attributes.COLOR_0) |aidx| {
                    const accessor = &accessors[aidx];

                    const vidx = accessor.bufferView;
                    const view = &bufferViews[vidx];
                    const buffer = buffers.items[view.buffer];

                    const accessor_type = std.meta.stringToEnum(
                        GltfJson.AccesorType,
                        accessor.type,
                    ) orelse return Error.FailedToParse;

                    const has_alpha = switch (accessor_type) {
                        .VEC3 => false,
                        .VEC4 => true,
                        else => return Error.InvalidAccessorType,
                    };

                    const stride = view.byteStride orelse blk: {
                        // accessor type enum is equivalent to element count.
                        const count: u32 = @intFromEnum(accessor_type);

                        break :blk switch (accessor.componentType) {
                            .UNSIGNED_BYTE => count,
                            .UNSIGNED_SHORT => count * @sizeOf(u16),
                            .FLOAT => count * @sizeOf(f32),
                            else => return Error.InvalidAttributeComponent,
                        };
                    };

                    primitives[pidx].color = .{
                        .float = accessor.componentType,
                        .has_alpha = has_alpha,
                        .bytes = buffer.bytes[view.byteOffset .. view.byteOffset + view.byteLength],
                        .stride = stride,
                    };
                }

                if (gltf_primitive.indices) |aidx| {
                    const accessor = &accessors[aidx];

                    const vidx = accessor.bufferView;
                    const view = &bufferViews[vidx];
                    const buffer = buffers.items[view.buffer];

                    const accessor_type = std.meta.stringToEnum(
                        GltfJson.AccesorType,
                        accessor.type,
                    ) orelse return Error.FailedToParse;

                    if (accessor_type != .SCALAR) {
                        return Error.InvalidAttributeType;
                    }

                    const stride = view.byteStride orelse blk: {
                        // accessor type enum is equivalent to element count.
                        const count: u32 = @intFromEnum(accessor_type);

                        break :blk switch (accessor.componentType) {
                            .UNSIGNED_BYTE => count * 1,
                            .UNSIGNED_INT => count * 4,
                            .UNSIGNED_SHORT => count * 2,
                            else => return Error.InvalidAttributeComponent,
                        };
                    };

                    // indices must provide a valid ElementArrayBuffer target
                    if (bufferViews[vidx].target) |target| {
                        switch (target) {
                            .ElementArrayBuffer => {},
                            else => return Error.InvalidIndexTarget,
                        }
                    }

                    primitives[pidx].indices = .{
                        .uint = accessor.componentType,
                        .bytes = buffer.bytes[view.byteOffset .. view.byteOffset + view.byteLength],
                        .stride = stride,
                    };
                }
            }

            try meshes.append(gpa, .{
                .name = gltf_mesh.name orelse "",
                .primitives = primitives,
            });
        }
    }

    return .{
        .json = parsed,
        .buffers = buffers,
        .images = images,
        .meshes = meshes,
        .samplers = json.samplers.?,
        .textures = json.textures.?,
        .materials = json.materials.?,
    };
}

pub fn deinit(self: *Gltf, gpa: Allocator) void {
    for (self.meshes.items) |mesh| {
        gpa.free(mesh.primitives);
    }
    self.meshes.deinit(gpa);

    for (self.buffers.items) |buffer| {
        gpa.free(buffer.bytes);
    }
    self.buffers.deinit(gpa);

    self.images.deinit(gpa);

    self.json.deinit();
}

// test "" {
//      Spec: that allows padding
//     std.debug.assert(buffer.bytes.len >= gltf_buffer.byteLength);
// }
