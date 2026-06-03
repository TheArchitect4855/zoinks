const std = @import("std");
const Entity = @import("Entity.zig");
const assert = std.debug.assert;
const Allocator = std.heap.DebugAllocator(.{});

var allocator = Allocator.init;

pub const Ecs = @import("zoinks").Ecs(Entity);

// Test functions that don't assert anything other than
// gpa.deinit() == .ok are basically just checking that
// the operations don't crash or cause memory leaks.

test "init/deinit" {
    var gpa = Allocator.init;
    defer assert(gpa.deinit() == .ok);

    var ecs = Ecs.init(gpa.allocator());
    defer ecs.deinit();
}

test "spawn" {
    var ecs = getEcs();
    defer ecs.deinit();

    _ = try ecs.spawn(.{});
}

test "despawn" {
    var ecs = getEcs();
    defer ecs.deinit();

    const id = try ecs.spawn(.{});
    try ecs.despawn(id);
}

test "query empty" {
    var ecs = getEcs();
    defer ecs.deinit();

    var query = try ecs.query(struct {});
    defer query.deinit();

    assert(query.next() == null);
}

test "query next end" {
    var ecs = getEcsForQuery(1);
    defer ecs.deinit();

    var query = try ecs.query(struct {});
    defer query.deinit();

    _ = query.next();
    assert(query.next() == null);
}

test "query current entity ID" {
    var ecs = getEcs();
    defer ecs.deinit();

    const id = try ecs.spawn(.{});

    var query = try ecs.query(struct {});
    defer query.deinit();

    _ = query.next();
    assert(std.meta.eql(query.current_entity_id, id));
}

test "query num" {
    var ecs = getEcsForQuery(1);
    defer ecs.deinit();

    var query = try ecs.query(struct { num: u32 });
    defer query.deinit();

    assert(std.meta.eql(query.next(), .{ .num = 0 }));
}

test "query num optional" {
    var ecs = getEcsForQuery(1);
    defer ecs.deinit();

    var query = try ecs.query(struct { num: ?u32 });
    defer query.deinit();

    assert(std.meta.eql(query.next(), .{ .num = 0 }));
}

test "query num pointer" {
    var ecs = getEcsForQuery(1);
    defer ecs.deinit();

    var query = try ecs.query(struct { num: *u32 });
    defer query.deinit();

    assert(query.next().?.num.* == 0);
}

test "query num optional pointer" {
    var ecs = getEcsForQuery(1);
    defer ecs.deinit();

    var query = try ecs.query(struct { num: ?*u32 });
    defer query.deinit();

    assert(query.next().?.num.?.* == 0);
}

test "query num with value" {
    var ecs = getEcsForQuery(2);
    defer ecs.deinit();

    var query = try ecs.query(struct { num: u32 = 1 });
    defer query.deinit();

    assert(std.meta.eql(query.next(), .{ .num = 1 }));
}

test "query opt_num" {
    var ecs = getEcsForQuery(2);
    defer ecs.deinit();

    var query = try ecs.query(struct { opt_num: u32 });
    defer query.deinit();

    assert(std.meta.eql(query.next(), .{ .opt_num = 1 }));
}

test "query opt_num optional" {
    var ecs = getEcsForQuery(2);
    defer ecs.deinit();

    var query = try ecs.query(struct { opt_num: ?u32 });
    defer query.deinit();

    assert(std.meta.eql(query.next(), .{ .opt_num = null }));
    assert(std.meta.eql(query.next(), .{ .opt_num = 1 }));
}

test "query opt_num pointer" {
    var ecs = getEcsForQuery(2);
    defer ecs.deinit();

    var query = try ecs.query(struct { opt_num: *u32 });
    defer query.deinit();

    assert(query.next().?.opt_num.* == 1);
}

test "query opt_num optional pointer" {
    var ecs = getEcsForQuery(2);
    defer ecs.deinit();

    var query = try ecs.query(struct { opt_num: ?*u32 });
    defer query.deinit();

    assert(query.next().?.opt_num == null);
    assert(query.next().?.opt_num.?.* == 1);
}

test "query opt_num with value" {
    var ecs = getEcsForQuery(2);
    defer ecs.deinit();

    var query = try ecs.query(struct { opt_num: u32 = 1 });
    defer query.deinit();

    assert(std.meta.eql(query.next(), .{ .opt_num = 1 }));
}

test "query opt_num with null value" {
    var ecs = getEcsForQuery(3);
    defer ecs.deinit();

    var query = try ecs.query(struct { num: u32, opt_num: ?u32 = null });
    defer query.deinit();

    _ = query.next();
    assert(std.meta.eql(query.next(), .{ .num = 2, .opt_num = null }));
}

test "query ptr" {
    var ecs = getEcsForQuery(1);
    defer ecs.deinit();

    var query = try ecs.query(struct { ptr: *u32 });
    defer query.deinit();

    assert(std.meta.eql(query.next(), .{ .ptr = &Entity.ptr_dest }));
}

test "query ptr optional" {
    var ecs = getEcsForQuery(1);
    defer ecs.deinit();

    var query = try ecs.query(struct { ptr: ?*u32 });
    defer query.deinit();

    assert(std.meta.eql(query.next(), .{ .ptr = &Entity.ptr_dest }));
}

test "query ptr pointer" {
    var ecs = getEcsForQuery(1);
    defer ecs.deinit();

    var query = try ecs.query(struct { ptr: **u32 });
    defer query.deinit();

    assert(query.next().?.ptr.* == &Entity.ptr_dest);
}

test "query ptr optional pointer" {
    var ecs = getEcsForQuery(1);
    defer ecs.deinit();

    var query = try ecs.query(struct { ptr: ?**u32 });
    defer query.deinit();

    assert(query.next().?.ptr.?.* == &Entity.ptr_dest);
}

test "query flag" {
    var ecs = getEcsForQuery(2);
    defer ecs.deinit();

    var query = try ecs.query(struct { num: u32, flag: bool = false });
    defer query.deinit();

    assert(std.meta.eql(query.next(), .{ .num = 1, .flag = false }));
}

fn getEcs() Ecs {
    return Ecs.init(allocator.allocator());
}

fn getEcsForQuery(entity_count: comptime_int) Ecs {
    var ecs = getEcs();
    for (0..entity_count) |i| {
        _ = ecs.spawn(.{
            .num = @intCast(i),
            .opt_num = if (i % 2 == 0) null else @intCast(i),
            .opt_ptr = if (i % 3 == 0) null else &Entity.ptr_dest,
            .opt_slice = if (i % 5 == 0) null else "Hello, world!",
            .flag = (i % 6 == 0),
        }) catch unreachable;
    }

    return ecs;
}
