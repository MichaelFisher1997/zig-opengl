//! Component definitions.

const std = @import("std");
const math = @import("zig-math");
const Vec3 = math.Vec3;
const AABB = math.AABB;

pub const Transform = struct {
    position: Vec3,
    rotation: Vec3 = Vec3.zero, // Euler angles (pitch, yaw, roll)
    scale: Vec3 = Vec3.one,
};

pub const Physics = struct {
    velocity: Vec3 = Vec3.zero,
    acceleration: Vec3 = Vec3.zero,
    aabb_size: Vec3, // Width, Height, Depth relative to position
    grounded: bool = false,
    use_gravity: bool = true,
};

pub const Mesh = struct {
    /// For now, just a color for debug rendering
    color: Vec3 = Vec3.init(1.0, 0.0, 1.0), // Magenta by default
    visible: bool = true,
};

pub const AI = struct {
    state: AIState = .idle,
    target_pos: ?Vec3 = null,
    move_speed: f32 = 2.0,
};

pub const AIState = enum {
    idle,
    wandering,
    chasing,
    fleeing,
};
