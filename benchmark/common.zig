const std = @import("std");
const names: []const []const u8 = @import("benchmark_names.zon");

pub const Entity = struct {
    counter: u32 = 0,
    name: ?[]const u8,
    random: f32,
    flag: bool,
};

/// Returns the number of nanoseconds per iteration the tested function took.
pub fn bench(T: type, comptime fn_name: []const u8, args: anytype, count: u64, stdout: *std.Io.Writer) !void {
    std.debug.print("benchmarking " ++ fn_name ++ " ({d} iters)...\n", .{count});
    var hash: usize = 0;
    var timer = try std.time.Timer.start();
    for (0..count) |i| {
        hash ^= try @field(T, fn_name)(args, i);
    }

    const elapsed = timer.read();
    try stdout.print(fn_name ++ "\t{d}\t", .{count});
    try fmtTime(stdout, elapsed);
    try stdout.print("\t", .{});
    try fmtTime(stdout, elapsed / count);
    try stdout.print("\t{x}\n", .{hash});
}

pub fn getEntities(allocator: std.mem.Allocator, rng: std.Random, count: usize) ![]const Entity {
    std.debug.print("pregenerating {d} entities...\n", .{count});
    const entities = try allocator.alloc(Entity, count);
    for (0..count) |i| {
        var name: ?[]const u8 = null;
        if (rng.boolean()) {
            name = names[rng.uintLessThan(usize, names.len)];
        }

        entities[i] = .{
            .name = name,
            .random = rng.float(f32),
            .flag = rng.boolean(),
        };
    }

    return entities;
}

pub fn getDespawnIndices(allocator: std.mem.Allocator, rng: std.Random, despawn_count: usize, entity_count: usize) ![]const usize {
    std.debug.print("pregenerating {d} despawn indices...\n", .{despawn_count});
    const indices = try allocator.alloc(usize, despawn_count);
    for (0..indices.len) |i| {
        indices[i] = rng.uintLessThan(usize, entity_count);
    }

    return indices;
}

fn fmtTime(writer: *std.Io.Writer, nanos: u64) !void {
    const seconds = nanos / std.time.ns_per_s;
    const millis = nanos / std.time.ns_per_ms;
    const micros = nanos / std.time.ns_per_us;
    if (seconds > 0) {
        try writer.print("{d}s", .{seconds});
    } else if (millis > 0) {
        try writer.print("{d}ms", .{millis});
    } else if (micros > 0) {
        try writer.print("{d}µs", .{micros});
    } else {
        try writer.print("{d}ns", .{nanos});
    }
}
