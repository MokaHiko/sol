const GltfLoader = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

const sol = @import("sol");

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

pub const Handedness = enum {
    Right,
    Left,
};

pub const Options = struct {
    handedness: Handedness = .Right,
};

const Buffer = struct {
    bytes: []u8,
    uri: []u8,
};

const Primitive = struct {
    const AttributeDecription = struct {
        type: Gltf.AccesorType,
        component: Gltf.ComponentType,
        bytes: []u8,
        stride: u32,
    };

    positions: ?AttributeDecription = null,
    normals: ?AttributeDecription = null,
};

const Mesh = struct {
    primitives: []Primitive,
    name: []const u8,
};

gltf: Gltf,
buffers: std.ArrayList(Buffer),
meshes: std.ArrayList(Buffer),

pub fn init(gpa: Allocator, path: []const u8) !GltfLoader {
    const json = try std.json.parseFromSlice(
        Gltf,
        gpa,
        @embedFile("DamagedHelmet/glTF/DamagedHelmet.gltf"),
        .{
            .ignore_unknown_fields = true,
        },
    );

    // TODO: Move json to deinit to keep metadata and string names
    defer json.deinit();

    const gltf: Gltf = json.value;

    // Queue load resources
    var buffers: std.ArrayList(Buffer) = if (gltf.buffers) |buffers| try .initCapacity(gpa, buffers.len) else .{};
    if (gltf.buffers) |gltf_buffers| {
        for (gltf_buffers) |gltf_buffer| {
            if (gltf_buffer.uri) |uri| {
                const dir = std.fs.path.dirname(path) orelse @panic("Unimplemented uri type");

                const file_path = try std.fs.path.join(
                    gpa,
                    &[_][]const u8{ dir, uri },
                );
                defer gpa.free(file_path);

                try buffers.append(gpa, .{
                    .uri = file_path,
                    .bytes = try sol.fs.read(gpa, file_path, .{}),
                });
            }
        }
    }

    const bufferViews = gltf.bufferViews orelse return Error.EmptyBufferViews;
    const accessors = gltf.accessors orelse return Error.EmptyAccessors;

    if (gltf.meshes) |gltf_meshes| {
        for (gltf_meshes) |gltf_mesh| {
            const primitives = try gpa.alloc(Primitive, gltf_mesh.primitives.len);

            for (gltf_mesh.primitives, 0..) |gltf_primitive, pidx| {
                if (gltf_primitive.attributes.POSITION) |aidx| {
                    const accessor = &accessors[aidx];

                    const vidx = accessor.bufferView;
                    const view = &bufferViews[vidx];
                    const buffer = buffers.items[view.buffer];

                    const accessor_type = std.meta.stringToEnum(
                        Gltf.AccesorType,
                        accessor.type,
                    ) orelse return Error.FailedToParse;

                    const stride = view.byteStride orelse blk: {
                        // accessor type enum is equivalent to element count.
                        const count: u32 = @intFromEnum(accessor_type);

                        break :blk switch (accessor.componentType) {
                            .FLOAT => count * 4,
                            else => @panic("Invalid POSITION format!"),
                        };
                    };

                    primitives[pidx].positions = .{
                        .component = accessor.componentType,
                        .type = accessor_type,
                        .bytes = buffer.bytes[view.byteOffset .. view.byteOffset + view.byteLength],
                        .stride = stride,
                    };
                }

                if (gltf_primitive.indices) |iidx| {
                    const vidx = accessors[iidx].bufferView;
                    sol.log.debug("buffer length {B}", .{bufferViews[vidx].byteLength});
                    // bufferViews[vidx].target // must be defined
                }
            }
        }
    }

    return .{
        .gltf = gltf,
        .buffers = buffers,
        .meshes = undefined,
    };
}

pub fn deinit(self: GltfLoader, gpa: Allocator) void {
    for (self.buffers.items) |buffer| {
        gpa.free(buffer.uri);
        gpa.free(buffer.bytes);
    }
    self.buffers.deinit(gpa);

    if (self.meshes.items) |mesh| {
        gpa.free(mesh.primitives);
    }
    self.meshes.deinit(gpa);
}

// test "" {
//      Spec: that allows padding
//     std.debug.assert(buffer.bytes.len >= gltf_buffer.byteLength);
// }
