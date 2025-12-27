const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zig_math = b.createModule(.{
        .root_source_file = b.path("libs/zig-math/math.zig"),
        .target = target,
        .optimize = optimize,
    });

    const zig_noise = b.createModule(.{
        .root_source_file = b.path("libs/zig-noise/noise.zig"),
        .target = target,
        .optimize = optimize,
    });

    const root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    root_module.addImport("zig-math", zig_math);
    root_module.addImport("zig-noise", zig_noise);

    const exe = b.addExecutable(.{
        .name = "zig-triangle",
        .root_module = root_module,
    });

    exe.linkLibC();

    exe.linkSystemLibrary("sdl3");
    exe.linkSystemLibrary("glew");
    exe.linkSystemLibrary("gl");
    exe.linkSystemLibrary("vulkan");

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const test_root_module = b.createModule(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_root_module.addImport("zig-math", zig_math);
    test_root_module.addImport("zig-noise", zig_noise);

    const exe_tests = b.addTest(.{
        .root_module = test_root_module,
    });
    exe_tests.linkLibC();

    const test_step = b.step("test", "Run unit tests");
    const run_exe_tests = b.addRunArtifact(exe_tests);
    test_step.dependOn(&run_exe_tests.step);

    const integration_root_module = b.createModule(.{
        .root_source_file = b.path("src/integration_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    integration_root_module.addImport("zig-math", zig_math);
    integration_root_module.addImport("zig-noise", zig_noise);

    const exe_integration_tests = b.addTest(.{
        .root_module = integration_root_module,
    });
    exe_integration_tests.linkLibC();
    exe_integration_tests.linkSystemLibrary("sdl3");
    exe_integration_tests.linkSystemLibrary("glew");
    exe_integration_tests.linkSystemLibrary("gl");
    exe_integration_tests.linkSystemLibrary("vulkan");

    const test_integration_step = b.step("test-integration", "Run integration smoke test");
    const run_integration_tests = b.addRunArtifact(exe_integration_tests);
    test_integration_step.dependOn(&run_integration_tests.step);
}
