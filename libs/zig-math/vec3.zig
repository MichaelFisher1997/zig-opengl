const std = @import("std");

pub const Vec3 = struct {
    x: f32,
    y: f32,
    z: f32,

    pub const zero = Vec3{ .x = 0, .y = 0, .z = 0 };
    pub const one = Vec3{ .x = 1, .y = 1, .z = 1 };
    pub const up = Vec3{ .x = 0, .y = 1, .z = 0 };
    pub const down = Vec3{ .x = 0, .y = -1, .z = 0 };
    pub const forward = Vec3{ .x = 0, .y = 0, .z = -1 };
    pub const back = Vec3{ .x = 0, .y = 0, .z = 1 };
    pub const right = Vec3{ .x = 1, .y = 0, .z = 0 };
    pub const left = Vec3{ .x = -1, .y = 0, .z = 0 };

    pub fn init(x: f32, y: f32, z: f32) Vec3 {
        return .{ .x = x, .y = y, .z = z };
    }

    pub fn add(self: Vec3, other: Vec3) Vec3 {
        return .{
            .x = self.x + other.x,
            .y = self.y + other.y,
            .z = self.z + other.z,
        };
    }

    pub fn sub(self: Vec3, other: Vec3) Vec3 {
        return .{
            .x = self.x - other.x,
            .y = self.y - other.y,
            .z = self.z - other.z,
        };
    }

    pub fn scale(self: Vec3, scalar: f32) Vec3 {
        return .{
            .x = self.x * scalar,
            .y = self.y * scalar,
            .z = self.z * scalar,
        };
    }

    pub fn dot(self: Vec3, other: Vec3) f32 {
        return self.x * other.x + self.y * other.y + self.z * other.z;
    }

    pub fn cross(self: Vec3, other: Vec3) Vec3 {
        return .{
            .x = self.y * other.z - self.z * other.y,
            .y = self.z * other.x - self.x * other.z,
            .z = self.x * other.y - self.y * other.x,
        };
    }

    pub fn length(self: Vec3) f32 {
        return std.math.sqrt(self.lengthSquared());
    }

    pub fn lengthSquared(self: Vec3) f32 {
        return self.dot(self);
    }

    pub fn normalize(self: Vec3) Vec3 {
        const len = self.length();
        if (len == 0) return Vec3.zero;
        return self.scale(1.0 / len);
    }

    pub fn negate(self: Vec3) Vec3 {
        return .{ .x = -self.x, .y = -self.y, .z = -self.z };
    }

    pub fn lerp(self: Vec3, other: Vec3, t: f32) Vec3 {
        return self.add(other.sub(self).scale(t));
    }

    pub fn distance(self: Vec3, other: Vec3) f32 {
        return self.sub(other).length();
    }

    pub fn toArray(self: Vec3) [3]f32 {
        return .{ self.x, self.y, self.z };
    }

    pub fn toLinear(self: Vec3) Vec3 {
        return .{
            .x = std.math.pow(f32, self.x, 2.2),
            .y = std.math.pow(f32, self.y, 2.2),
            .z = std.math.pow(f32, self.z, 2.2),
        };
    }
};
