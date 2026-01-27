//! glTF 2.0 JSON Definitions and Parser
//!
//! This file defines Zig structs that directly mirror the glTF 2.0 JSON schema
//! and provides basic loading and parsing of `.gltf` files using `std.json`.
//!
//! This is a spec-mirroring layer focused on lossless deserialization.
//! The types here are not intended for runtime or engine use.
//!
//! Goals:
//! - 1:1 mapping with glTF 2.0 JSON fields
//! - Preserve optional fields, extensions, and extras
//! - Minimal interpretation at parse time
//!
//! Validation, buffer decoding, sparse resolution, and rendering logic
//! are expected to live outside this module.
//!
//! Spec: https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html
//!
//! MISSING FEATURES:
//! - Buffer:
//!     - Embedded URI
//! - Geometry:
//!     - Meshes:
//!         - skin
//!     - Morph Targets
//! - Animation:
//! - Camera:
//! - Extensions
//! - Extras
const Gltf = @This();

const std = @import("std");

asset: struct {
    /// The glTF version in the form of <major>.<minor> that this asset targets.
    version: []u8,

    /// The minimum glTF version in the form of <major>.<minor> that this asset targets. This property MUST NOT be greater than the asset version.
    minVersion: ?[]const u8 = null,

    /// Tool that generated this glTF model. Useful for debugging.
    generator: ?[]const u8 = null,

    /// A copyright message suitable for display to credit the content creator.
    copyright: ?[]const u8 = null,

    /// JSON object with extension-specific objects.
    extension: ?std.json.Value = null,

    /// Application-specific data.
    extras: ?std.json.Value = null,
},

// Identifies which of the scenes in the array SHOULD be displayed at load time.
scene: ?u32 = null,

/// the set of visual objects to render.
scenes: ?[]struct {
    /// The user-defined name of this scene.
    name: []const u8,

    /// Indices into the nodes array.
    nodes: []u32,
} = null,

nodes: ?[]struct {
    /// The user-defined name of this node.
    name: ?[]const u8 = null,

    children: ?u32 = null,

    matrix: ?[16]f32 = null,

    translation: ?[3]f32 = null,
    scale: ?[3]f32 = null,

    /// quat : xyzw
    rotation: ?[4]f32 = null,

    mesh: struct {
        const Attributes = enum(u32) {
            /// Unitless XYZ vertex positions.
            POSITION,

            /// Normalized XYZ vertex normals.
            NORMAL,

            /// XYZW vertex tangents where the XYZ portion is normalized,
            /// and the W component is a sign value (1 or +1) indicating handedness of the tangent basis.
            ///
            /// When tangents are not specified, client implementations SHOULD calculate tangents using default MikkTSpace
            /// algorithms with the specified vertex positions, normals, and texture coordinates associated with the normal texture.
            TANGENT,

            /// ST texture coordinates.
            TEXCOORDS_N,

            JOINTS_N,

            WEIGHTS_N,

            _,
        };

        primitives: struct {
            /// A plain JSON object, where each key corresponds to a mesh attribute semantic
            /// and each value is the index of the accessor containing attribute’s data.
            primitives: std.json.Value,

            indices: u32,
            material: ?u32 = null,
            mode: ?u32 = null,
        },
    },
},

textures: ?[]struct {
    /// If not present, provided by extension.
    source: ?u32,

    /// If not present, repeated wrapping sampler must be provided.
    sampler: ?u32,
},

images: ?[]struct {},

/// glTF 2.0 — Buffers and Buffer Views
/// https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html#buffers-and-buffer-views
/// A buffer points to binary geometry, animation, or skins.
buffers: ?[]struct {
    /// The URI (or IRI) of the buffer.
    uri: ?[]const u8,

    /// The length of the buffer in bytes.
    byteLength: u32,

    /// The user-defined name of this object.
    name: ?[]const u8 = null,

    /// JSON object with extension-specific objects.
    extension: ?std.json.Value = null,

    /// Application-specific data.
    extras: ?std.json.Value = null,
} = null,

/// glTF 2.0 — Buffers and Buffer Views
/// https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html#buffers-and-buffer-views
/// A view into a buffer generally representing a subset of the buffer.
bufferViews: ?[]struct {
    const ViewTarget = enum(i32) {
        ArrayBuffer = 34962,
        ElementArrayBuffer = 34963,
    };

    /// The index of the buffer.
    buffer: u32,

    /// The offset into the buffer in bytes.
    byteOffset: u32 = 0,

    byteLength: u32,

    /// Indicates stride for vertex attirbutes, only.
    ///
    /// When byteStride of the referenced bufferView is not defined, it means that accessor elements are tightly packed,
    /// i.e., effective stride equals the size of the element.
    byteStride: ?u32 = null,

    /// The hint representing the intended GPU buffer type to use with this buffer view.
    target: ?ViewTarget = null,

    /// The user-defined name of this object.
    name: ?[]const u8 = null,

    /// JSON object with extension-specific objects.
    extension: ?std.json.Value = null,

    /// Application-specific data.
    extras: ?std.json.Value = null,
} = null,

/// glTF 2.0 — Accessor Sparse Storage
/// https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html#accessors
/// A typed view into a buffer view that contains raw binary data.
accessors: ?[]struct {
    const ComponentType = enum(i32) {
        BYTE = 5120,
        UNSIGNED_BYTE = 5121,
        SHORT = 5122,
        UNSIGNED_SHORT = 5123,
        UNSIGNED_INT = 5125,
        FLOAT = 5126,
    };

    const Type = enum {
        SCALAR,
        VEC2,
        VEC3,
        VEC4,
        MAT2,
        MAT3,
        MAT4,
    };

    /// The index of the bufferView.
    bufferView: u32,

    /// The offset relative to the start of the buffer view in bytes.
    byteOffset: u32 = 0,

    /// The datatype of the accessor’s components.
    componentType: ComponentType,

    /// Specifies whether integer data values are normalized before usage.
    normalized: bool = false,

    /// The number of elements referenced by this accessor.
    count: u32,

    /// Specifies if the accessor’s elements are scalars, vectors, or matrices.
    ///
    /// Raw string value from glTF JSON (e.g. "SCALAR", "VEC3").
    /// Parsed into `Type` during validation.
    type: []const u8,

    /// Maximum value of each component in this accessor.
    ///
    /// Must be of type `Type`.
    max: ?[]std.json.Value = null,

    /// Minimum value of each component in this accessor.
    ///
    /// Must be of type `Type`.
    min: ?[]std.json.Value = null,

    /// glTF 2.0 — Accessor Sparse Storage
    /// https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html#sparse-accessors
    sparse: ?struct {
        /// Number of deviating accessor values stored in the sparse array.
        count: u32,

        /// An object pointing to a buffer view containing the indices of deviating accessor values. T
        indices: struct {
            /// The index of the buffer view with sparse indices. T
            bufferView: u32,
            /// The offset relative to the start of the buffer view in bytes.
            byteoffset: u32 = 0,
            /// The indices data type.
            componentType: ComponentType,

            /// JSON object with extension-specific objects.
            extension: ?std.json.Value = null,

            /// Application-specific data.
            extras: ?std.json.Value = null,
        },

        /// An object pointing to a buffer view containing the deviating accessor values.
        values: struct {
            /// The index of the buffer view with sparse indices. T
            bufferView: u32,
            /// The offset relative to the start of the buffer view in bytes.
            byteoffset: u32 = 0,
            /// The indices data type.
            componentType: ComponentType,

            /// JSON object with extension-specific objects.
            extension: ?std.json.Value = null,

            /// Application-specific data.
            extras: ?std.json.Value = null,
        },

        /// JSON object with extension-specific objects.
        extension: ?std.json.Value = null,

        /// Application-specific data.
        extras: ?std.json.Value = null,
    } = null,

    name: ?[]const u8 = null,
},

/// /// JSON object with extension-specific objects.
/// extension: ?std.json.Value = null,
///
/// /// Application-specific data.
/// extras: ?std.json.Value = null,
pub const Handedness = enum {
    Right,
    Left,
};

pub const LoadOptions = struct {
    handedness: Handedness = .Right,
};

pub fn loadFromFile() !Gltf {
    const native_endian = @import("builtin").target.cpu.arch.endian();

    switch (native_endian) {
        .little => {},
        else => @panic("Big Endian machines are unsupported!"),
    }

    // TODO: Check if gltf has minVersion and if minVersin is supported
    return .{};
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const allocator = gpa.allocator();

    const gltf_json = try std.json.parseFromSlice(
        Gltf,
        allocator,
        @embedFile("DamagedHelmet/glTF/DamagedHelmet.gltf"),
        .{
            .ignore_unknown_fields = true,
        },
    );
    defer gltf_json.deinit();

    if (gltf_json.value.buffers) |buffers| {
        if (buffers[0].uri) |uri| {
            std.log.debug("{s}", .{uri});
        }
    }

    if (gltf_json.value.bufferViews) |views| {
        if (views[0].target) |target| {
            std.log.debug("{s}", .{@tagName(target)});
        }
    }
}
