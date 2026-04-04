const std = @import("std");
const sync = @import("../ecs.zig");
const task = @import("task.zig");
const StructField = std.builtin.Type.StructField;

/// A schedule is a collection of queries to be run in parallel. `E` is the
/// entity type, and `T` is the context type.
pub fn Schedule(E: type, T: type) type {
    const Ecs = sync.Ecs(E);
    const Task = task.Task(E);

    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        tasks: std.ArrayList(Task) = .empty,

        pub fn deinit(self: *Self) void {
            self.tasks.deinit(self.allocator);
        }

        /// Adds a query to be run in parallel. `Q` is the query type.
        pub fn addQuery(
            self: *Self,
            Q: type,
            run_query: *const fn (ctx: *const T, iter: *Ecs.QueryIterator(Q)) anyerror!void,
        ) std.mem.Allocator.Error!void {
            const I = Ecs.QueryIterator(Q);
            const Context = struct {
                var iter: I = undefined;

                fn deinitIter() void {
                    iter.deinit();
                }

                fn getIter(ecs: *Ecs) Ecs.QueryError!*I {
                    iter = try I.init(ecs);
                    return &iter;
                }
            };

            var all_fields = Task.FieldBits.initEmpty();
            var exclusive_fields = Task.FieldBits.initEmpty();
            inline for (Ecs.entity_fields, 0..) |field, index| {
                const query_field = getField(field.name, I.query_fields) orelse continue;
                if (isMutable(query_field.type)) exclusive_fields.set(index);
                all_fields.set(index);
            }

            const t = Task{
                .all_fields = all_fields,
                .exclusive_fields = exclusive_fields,
                .deinit_iter = &Context.deinitIter,
                .get_iter = @ptrCast(&Context.getIter),
                .run_query = @ptrCast(run_query),
            };

            try self.tasks.append(self.allocator, t);
        }
    };
}

fn getField(comptime name: []const u8, comptime fields: []const StructField) ?StructField {
    for (fields) |f| {
        if (std.mem.eql(u8, name, f.name)) return f;
    }

    return null;
}

fn isMutable(T: type) bool {
    return switch (@typeInfo(T)) {
        .optional => |opt| isMutable(opt.child),
        .pointer => |ptr| !ptr.is_const or isMutable(ptr.child),
        else => false,
    };
}
