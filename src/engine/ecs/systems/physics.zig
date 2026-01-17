//! Physics system for ECS.

const std = @import("std");
const Registry = @import("../manager.zig").Registry;
const World = @import("../../../world/world.zig").World;
const collision = @import("../../physics/collision.zig");
const math = @import("zig-math");
const Vec3 = math.Vec3;
const AABB = math.AABB;

pub const PhysicsSystem = struct {
    pub fn update(registry: *Registry, world: *World, delta_time: f32) void {
        const physics_store = &registry.physics;

        // Iterate over all entities with Physics component
        for (physics_store.components.items, physics_store.entities.items) |*phys, entity_id| {
            // Must also have Transform
            if (registry.transforms.getPtr(entity_id)) |transform| {

                // Apply gravity
                if (phys.use_gravity) {
                    const GRAVITY: f32 = 32.0;
                    phys.velocity.y -= GRAVITY * delta_time;
                }

                // Terminal velocity
                const TERMINAL_VELOCITY: f32 = 78.4;
                if (phys.velocity.y < -TERMINAL_VELOCITY) {
                    phys.velocity.y = -TERMINAL_VELOCITY;
                }

                // Calculate AABB for collision
                const center = transform.position.add(Vec3.init(0, phys.aabb_size.y * 0.5, 0));
                const size = phys.aabb_size;
                const aabb = AABB.fromCenterSize(center, size);

                // Perform collision
                const result = collision.moveAndCollide(world, aabb, phys.velocity, delta_time, .{});

                // Update position (convert back to feet position)
                transform.position = result.position.sub(Vec3.init(0, phys.aabb_size.y * 0.5, 0));
                phys.velocity = result.velocity;
                phys.grounded = result.grounded;
            }
        }
    }
};
