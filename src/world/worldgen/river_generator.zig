const noise_sampler_mod = @import("noise_sampler.zig");
const NoiseSampler = noise_sampler_mod.NoiseSampler;

/// River channel detector used by terrain generation.
pub const RiverGenerator = struct {
    pub fn init() RiverGenerator {
        return .{};
    }

    pub fn getMask(self: *const RiverGenerator, noise_sampler: *const NoiseSampler, x: f32, z: f32, reduction: u8) f32 {
        _ = self;
        return noise_sampler.getRiverMask(x, z, reduction);
    }
};
