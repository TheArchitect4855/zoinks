# zoinks

Zoinks is an easy-to-use ECS package for the Zig programming language. It's
intended use case is in games.

## Features

1. An ECS "world" to put entities in.
2. Entity spawning and despawning.
3. Queries that can iterate over & mutate entities.

## Background

I created this library because I think Zig is a great language for game/engine
development. ECS is also a really slick architecture for games, and I
personally use it a lot. This library is intended to be an easy-to-use drop-in
ECS for any project that needs one.

### Goals

#### 1. Simplicity.
This library should make sense and be intuitive to use.

#### 2. Focus.
This library should be incredibly good at one thing (ECS), and do nothing else.

#### 3. Speed.
Speed is obviously very important in game development. ECS is already
inherently fast on modern architectures, but maximizing throughput is a top
priority.

### Non-Goals

#### Everything but the kitchen sink.
This library is NOT meant to be a general-purpose game development framework. It
is meant to be an ECS library, and nothing more.

## Installation
Since this library is in early development, it makes the most sense to install
the latest version to your Zig project:

`zig fetch --save git+https://github.com/TheArchitect4855/zoinks.git`

Then in your `build.zig`:

```zig
const zoinks = b.dependency("zoinks", .{
    .target = target,
    .optimize = optimize,
});

exe_mod.addImport("zoinks", linalg.module("zoinks"));
```

## Usage

```zig
// This creates an ECS type. The struct passed to the `Ecs()` function is your
// entity definition. You can have any kinds of fields in your entity, and
// zoinks will optimize it as best it can.
const Ecs = @import("zoinks").Ecs(struct {
    // ...your entity definition here...
    foo: u32 = 42,
    bar: ?u32 = null, // Optional values are handled automatically.
});

// --- INIT/DEINIT --- \\
var ecs = Ecs.init(allocator);
defer ecs.deinit();

// --- SPAWNING/DESPAWNING --- \\
const entity_id = try ecs.spawn(.{
    // Entity data goes here. Matches the struct you passed to the Ecs()
    // function.
});

// When you're done with your entity...
try ecs.despawn(entity_id);

// --- QUERIES --- \\
var query = try ecs.query(struct {
    // Your query goes here. You can query any field on your entity struct. The
    // type of the field in the query can be the type of the field on your
    // entity struct, an optional of it, a pointer to it, or an optional
    // pointer.
    foo: *u32, // This would query a pointer to the foo field on your entity.
    bar: u32,  // This would copy the bar field on your entity, and only return entities where bar is not null.
});
defer query.deinit();

while (query.next()) |entity| {
    entity.foo.* += 1; // Pointers can be written to as you'd expect.
    
    // It's safe to despawn entities while iterating your query.
    const entity_id = query.current_entity_id;
    try ecs.despawn(entity_id);
}
```

## Support
Found a bug? Have a feature request? Submit an issue or create a PR!

## Contributing
Contributions are welcome! If you'd like to tackle an open issue, please leave
a comment to indicate you will be working on it. To submit your code, create a
pull request.
