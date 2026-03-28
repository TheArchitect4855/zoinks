const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const zoinks = b.addModule("zoinks", .{
        .root_source_file = b.path("src/root.zig"),
        .optimize = optimize,
        .target = target,
    });

    const bench_module = b.createModule(.{
        .root_source_file = b.path("benchmark/main.zig"),
        .optimize = optimize,
        .target = target,
        .imports = &.{
            .{ .name = "zoinks", .module = zoinks },
        },
    });

    const bench_exe = b.addExecutable(.{ .name = "benchmark", .root_module = bench_module });
    const bench_install = b.addInstallArtifact(bench_exe, .{});
    const run_bench = b.addRunArtifact(bench_exe);
    run_bench.step.dependOn(&bench_install.step);
    const bench_step = b.step("bench", "Run benchmark");
    bench_step.dependOn(&run_bench.step);

    const test_module = b.createModule(.{
        .root_source_file = b.path("src/tests/root.zig"),
        .optimize = optimize,
        .target = target,
        .imports = &.{
            .{ .name = "zoinks", .module = zoinks },
        },
    });

    const test_exe = b.addTest(.{ .root_module = test_module });
    const run_tests = b.addRunArtifact(test_exe);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests.step);
}
