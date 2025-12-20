const Vec3 = @import("vec3.zig").Vec3;

/// Axis-Aligned Bounding Box for collision detection
pub const AABB = struct {
    min: Vec3,
    max: Vec3,

    pub fn init(min: Vec3, max: Vec3) AABB {
        return .{ .min = min, .max = max };
    }

    pub fn fromCenterSize(c: Vec3, s: Vec3) AABB {
        const half = s.scale(0.5);
        return .{
            .min = c.sub(half),
            .max = c.add(half),
        };
    }

    pub fn center(self: AABB) Vec3 {
        return self.min.add(self.max).scale(0.5);
    }

    pub fn size(self: AABB) Vec3 {
        return self.max.sub(self.min);
    }

    pub fn contains(self: AABB, point: Vec3) bool {
        return point.x >= self.min.x and point.x <= self.max.x and
            point.y >= self.min.y and point.y <= self.max.y and
            point.z >= self.min.z and point.z <= self.max.z;
    }

    pub fn intersects(self: AABB, other: AABB) bool {
        return self.min.x <= other.max.x and self.max.x >= other.min.x and
            self.min.y <= other.max.y and self.max.y >= other.min.y and
            self.min.z <= other.max.z and self.max.z >= other.min.z;
    }

    pub fn expand(self: AABB, amount: Vec3) AABB {
        return .{
            .min = self.min.sub(amount),
            .max = self.max.add(amount),
        };
    }

    pub fn translate(self: AABB, offset: Vec3) AABB {
        return .{
            .min = self.min.add(offset),
            .max = self.max.add(offset),
        };
    }
};
