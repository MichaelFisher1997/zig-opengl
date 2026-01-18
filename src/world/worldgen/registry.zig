const std = @import("std");
const gen_interface = @import("generator_interface.zig");
const Generator = gen_interface.Generator;
const OverworldGenerator = @import("overworld_generator.zig").OverworldGenerator;
const FlatWorldGenerator = @import("flat_world.zig").FlatWorldGenerator;

pub const RegistryError = error{
    InvalidGeneratorIndex,
    OutOfMemory,
};

pub const GeneratorType = struct {
    info: gen_interface.GeneratorInfo,
    initFn: *const fn (seed: u64, allocator: std.mem.Allocator) anyerror!Generator,
};

pub const GENERATORS = [_]GeneratorType{
    .{
        .info = OverworldGenerator.INFO,
        .initFn = initOverworld,
    },
    .{
        .info = FlatWorldGenerator.INFO,
        .initFn = initFlatWorld,
    },
};

fn initOverworld(seed: u64, allocator: std.mem.Allocator) anyerror!Generator {
    const gen = try allocator.create(OverworldGenerator);
    gen.* = OverworldGenerator.init(seed, allocator);
    return gen.generator();
}

fn initFlatWorld(seed: u64, allocator: std.mem.Allocator) anyerror!Generator {
    const gen = try allocator.create(FlatWorldGenerator);
    gen.* = FlatWorldGenerator.init(seed, allocator);
    return gen.generator();
}

pub fn getGeneratorCount() usize {
    return GENERATORS.len;
}

pub fn getGeneratorInfo(index: usize) gen_interface.GeneratorInfo {
    std.debug.assert(index < GENERATORS.len);
    return GENERATORS[index].info;
}

pub fn createGenerator(index: usize, seed: u64, allocator: std.mem.Allocator) anyerror!Generator {
    if (index >= GENERATORS.len) return error.InvalidGeneratorIndex;
    return GENERATORS[index].initFn(seed, allocator) catch |err| {
        std.log.err("Generator initialization failed for index {}: {}", .{ index, err });
        return err;
    };
}
