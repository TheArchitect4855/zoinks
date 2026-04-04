const std = @import("std");
const zoinks = @import("zoinks");
const Entity = @import("Entity.zig");
const assert = std.debug.assert;

var debug = std.heap.DebugAllocator(.{}).init;
var allocator = std.heap.ThreadSafeAllocator{ .child_allocator = debug.allocator() };

const Ecs = zoinks.concurrent.Ecs(Entity, zoinks.concurrent.StdThread);

const EmptyQuery = struct {};
const NumQuery = struct { num: u32 };
const NumFlagQuery = struct { num: u32, flag: bool };

test "init/deinit" {
    var debug_allocator = std.heap.DebugAllocator(.{}).init;
    defer assert(debug_allocator.deinit() == .ok);

    var gpa = std.heap.ThreadSafeAllocator{ .child_allocator = debug_allocator.allocator() };
    var ecs = try Ecs.init(&gpa, 2);
    defer ecs.deinit();
}

test "create schedule" {
    var ecs = getEcs();
    defer ecs.deinit();

    _ = ecs.createSchedule(void);
}

test "run schedule empty" {
    var ecs = getEcs();
    defer ecs.deinit();

    const schedule = ecs.createSchedule(void);
    try ecs.runSchedule(void, &{}, schedule);
}

test "schedule add query" {
    var ecs = getEcs();
    defer ecs.deinit();

    var schedule = ecs.createSchedule(void);
    defer schedule.deinit();

    try schedule.addQuery(EmptyQuery, &runQueryVoidEmpty);
}

test "run schedule" {
    var ecs = getEcsForQuery(10);
    defer ecs.deinit();

    var schedule = ecs.createSchedule(Ecs);
    defer schedule.deinit();

    try schedule.addQuery(NumQuery, &runQueryEcsNum);
    try schedule.addQuery(NumFlagQuery, &runQueryEcsNumFlag);

    try ecs.runSchedule(Ecs, &ecs, schedule);
}

fn getEcs() Ecs {
    return Ecs.init(&allocator, 2) catch unreachable;
}

fn getEcsForQuery(entity_count: comptime_int) Ecs {
    var entities: [entity_count]Entity = undefined;
    for (0..entity_count) |i| {
        entities[i] = .{
            .num = @intCast(i),
            .opt_num = if (i % 2 == 0) null else @intCast(i),
            .opt_ptr = if (i % 3 == 0) null else &Entity.ptr_dest,
            .opt_slice = if (i % 5 == 0) null else "Hello, world!",
            .flag = (i % 6 == 0),
        };
    }

    var id_buffer: [entity_count]zoinks.EntityId = undefined;
    var ecs = getEcs();
    ecs.spawn(&entities, &id_buffer) catch unreachable;
    return ecs;
}

fn runQueryVoidEmpty(ctx: *const void, iter: *Ecs.QueryIterator(EmptyQuery)) anyerror!void {
    _ = ctx;
    _ = iter;
}

fn runQueryEcsNum(ctx: *const Ecs, iter: *Ecs.QueryIterator(NumQuery)) anyerror!void {
    _ = ctx;
    _ = iter;
}

fn runQueryEcsNumFlag(ctx: *const Ecs, iter: *Ecs.QueryIterator(NumFlagQuery)) anyerror!void {
    _ = ctx;
    _ = iter;
}
