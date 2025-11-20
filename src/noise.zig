const std = @import("std");

// Simple 2D Perlin Noise implementation

pub const Perlin = struct {
    seed: u32,
    perm: [512]u8,

    pub fn init(seed: u32) Perlin {
        var p = Perlin{
            .seed = seed,
            .perm = undefined,
        };

        var prng = std.Random.DefaultPrng.init(seed);
        const rand = prng.random();

        var p_array: [256]u8 = undefined;
        for (0..256) |i| {
            p_array[i] = @intCast(i);
        }

        // Shuffle
        for (0..256) |i| {
            const j = rand.intRangeAtMost(usize, 0, 255);
            const temp = p_array[i];
            p_array[i] = p_array[j];
            p_array[j] = temp;
        }

        // Duplicate for overflow
        for (0..256) |i| {
            p.perm[i] = p_array[i];
            p.perm[i + 256] = p_array[i];
        }

        return p;
    }

    pub fn noise2d(self: Perlin, x: f32, y: f32) f32 {
        const X = @as(usize, @intCast(@as(i32, @intFromFloat(@floor(x))) & 255));
        const Y = @as(usize, @intCast(@as(i32, @intFromFloat(@floor(y))) & 255));

        const xf = x - @floor(x);
        const yf = y - @floor(y);

        const u = fade(xf);
        const v = fade(yf);

        const A = self.perm[X] + Y;
        const AA = self.perm[A];
        const AB = self.perm[A + 1];
        const B = self.perm[X + 1] + Y;
        const BA = self.perm[B];
        const BB = self.perm[B + 1];

        return lerp(
            lerp(grad(self.perm[AA], xf, yf), grad(self.perm[BA], xf - 1, yf), u),
            lerp(grad(self.perm[AB], xf, yf - 1), grad(self.perm[BB], xf - 1, yf - 1), u),
            v,
        );
    }

    fn fade(t: f32) f32 {
        return t * t * t * (t * (t * 6 - 15) + 10);
    }

    fn lerp(a: f32, b: f32, t: f32) f32 {
        return a + t * (b - a);
    }

    fn grad(hash: u8, x: f32, y: f32) f32 {
        const h = hash & 15;
        const u = if (h < 8) x else y;
        const v = if (h < 4) y else if (h == 12 or h == 14) x else 0; // Optimization? actually simple grad
        // Better grad for 2D:
        // 12 gradients: (1,1,0), (-1,1,0), (1,-1,0), (-1,-1,0), (1,0,1), (-1,0,1), (1,0,-1), (-1,0,-1), (0,1,1), (0,-1,1), (0,1,-1), (0,-1,-1)
        // But for 2D we really just need vectors in plane.
        // Simplified:
        return (if ((h & 1) == 0) u else -u) + (if ((h & 2) == 0) v else -v);
    }
};
