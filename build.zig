const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    _ = b.addModule("zoinks", .{
        .root_source_file = b.path("src/root.zig"),
        .optimize = optimize,
        .target = target,
    });

    const test_module = b.createModule(.{
        .root_source_file = b.path("src/tests.zig"),
        .optimize = optimize,
        .target = target,
    });

    const test_exe = b.addTest(.{ .root_module = test_module });
    const run_tests = b.addRunArtifact(test_exe);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests.step);
}
