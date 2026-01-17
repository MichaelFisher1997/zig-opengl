//! Render system for ECS.
//! Currently renders entities as colored wireframe boxes.

const std = @import("std");
const Registry = @import("../manager.zig").Registry;
const rhi_pkg = @import("../../graphics/rhi.zig");
const RHI = rhi_pkg.RHI;
const Mat4 = @import("../../math/mat4.zig").Mat4;
const Vec3 = @import("../../math/vec3.zig").Vec3;
const Vertex = rhi_pkg.Vertex;

/// Reusing the wireframe cube generation from BlockOutline, but we might want
/// to move this to a shared utility later.
const LINE_THICKNESS: f32 = 0.025;

/// Create a vertex with the given position and color
fn makeVertex(x: f32, y: f32, z: f32, r: f32, g: f32, b: f32) Vertex {
    return .{
        .pos = .{ x, y, z },
        .color = .{ r, g, b },
        .normal = .{ 0, 1, 0 },
        .uv = .{ 0, 0 },
        .tile_id = 0,
        .skylight = 15,
        .blocklight = .{ 15, 15, 15 },
        .ao = 1.0,
    };
}

/// Vertices for a 1x1x1 cube (centered at 0.5, 0.5, 0.5 for scaling? No, let's center at 0,0,0)
/// Actually BlockOutline is 0..1. Let's stick to 0..1 and offset/scale via matrix.
const outline_vertices = blk: {
    const s: f32 = 0.0;
    const e: f32 = 1.0;
    const t: f32 = LINE_THICKNESS;

    // 12 edges * 4 quads per edge * 6 verts per quad = 288 vertices
    // We'll just reuse the logic but with 0..1 range
    var verts: [288]Vertex = undefined;
    var idx: usize = 0;

    const addQuad = struct {
        fn f(v: *[288]Vertex, i: *usize, p0: Vertex, p1: Vertex, p2: Vertex, p3: Vertex) void {
            v[i.*] = p0;
            i.* += 1;
            v[i.*] = p1;
            i.* += 1;
            v[i.*] = p2;
            i.* += 1;
            v[i.*] = p0;
            i.* += 1;
            v[i.*] = p2;
            i.* += 1;
            v[i.*] = p3;
            i.* += 1;
        }
    }.f;

    const addEdge = struct {
        fn f(v: *[288]Vertex, i: *usize, x0: f32, y0: f32, z0: f32, x1: f32, y1: f32, z1: f32, t1x: f32, t1y: f32, t1z: f32, t2x: f32, t2y: f32, t2z: f32) void {
            const addDSQuad = struct {
                fn g(v_arr: *[288]Vertex, idx_ptr: *usize, c0: Vertex, c1: Vertex, c2: Vertex, c3: Vertex) void {
                    addQuad(v_arr, idx_ptr, c0, c1, c2, c3);
                    addQuad(v_arr, idx_ptr, c0, c3, c2, c1);
                }
            }.g;

            // Quad 1
            const q1_c0 = makeVertex(x0, y0, z0, 1, 1, 1);
            const q1_c1 = makeVertex(x1, y1, z1, 1, 1, 1);
            const q1_c2 = makeVertex(x1 + t1x, y1 + t1y, z1 + t1z, 1, 1, 1);
            const q1_c3 = makeVertex(x0 + t1x, y0 + t1y, z0 + t1z, 1, 1, 1);
            addDSQuad(v, i, q1_c0, q1_c1, q1_c2, q1_c3);

            // Quad 2
            const q2_c0 = makeVertex(x0, y0, z0, 1, 1, 1);
            const q2_c1 = makeVertex(x1, y1, z1, 1, 1, 1);
            const q2_c2 = makeVertex(x1 + t2x, y1 + t2y, z1 + t2z, 1, 1, 1);
            const q2_c3 = makeVertex(x0 + t2x, y0 + t2y, z0 + t2z, 1, 1, 1);
            addDSQuad(v, i, q2_c0, q2_c1, q2_c2, q2_c3);
        }
    }.f;

    // Bottom face (y=0)
    addEdge(&verts, &idx, s, s, s, e, s, s, 0, t, 0, 0, 0, t);
    addEdge(&verts, &idx, e, s, s, e, s, e, 0, t, 0, -t, 0, 0);
    addEdge(&verts, &idx, e, s, e, s, s, e, 0, t, 0, 0, 0, -t);
    addEdge(&verts, &idx, s, s, e, s, s, s, 0, t, 0, t, 0, 0);

    // Top face (y=1)
    addEdge(&verts, &idx, s, e, s, e, e, s, 0, -t, 0, 0, 0, t);
    addEdge(&verts, &idx, e, e, s, e, e, e, 0, -t, 0, -t, 0, 0);
    addEdge(&verts, &idx, e, e, e, s, e, e, 0, -t, 0, 0, 0, -t);
    addEdge(&verts, &idx, s, e, e, s, e, s, 0, -t, 0, t, 0, 0);

    // Verticals
    addEdge(&verts, &idx, s, s, s, s, e, s, t, 0, 0, 0, 0, t);
    addEdge(&verts, &idx, e, s, s, e, e, s, -t, 0, 0, 0, 0, t);
    addEdge(&verts, &idx, e, s, e, e, e, e, -t, 0, 0, 0, 0, -t);
    addEdge(&verts, &idx, s, s, e, s, e, e, t, 0, 0, 0, 0, -t);

    break :blk verts;
};

pub const RenderSystem = struct {
    buffer_handle: rhi_pkg.BufferHandle,
    rhi: RHI,

    pub fn init(rhi: RHI) RenderSystem {
        const buffer = rhi.createBuffer(@sizeOf(@TypeOf(outline_vertices)), .vertex);
        rhi.uploadBuffer(buffer, std.mem.asBytes(&outline_vertices));

        return .{
            .buffer_handle = buffer,
            .rhi = rhi,
        };
    }

    pub fn deinit(self: *RenderSystem) void {
        if (self.buffer_handle != rhi_pkg.InvalidBufferHandle) {
            self.rhi.destroyBuffer(self.buffer_handle);
            self.buffer_handle = rhi_pkg.InvalidBufferHandle;
        }
    }

    pub fn render(self: *RenderSystem, registry: *Registry, camera_pos: Vec3) void {
        const meshes = &registry.meshes;

        for (meshes.components.items, meshes.entities.items) |*mesh, entity_id| {
            if (!mesh.visible) continue;

            if (registry.transforms.getPtr(entity_id)) |transform| {
                // Determine size from physics if available, otherwise default 1x1x1
                var size = Vec3.one;
                var offset = Vec3.zero;

                if (registry.physics.getPtr(entity_id)) |phys| {
                    size = phys.aabb_size;
                    // Physics position is at the feet (bottom center)
                    // Mesh vertex data is 0..1
                    // So we want to translate to position - (size.x/2, 0, size.z/2)
                    offset = Vec3.init(-size.x / 2.0, 0, -size.z / 2.0);
                }

                // Calculate relative position to camera
                const rel_pos = transform.position.add(offset).sub(camera_pos);

                // Create model matrix: Translate * Scale
                // Note: Matrices are column-major usually, or we chain them T * R * S
                const model = Mat4.translate(rel_pos).multiply(Mat4.scale(size));

                // Set color uniform (using a specialized uniform or reusing one?)
                // Since we don't have a custom shader easily plugged in here without RHI changes,
                // we'll rely on vertex colors which are white in the buffer.
                // Wait, I hardcoded white (1,1,1) in makeVertex.
                // If we want custom colors we need to update uniforms or use instance attributes.
                // For now, let's just draw white wireframes.
                // TODO: Add support for entity color via uniform.

                self.rhi.setModelMatrix(model, 0); // Mesh ID 0 (standard block shader?)
                self.rhi.draw(self.buffer_handle, 288, .triangles);
            }
        }
    }
};
