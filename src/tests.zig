const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.heap.DebugAllocator(.{});

var allocator = Allocator.init;
var ptr_dest: u32 = 0;
var opt_ptr_dest: ?u32 = null;

pub const Ecs = @import("root.zig").Ecs(struct {
    num: u32 = 0,
    opt_num: ?u32 = null,
    ptr: *u32 = &ptr_dest,
    opt_ptr: ?*u32 = null,
    ptr_opt: *?u32 = &opt_ptr_dest,
    slice: []const u8 = "Hello, world!",
    opt_slice: ?[]const u8 = null,
});

// Test functions that don't assert anything other than
// gpa.deinit() == .ok are basically just checking that
// the operations don't crash or cause memory leaks.

test "ECS init/deinit" {
    var gpa = Allocator.init;
    defer assert(gpa.deinit() == .ok);

    var ecs = Ecs.init(gpa.allocator());
    defer ecs.deinit();
}

test "ECS spawn" {
    var ecs = getEcs();
    defer ecs.deinit();

    _ = try ecs.spawn(.{});
}

test "ECS despawn" {
    var ecs = getEcs();
    defer ecs.deinit();

    const id = try ecs.spawn(.{});
    try ecs.despawn(id);
}

test "ECS query empty" {
    var ecs = getEcs();
    defer ecs.deinit();

    var query = try ecs.query(struct {});
    defer query.deinit();

    assert(query.next() == null);
}

test "ECS query next end" {
    var ecs = getEcsForQuery(1);
    defer ecs.deinit();

    var query = try ecs.query(struct {});
    defer query.deinit();

    _ = query.next();
    assert(query.next() == null);
}

test "ECS query current entity ID" {
    var ecs = getEcs();
    defer ecs.deinit();

    const id = try ecs.spawn(.{});

    var query = try ecs.query(struct {});
    defer query.deinit();

    _ = query.next();
    assert(std.meta.eql(query.current_entity_id, id));
}

test "ECS query num" {
    var ecs = getEcsForQuery(1);
    defer ecs.deinit();

    var query = try ecs.query(struct { num: u32 });
    defer query.deinit();

    assert(std.meta.eql(query.next(), .{ .num = 0 }));
}

test "ECS query num optional" {
    var ecs = getEcsForQuery(1);
    defer ecs.deinit();

    var query = try ecs.query(struct { num: ?u32 });
    defer query.deinit();

    assert(std.meta.eql(query.next(), .{ .num = 0 }));
}

test "ECS query num pointer" {
    var ecs = getEcsForQuery(1);
    defer ecs.deinit();

    var query = try ecs.query(struct { num: *u32 });
    defer query.deinit();

    assert(query.next().?.num.* == 0);
}

test "ECS query num optional pointer" {
    var ecs = getEcsForQuery(1);
    defer ecs.deinit();

    var query = try ecs.query(struct { num: ?*u32 });
    defer query.deinit();

    assert(query.next().?.num.?.* == 0);
}

test "ECS query opt_num" {
    var ecs = getEcsForQuery(2);
    defer ecs.deinit();

    var query = try ecs.query(struct { opt_num: u32 });
    defer query.deinit();

    assert(std.meta.eql(query.next(), .{ .opt_num = 1 }));
}

test "ECS query opt_num optional" {
    var ecs = getEcsForQuery(2);
    defer ecs.deinit();

    var query = try ecs.query(struct { opt_num: ?u32 });
    defer query.deinit();

    assert(std.meta.eql(query.next(), .{ .opt_num = null }));
    assert(std.meta.eql(query.next(), .{ .opt_num = 1 }));
}

test "ECS query opt_num pointer" {
    var ecs = getEcsForQuery(2);
    defer ecs.deinit();

    var query = try ecs.query(struct { opt_num: *u32 });
    defer query.deinit();

    assert(query.next().?.opt_num.* == 1);
}

test "ECS query opt_num optional pointer" {
    var ecs = getEcsForQuery(2);
    defer ecs.deinit();

    var query = try ecs.query(struct { opt_num: ?*u32 });
    defer query.deinit();

    assert(query.next().?.opt_num == null);
    assert(query.next().?.opt_num.?.* == 1);
}

test "ECS query ptr" {
    var ecs = getEcsForQuery(1);
    defer ecs.deinit();

    var query = try ecs.query(struct { ptr: *u32 });
    defer query.deinit();

    assert(std.meta.eql(query.next(), .{ .ptr = &ptr_dest }));
}

test "ECS query ptr optional" {
    var ecs = getEcsForQuery(1);
    defer ecs.deinit();

    var query = try ecs.query(struct { ptr: ?*u32 });
    defer query.deinit();

    assert(std.meta.eql(query.next(), .{ .ptr = &ptr_dest }));
}

test "ECS query ptr pointer" {
    var ecs = getEcsForQuery(1);
    defer ecs.deinit();

    var query = try ecs.query(struct { ptr: **u32 });
    defer query.deinit();

    assert(query.next().?.ptr.* == &ptr_dest);
}

test "ECS query ptr optional pointer" {
    var ecs = getEcsForQuery(1);
    defer ecs.deinit();

    var query = try ecs.query(struct { ptr: ?**u32 });
    defer query.deinit();

    assert(query.next().?.ptr.?.* == &ptr_dest);
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
            .opt_ptr = if (i % 3 == 0) null else &ptr_dest,
            .opt_slice = if (i % 5 == 0) null else "Hello, world!",
        }) catch unreachable;
    }

    return ecs;
}
