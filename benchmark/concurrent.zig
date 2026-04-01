const std = @import("std");
const zoinks = @import("zoinks");
const common = @import("common.zig");

const Ecs = zoinks.ConcurrentEcs(common.Entity);
const Self = @This();

const FlagQuery = struct { flag: bool };
const SumQuery = struct { random: f32 };
const CounterQuery = struct { counter: *u32 };
const SearchFlagQuery = struct { flag: bool = true };
const NameQuery = struct { name: []const u8 };
const SearchRandomValueQuery = struct { random: f32 = 0.5 };

pub fn bench(
    allocator: std.mem.Allocator,
    rng: std.Random,
    spawn_iter_count: u64,
    stdout: *std.Io.Writer,
) !void {
    const pregenerated_entities = try common.getEntities(allocator, rng, spawn_iter_count);
    defer allocator.free(pregenerated_entities);

    const available_threads = try std.Thread.getCpuCount();
    const worker_count = @max(available_threads / 2, 1);
    std.debug.print("using {d} workers\n", .{worker_count});

    var thread_safe = std.heap.ThreadSafeAllocator{ .child_allocator = allocator };
    var ecs = try Ecs.init(&thread_safe, &spawnWorker, 2);
    defer ecs.deinit();

    try common.bench(Self, "benchSpawn", .{ .ecs = &ecs, .entities = pregenerated_entities }, spawn_iter_count, stdout);
    try common.bench(Self, "benchConcurrentQueries", .{ .ecs = &ecs }, 1, stdout);
    try common.bench(Self, "benchDespawn", .{ .ecs = &ecs }, spawn_iter_count, stdout);
}

pub inline fn benchConcurrentQueries(args: anytype, _: usize) !usize {
    const ecs: *Ecs = args.ecs;
    var schedule = ecs.createSchedule(Ecs);
    defer schedule.deinit();

    try schedule.addQuery(FlagQuery, &queryFlag);
    try schedule.addQuery(SumQuery, &querySum);
    try schedule.addQuery(CounterQuery, &queryCounter);
    try schedule.addQuery(SearchFlagQuery, &querySearchFlag);
    try schedule.addQuery(NameQuery, &queryName);
    try schedule.addQuery(SearchRandomValueQuery, &querySearchRandomValue);

    try ecs.runSchedule(Ecs, ecs, schedule);
    return 0;
}

pub inline fn benchSpawn(args: anytype, id: usize) !usize {
    const ecs: *Ecs = args.ecs;
    const entities: []const Ecs.Entity = args.entities;
    var id_buffer: [1]zoinks.EntityId = undefined;
    try ecs.spawn(&.{entities[id]}, &id_buffer);
    return @intCast(@as(u32, @bitCast(id_buffer[0])));
}

pub inline fn benchDespawn(args: anytype, id: usize) !usize {
    const ecs: *Ecs = args.ecs;
    const generation = ecs.shared.ecs.generations.items[id];
    const entity_id = zoinks.EntityId{ .generation = generation, .index = @intCast(id) };
    try ecs.despawn(&.{entity_id});
    return id;
}

fn queryFlag(ecs: *const Ecs, iter: *Ecs.QueryIterator(FlagQuery)) anyerror!void {
    var despawn_list = std.ArrayList(zoinks.EntityId).empty;
    defer despawn_list.deinit(ecs.gpa);

    var counter: u32 = 0;
    while (iter.next()) |entity| {
        if (entity.flag) {
            counter += 1;
            if (counter % 2 == 0) try despawn_list.append(ecs.gpa, iter.current_entity_id);
        }
    }

    try ecs.despawn(despawn_list.items);
}

fn querySum(ecs: *const Ecs, iter: *Ecs.QueryIterator(SumQuery)) anyerror!void {
    _ = ecs;

    var sum: f32 = 0.0;
    while (iter.next()) |entity| {
        sum += entity.random;
    }

    std.debug.print("concurrent sum: {d}\n", .{sum});
}

fn queryCounter(ecs: *const Ecs, iter: *Ecs.QueryIterator(CounterQuery)) anyerror!void {
    _ = ecs;

    var hash: u32 = 0;
    while (iter.next()) |entity| {
        entity.counter.* += 1;
        hash ^= entity.counter.*;
    }

    std.debug.print("concurrent counter hash {d}\n", .{hash});
}

fn querySearchFlag(ecs: *const Ecs, iter: *Ecs.QueryIterator(SearchFlagQuery)) anyerror!void {
    _ = ecs;

    var counter: u32 = 0;
    while (iter.next()) |_| {
        counter += 1;
    }

    std.debug.print("concurrent flag true count: {d}\n", .{counter});
}

fn queryName(ecs: *const Ecs, iter: *Ecs.QueryIterator(NameQuery)) anyerror!void {
    var names = std.ArrayList(u8).empty;
    defer names.deinit(ecs.gpa);

    const first = iter.next().?;
    try names.appendSlice(ecs.gpa, first.name);

    while (iter.next()) |e| {
        while (names.items.len < e.name.len) try names.append(ecs.gpa, 0);

        for (0..e.name.len) |i| {
            const xor = names.items[i] ^ e.name[i];
            names.items[i] = xor % 94 + 32;
        }
    }

    std.debug.print("concurrent names: {s}\n", .{names.items});
}

fn querySearchRandomValue(ecs: *const Ecs, iter: *Ecs.QueryIterator(SearchRandomValueQuery)) anyerror!void {
    _ = ecs;
    var count: u32 = 0;
    while (iter.next()) |_| {
        count += 1;
    }

    std.debug.print("concurrent random count: {d}\n", .{count});
}

fn spawnWorker(allocator: std.mem.Allocator, worker: Ecs.WorkerFn, shared: *Ecs.Shared) anyerror!Ecs.Worker {
    const Closure = struct {
        thread: std.Thread,

        pub fn deinit(self: *@This(), a: std.mem.Allocator) void {
            a.destroy(self);
        }

        pub fn join(self: *@This()) void {
            self.thread.join();
        }

        fn run(fn_ptr: Ecs.WorkerFn, s: *Ecs.Shared) void {
            fn_ptr(s);
        }
    };

    const closure = try allocator.create(Closure);
    errdefer allocator.destroy(closure);

    closure.*.thread = try std.Thread.spawn(.{}, Closure.run, .{ worker, shared });
    return Ecs.Worker.from(Closure, closure);
}
