const std = @import("std");
const zoinks = @import("zoinks");
const ecs = @import("ecs.zig");
const concurrent = @import("concurrent.zig");

const Self = @This();
const page_allocator = std.heap.page_allocator;

var stdout: *std.Io.Writer = undefined;

pub fn main() !void {
    const spawn_iter_count = try getEnvNum("SPAWN_ITER", 1_000_000);
    const query_iter_count = try getEnvNum("QUERY_ITER", 1_000);

    // --- SETUP --- \\
    const stdout_buffer = try page_allocator.alloc(u8, 1_048_576);
    defer page_allocator.free(stdout_buffer);

    var stdout_writer = std.fs.File.stdout().writer(stdout_buffer);
    stdout = &stdout_writer.interface;

    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();

    var rng = std.Random.DefaultPrng.init(@intCast(std.time.microTimestamp()));
    try stdout.print("function\tinvocation count\telapsed time\tavg. per invocation\thash\n", .{});
    try ecs.bench(gpa.allocator(), rng.random(), spawn_iter_count, query_iter_count, stdout);
    try concurrent.bench(gpa.allocator(), rng.random(), spawn_iter_count, stdout);
    try stdout.flush();
}

fn getEnvNum(name: []const u8, default_value: u64) !u64 {
    var buffer: [1024]u8 = undefined; // 1KB ought to be enough for anyone!
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const env = std.process.getEnvVarOwned(fba.allocator(), name) catch return default_value;
    return try std.fmt.parseInt(u64, env, 10);
}
