const std = @import("std");
const zoinks = @import("root.zig");
const names: []const []const u8 = @import("benchmark_names.zon");

const Ecs = zoinks.Ecs(struct {
    counter: u32 = 0,
    name: ?[]const u8,
    random: f32,
    flag: bool,
});

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

    var ecs = Ecs.init(gpa.allocator());
    defer ecs.deinit();

    var rng = std.Random.DefaultPrng.init(@intCast(std.time.microTimestamp()));
    const pregenerated_entities = try getEntities(page_allocator, rng.random(), spawn_iter_count);
    defer page_allocator.free(pregenerated_entities);

    const despawn_indices = try getDespawnIndices(page_allocator, rng.random(), spawn_iter_count / 2, spawn_iter_count);
    defer page_allocator.free(despawn_indices);

    try stdout.print("function\tinvocation count\telapsed time\tavg. per invocation\thash\n", .{});

    // --- BENCHMARKS --- \\
    try bench("benchSpawn", .{ .ecs = &ecs, .entities = pregenerated_entities }, spawn_iter_count);
    try bench("benchQueryEmpty", .{ .ecs = &ecs }, query_iter_count);
    try bench("benchQueryFlag", .{ .ecs = &ecs }, query_iter_count);
    try bench("benchQueryName", .{ .ecs = &ecs }, query_iter_count);
    try bench("benchCounter", .{ .ecs = &ecs }, query_iter_count);
    try bench("benchSum", .{ .ecs = &ecs }, query_iter_count);
    try bench("benchFlag", .{ .ecs = &ecs }, query_iter_count);
    try bench("benchSearchFlag", .{ .ecs = &ecs }, query_iter_count);
    try bench("benchSearchRandomValue", .{ .ecs = &ecs }, query_iter_count);
    try bench("benchDespawn", .{ .ecs = &ecs }, spawn_iter_count);

    try bench("benchSpawn", .{ .ecs = &ecs, .entities = pregenerated_entities }, spawn_iter_count);
    try bench("benchDespawnRandom", .{ .ecs = &ecs, .indices = despawn_indices }, despawn_indices.len);
    try bench("benchQueryEmpty", .{ .ecs = &ecs }, query_iter_count);
    try bench("benchQueryFlag", .{ .ecs = &ecs }, query_iter_count);
    try bench("benchQueryName", .{ .ecs = &ecs }, query_iter_count);
    try bench("benchCounter", .{ .ecs = &ecs }, query_iter_count);
    try bench("benchSum", .{ .ecs = &ecs }, query_iter_count);
    try bench("benchFlag", .{ .ecs = &ecs }, query_iter_count);
    try bench("benchSearchFlag", .{ .ecs = &ecs }, query_iter_count);
    try bench("benchSearchRandomValue", .{ .ecs = &ecs }, query_iter_count);

    try stdout.flush();
}

/// Returns the number of nanoseconds per iteration the tested function took.
fn bench(comptime fn_name: []const u8, args: anytype, count: u64) !void {
    std.debug.print("benchmarking " ++ fn_name ++ " ({d} iters)...\n", .{count});
    var hash: usize = 0;
    var timer = try std.time.Timer.start();
    for (0..count) |i| {
        hash ^= try @field(Self, fn_name)(args, i);
    }

    const elapsed = timer.read();
    try stdout.print(fn_name ++ "\t{d}\t", .{count});
    try fmtTime(stdout, elapsed);
    try stdout.print("\t", .{});
    try fmtTime(stdout, elapsed / count);
    try stdout.print("\t{x}\n", .{hash});
}

inline fn benchFlag(args: anytype, _: usize) !usize {
    const ecs: *Ecs = args.ecs;
    var query = try ecs.query(struct { flag: bool });
    defer query.deinit();

    var a: u32 = 0;
    var b: u32 = 0;
    while (query.next()) |entity| {
        if (entity.flag) {
            a += 1;
        } else {
            b += 1;
        }
    }

    return @intCast(a ^ b);
}

inline fn benchSpawn(args: anytype, id: usize) !usize {
    const ecs: *Ecs = args.ecs;
    const entities: []const Ecs.Entity = args.entities;
    const entity = try ecs.spawn(entities[id]);
    return @intCast(@as(u32, @bitCast(entity)));
}

inline fn benchSum(args: anytype, _: usize) !usize {
    const ecs: *Ecs = args.ecs;
    var query = try ecs.query(struct { random: f32 });
    defer query.deinit();

    var sum: f32 = 0.0;
    while (query.next()) |entity| {
        sum += entity.random;
    }

    return @intCast(@as(u32, @bitCast(sum)));
}

inline fn benchDespawn(args: anytype, id: usize) !usize {
    const generation = args.ecs.generations.items[id];
    try args.ecs.despawn(.{ .generation = generation, .index = @intCast(id) });
    return id;
}

inline fn benchDespawnRandom(args: anytype, id: usize) !usize {
    const ecs: *Ecs = args.ecs;
    const indices: []const usize = args.indices;

    const index = indices[id];
    const generation = args.ecs.generations.items[id];
    try ecs.despawn(.{ .generation = generation, .index = @intCast(index) });
    return index;
}

inline fn benchCounter(args: anytype, _: usize) !usize {
    const ecs: *Ecs = args.ecs;
    var query = try ecs.query(struct { counter: *u32 });
    defer query.deinit();

    var hash: u32 = 0;
    while (query.next()) |entity| {
        entity.counter.* += 1;
        hash ^= entity.counter.*;
    }

    return @intCast(hash);
}

inline fn benchQuery(ecs: *Ecs, Query: type) !void {
    var query = try ecs.query(Query);
    query.deinit();
    std.mem.doNotOptimizeAway(query);
}

inline fn benchQueryEmpty(args: anytype, id: usize) !usize {
    try benchQuery(args.ecs, struct {});
    return id;
}

inline fn benchQueryFlag(args: anytype, id: usize) !usize {
    try benchQuery(args.ecs, struct { flag: bool = true });
    return id;
}

inline fn benchQueryName(args: anytype, id: usize) !usize {
    try benchQuery(args.ecs, struct { name: []const u8 });
    return id;
}

inline fn benchSearchFlag(args: anytype, _: usize) !usize {
    const ecs: *Ecs = args.ecs;
    var query = try ecs.query(struct { flag: bool = true });
    defer query.deinit();

    var count: usize = 0;
    while (query.next()) |_| {
        count += 1;
    }

    return @intCast(count);
}

inline fn benchSearchRandomValue(args: anytype, _: usize) !usize {
    const ecs: *Ecs = args.ecs;
    var query = try ecs.query(struct { random: f32 = 0.5 });
    defer query.deinit();

    var count: u32 = 0;
    while (query.next()) |_| {
        count += 1;
    }

    return @intCast(count);
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

fn getEntities(allocator: std.mem.Allocator, rng: std.Random, count: usize) ![]const Ecs.Entity {
    std.debug.print("pregenerating {d} entities...\n", .{count});
    const entities = try allocator.alloc(Ecs.Entity, count);
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

fn getEnvNum(name: []const u8, default_value: u64) !u64 {
    var buffer: [1024]u8 = undefined; // 1KB ought to be enough for anyone!
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const env = std.process.getEnvVarOwned(fba.allocator(), name) catch return default_value;
    return try std.fmt.parseInt(u64, env, 10);
}

fn getDespawnIndices(allocator: std.mem.Allocator, rng: std.Random, despawn_count: usize, entity_count: usize) ![]const usize {
    std.debug.print("pregenerating {d} despawn indices...\n", .{despawn_count});
    const indices = try allocator.alloc(usize, despawn_count);
    for (0..indices.len) |i| {
        indices[i] = rng.uintLessThan(usize, entity_count);
    }

    return indices;
}
