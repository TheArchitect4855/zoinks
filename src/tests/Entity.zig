pub var ptr_dest: u32 = 0;
pub var opt_ptr_dest: ?u32 = null;

num: u32 = 0,
opt_num: ?u32 = null,
ptr: *u32 = &ptr_dest,
opt_ptr: ?*u32 = null,
ptr_opt: *?u32 = &opt_ptr_dest,
slice: []const u8 = "Hello, world!",
opt_slice: ?[]const u8 = null,
flag: bool = false,
