//! Simplex/Perlin noise implementation for terrain generation.

const std = @import("std");

pub const Noise = struct {
    seed: u64,

    // Permutation table
    perm: [512]u8,

    pub fn init(seed: u64) Noise {
        var noise = Noise{
            .seed = seed,
            .perm = undefined,
        };

        // Initialize permutation table
        var prng = std.Random.DefaultPrng.init(seed);
        const random = prng.random();

        // Fill first 256 entries
        for (0..256) |i| {
            noise.perm[i] = @intCast(i);
        }

        // Shuffle
        for (0..256) |i| {
            const j = random.intRangeAtMost(usize, 0, 255);
            const tmp = noise.perm[i];
            noise.perm[i] = noise.perm[j];
            noise.perm[j] = tmp;
        }

        // Duplicate for overflow
        for (0..256) |i| {
            noise.perm[256 + i] = noise.perm[i];
        }

        return noise;
    }

    /// 2D Perlin noise, returns value in range [-1, 1]
    pub fn perlin2D(self: *const Noise, x: f32, y: f32) f32 {
        // Find unit grid cell
        const xi: i32 = @intFromFloat(@floor(x));
        const yi: i32 = @intFromFloat(@floor(y));

        // Get relative position in cell
        const xf = x - @floor(x);
        const yf = y - @floor(y);

        // Fade curves
        const u = fade(xf);
        const v = fade(yf);

        // Hash coordinates of corners
        const aa = self.perm[@intCast(@mod(xi, 256) + self.perm[@intCast(@mod(yi, 256))])];
        const ab = self.perm[@intCast(@mod(xi, 256) + self.perm[@intCast(@mod(yi + 1, 256))])];
        const ba = self.perm[@intCast(@mod(xi + 1, 256) + self.perm[@intCast(@mod(yi, 256))])];
        const bb = self.perm[@intCast(@mod(xi + 1, 256) + self.perm[@intCast(@mod(yi + 1, 256))])];

        // Gradient dot products
        const g1 = grad2D(aa, xf, yf);
        const g2 = grad2D(ba, xf - 1, yf);
        const g3 = grad2D(ab, xf, yf - 1);
        const g4 = grad2D(bb, xf - 1, yf - 1);

        // Interpolate
        const x1 = lerp(g1, g2, u);
        const x2 = lerp(g3, g4, u);

        return lerp(x1, x2, v);
    }

    /// Fractal Brownian Motion - multiple octaves of noise
    pub fn fbm2D(self: *const Noise, x: f32, y: f32, octaves: u32, lacunarity: f32, persistence: f32) f32 {
        var total: f32 = 0;
        var frequency: f32 = 1;
        var amplitude: f32 = 1;
        var max_value: f32 = 0;

        for (0..octaves) |_| {
            total += self.perlin2D(x * frequency, y * frequency) * amplitude;
            max_value += amplitude;
            amplitude *= persistence;
            frequency *= lacunarity;
        }

        return total / max_value;
    }

    /// Get height value normalized to 0-1 range
    pub fn getHeight(self: *const Noise, x: f32, z: f32, scale: f32) f32 {
        const noise_val = self.fbm2D(x / scale, z / scale, 4, 2.0, 0.5);
        return (noise_val + 1.0) * 0.5; // Convert from [-1,1] to [0,1]
    }
};

fn fade(t: f32) f32 {
    // 6t^5 - 15t^4 + 10t^3
    return t * t * t * (t * (t * 6 - 15) + 10);
}

fn lerp(a: f32, b: f32, t: f32) f32 {
    return a + t * (b - a);
}

fn grad2D(hash: u8, x: f32, y: f32) f32 {
    // Use lower 2 bits to select gradient direction
    return switch (hash & 3) {
        0 => x + y,
        1 => -x + y,
        2 => x - y,
        3 => -x - y,
        else => unreachable,
    };
}
