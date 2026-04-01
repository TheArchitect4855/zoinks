const std = @import("std");
const sync = @import("../ecs.zig");

pub fn Task(E: type) type {
    const Ecs = sync.Ecs(E);
    return struct {
        pub const FieldBits = std.StaticBitSet(Ecs.entity_fields.len);
        all_fields: FieldBits,
        exclusive_fields: FieldBits,
        deinit_iter: *const fn () void,
        get_iter: *const fn (ecs: *Ecs) Ecs.QueryError!*anyopaque,
        run_query: *const fn (ctx: *const anyopaque, iter: *anyopaque) anyerror!void,

        pub fn run(self: @This(), ecs: *Ecs, ecs_rw: *std.Thread.RwLock, ctx: *const anyopaque) anyerror!void {
            ecs_rw.lockShared();
            errdefer ecs_rw.unlockShared();
            const iter = try self.get_iter(ecs);
            defer self.deinit_iter();
            ecs_rw.unlockShared();

            try self.run_query(ctx, iter);
        }
    };
}
