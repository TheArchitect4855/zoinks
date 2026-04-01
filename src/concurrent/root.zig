const std = @import("std");
const sync = @import("../ecs.zig");
const Atomic = std.atomic.Value;
const EntityId = @import("../entity_id.zig").EntityId;
const Futex = std.Thread.Futex;
const Schedule = @import("schedule.zig").Schedule;
const Task = @import("task.zig").Task;

pub fn ConcurrentEcs(E: type) type {
    const TaskNode = struct {
        pub const State = enum { waiting, running, completed };
        state: State = .waiting,
        task: Task(E),
    };

    const SyncEcs = sync.Ecs(E);
    const SharedImpl = struct {
        const Self = @This();

        ecs: SyncEcs,
        ecs_rw: std.Thread.RwLock = .{},
        ctx: *const anyopaque = undefined,
        stop_state: Atomic(u32) = .init(0),
        task_list: ?[]TaskNode = null,
        task_list_mutex: std.Thread.Mutex = .{},

        pub fn runTasks(self: *Self) void {
            self.task_list_mutex.lock();
            defer self.task_list_mutex.unlock();

            while (self.getRunnableNode()) |node| {
                node.state = .running;
                self.task_list_mutex.unlock();

                node.task.run(&self.ecs, &self.ecs_rw, self.ctx) catch |e| {
                    std.debug.print("error while running query task: {s}\n", .{@errorName(e)});
                };

                self.task_list_mutex.lock();
                node.state = .completed;
                self.signalWorkerContinue();
            }
        }

        pub fn shouldStop(self: *const Self) bool {
            return self.stop_state.load(.acquire) == 1;
        }

        pub fn signalWorkerContinue(self: *const Self) void {
            Futex.wake(&self.stop_state, std.math.maxInt(u32));
        }

        pub fn wait(self: *const Self) void {
            Futex.wait(&self.stop_state, 0);
        }

        fn getRunnableNode(self: *const Self) ?*TaskNode {
            const task_list = self.task_list orelse return null;

            var all_fields = Task(E).FieldBits.initEmpty();
            var exclusive_fields = Task(E).FieldBits.initEmpty();
            for (task_list) |node| {
                if (node.state != .running) continue;
                all_fields.setUnion(node.task.all_fields);
                exclusive_fields.setUnion(node.task.exclusive_fields);
            }

            for (task_list) |*node| {
                if (node.state != .waiting) continue;

                const overlapped_exclusive_fields = all_fields.intersectWith(node.task.exclusive_fields)
                    .unionWith(exclusive_fields.intersectWith(node.task.all_fields));
                if (overlapped_exclusive_fields.count() > 0) continue;
                return node;
            }

            return null;
        }
    };

    return struct {
        const Self = @This();

        // Error types
        pub const InitError = error{SpawnWorker} || std.mem.Allocator.Error;
        pub const RunScheduleError = std.mem.Allocator.Error;
        pub const Error = InitError || RunScheduleError;

        pub const Entity = SyncEcs.Entity;
        pub const QueryIterator = SyncEcs.QueryIterator;
        pub const Worker = @import("Worker.zig");
        pub const WorkerFn = *const fn (*Shared) void;
        pub const Shared = SharedImpl;
        gpa: std.mem.Allocator,
        shared: *Shared,
        workers: []Worker,

        pub fn init(
            gpa: *std.heap.ThreadSafeAllocator,
            spawn_fn: *const fn (std.mem.Allocator, WorkerFn, *Shared) anyerror!Worker,
            worker_count: usize,
        ) InitError!Self {
            std.debug.assert(worker_count > 0);

            const allocator = gpa.allocator();
            const sync_ecs = SyncEcs.init(allocator);
            const shared = try allocator.create(Shared);
            errdefer allocator.destroy(shared);
            shared.* = .{ .ecs = sync_ecs };

            const workers = try allocator.alloc(Worker, worker_count - 1);
            errdefer allocator.free(workers);
            for (0..worker_count - 1) |i| {
                workers[i] = spawn_fn(allocator, worker, shared) catch |e| {
                    std.debug.print("failed to spawn worker: {s}\n", .{@errorName(e)});
                    stop(allocator, shared, workers[0..i]);
                    return InitError.SpawnWorker;
                };
            }

            return .{
                .gpa = allocator,
                .shared = shared,
                .workers = workers,
            };
        }

        pub fn deinit(self: Self) void {
            stop(self.gpa, self.shared, self.workers);
            self.shared.ecs.deinit();
            self.gpa.destroy(self.shared);
            self.gpa.free(self.workers);
        }

        pub fn createSchedule(
            self: *Self,
            T: type,
        ) Schedule(E, T) {
            return .{ .allocator = self.gpa };
        }

        pub fn runSchedule(
            self: *Self,
            T: type,
            ctx: *const T,
            schedule: Schedule(E, T),
        ) RunScheduleError!void {
            const task_nodes = try self.gpa.alloc(TaskNode, schedule.tasks.items.len);
            defer self.gpa.free(task_nodes);

            for (schedule.tasks.items, 0..) |task, index| {
                task_nodes[index] = .{ .task = task };
            }

            self.shared.ctx = ctx;
            self.shared.task_list = task_nodes;
            self.shared.signalWorkerContinue();

            var has_tasks = true;
            while (has_tasks) {
                self.shared.runTasks();

                // Check if there are any uncompleted tasks
                self.shared.task_list_mutex.lock();
                has_tasks = false;
                for (task_nodes) |t| {
                    if (t.state != .waiting) continue;
                    has_tasks = true;
                    break;
                }

                self.shared.task_list_mutex.unlock();
            }

            while (true) {
                self.shared.task_list_mutex.lock();
                var any_uncompleted = false;
                for (task_nodes) |t| {
                    if (t.state == .completed) continue;
                    any_uncompleted = true;
                    break;
                }

                self.shared.task_list_mutex.unlock();
                if (any_uncompleted) {
                    self.shared.wait();
                } else {
                    break;
                }
            }

            self.shared.task_list_mutex.lock();
            self.shared.task_list = null;
            self.shared.task_list_mutex.unlock();
        }

        pub fn spawn(self: Self, entities: []const Entity, id_buffer: []EntityId) SyncEcs.SpawnError!void {
            std.debug.assert(id_buffer.len == 0 or entities.len == id_buffer.len);

            self.shared.ecs_rw.lock();
            defer self.shared.ecs_rw.unlock();

            const ecs = &self.shared.ecs;
            if (id_buffer.len == 0) {
                for (entities) |e| _ = try ecs.spawn(e);
            } else {
                for (entities, 0..) |e, i| {
                    const id = try ecs.spawn(e);
                    id_buffer[i] = id;
                }
            }
        }

        pub fn despawn(self: Self, entity_ids: []const EntityId) SyncEcs.DespawnError!void {
            self.shared.ecs_rw.lock();
            defer self.shared.ecs_rw.unlock();

            const ecs = &self.shared.ecs;
            for (entity_ids) |id| try ecs.despawn(id);
        }

        fn stop(allocator: std.mem.Allocator, shared: *Shared, workers: []Worker) void {
            shared.stop_state.store(1, .release);
            shared.signalWorkerContinue();
            for (workers) |*w| {
                w.join();
                w.deinit(allocator);
            }
        }

        fn worker(shared: *Shared) void {
            while (!shared.shouldStop()) {
                shared.wait();
                shared.runTasks();
            }
        }
    };
}
