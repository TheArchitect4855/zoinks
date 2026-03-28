const std = @import("std");
const zoinks = @import("zoinks");
const root = @import("root.zig");

const Ecs = zoinks.Ecs(root.Entity);
const Self = @This();

pub fn bench(
    allocator: std.mem.Allocator,
    rng: std.Random,
    spawn_iter_count: u64,
    query_iter_count: u64,
    stdout: *std.Io.Writer,
) !void {
    const pregenerated_entities = try root.getEntities(allocator, rng, spawn_iter_count);
    defer allocator.free(pregenerated_entities);

    const despawn_indices = try root.getDespawnIndices(allocator, rng, spawn_iter_count / 2, spawn_iter_count);
    defer allocator.free(despawn_indices);

    var ecs = Ecs.init(allocator);
    defer ecs.deinit();

    try root.bench(Self, "benchSpawn", .{ .ecs = &ecs, .entities = pregenerated_entities }, spawn_iter_count, stdout);
    try root.bench(Self, "benchQueryEmpty", .{ .ecs = &ecs }, query_iter_count, stdout);
    try root.bench(Self, "benchQueryFlag", .{ .ecs = &ecs }, query_iter_count, stdout);
    try root.bench(Self, "benchQueryName", .{ .ecs = &ecs }, query_iter_count, stdout);
    try root.bench(Self, "benchCounter", .{ .ecs = &ecs }, query_iter_count, stdout);
    try root.bench(Self, "benchSum", .{ .ecs = &ecs }, query_iter_count, stdout);
    try root.bench(Self, "benchFlag", .{ .ecs = &ecs }, query_iter_count, stdout);
    try root.bench(Self, "benchSearchFlag", .{ .ecs = &ecs }, query_iter_count, stdout);
    try root.bench(Self, "benchSearchRandomValue", .{ .ecs = &ecs }, query_iter_count, stdout);
    try root.bench(Self, "benchDespawn", .{ .ecs = &ecs }, spawn_iter_count, stdout);

    try root.bench(Self, "benchSpawn", .{ .ecs = &ecs, .entities = pregenerated_entities }, spawn_iter_count, stdout);
    try root.bench(Self, "benchDespawnRandom", .{ .ecs = &ecs, .indices = despawn_indices }, despawn_indices.len, stdout);
    try root.bench(Self, "benchQueryEmpty", .{ .ecs = &ecs }, query_iter_count, stdout);
    try root.bench(Self, "benchQueryFlag", .{ .ecs = &ecs }, query_iter_count, stdout);
    try root.bench(Self, "benchQueryName", .{ .ecs = &ecs }, query_iter_count, stdout);
    try root.bench(Self, "benchCounter", .{ .ecs = &ecs }, query_iter_count, stdout);
    try root.bench(Self, "benchSum", .{ .ecs = &ecs }, query_iter_count, stdout);
    try root.bench(Self, "benchFlag", .{ .ecs = &ecs }, query_iter_count, stdout);
    try root.bench(Self, "benchSearchFlag", .{ .ecs = &ecs }, query_iter_count, stdout);
    try root.bench(Self, "benchSearchRandomValue", .{ .ecs = &ecs }, query_iter_count, stdout);
}

pub inline fn benchFlag(args: anytype, _: usize) !usize {
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

pub inline fn benchSpawn(args: anytype, id: usize) !usize {
    const ecs: *Ecs = args.ecs;
    const entities: []const Ecs.Entity = args.entities;
    const entity = try ecs.spawn(entities[id]);
    return @intCast(@as(u32, @bitCast(entity)));
}

pub inline fn benchSum(args: anytype, _: usize) !usize {
    const ecs: *Ecs = args.ecs;
    var query = try ecs.query(struct { random: f32 });
    defer query.deinit();

    var sum: f32 = 0.0;
    while (query.next()) |entity| {
        sum += entity.random;
    }

    return @intCast(@as(u32, @bitCast(sum)));
}

pub inline fn benchDespawn(args: anytype, id: usize) !usize {
    const generation = args.ecs.generations.items[id];
    try args.ecs.despawn(.{ .generation = generation, .index = @intCast(id) });
    return id;
}

pub inline fn benchDespawnRandom(args: anytype, id: usize) !usize {
    const ecs: *Ecs = args.ecs;
    const indices: []const usize = args.indices;

    const index = indices[id];
    const generation = args.ecs.generations.items[id];
    try ecs.despawn(.{ .generation = generation, .index = @intCast(index) });
    return index;
}

pub inline fn benchCounter(args: anytype, _: usize) !usize {
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

pub inline fn benchQuery(ecs: *Ecs, Query: type) !void {
    var query = try ecs.query(Query);
    query.deinit();
    std.mem.doNotOptimizeAway(query);
}

pub inline fn benchQueryEmpty(args: anytype, id: usize) !usize {
    try benchQuery(args.ecs, struct {});
    return id;
}

pub inline fn benchQueryFlag(args: anytype, id: usize) !usize {
    try benchQuery(args.ecs, struct { flag: bool = true });
    return id;
}

pub inline fn benchQueryName(args: anytype, id: usize) !usize {
    try benchQuery(args.ecs, struct { name: []const u8 });
    return id;
}

pub inline fn benchSearchFlag(args: anytype, _: usize) !usize {
    const ecs: *Ecs = args.ecs;
    var query = try ecs.query(struct { flag: bool = true });
    defer query.deinit();

    var count: usize = 0;
    while (query.next()) |_| {
        count += 1;
    }

    return @intCast(count);
}

pub inline fn benchSearchRandomValue(args: anytype, _: usize) !usize {
    const ecs: *Ecs = args.ecs;
    var query = try ecs.query(struct { random: f32 = 0.5 });
    defer query.deinit();

    var count: u32 = 0;
    while (query.next()) |_| {
        count += 1;
    }

    return @intCast(count);
}
