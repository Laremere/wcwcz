const std = @import("std");
const parse = @import("parse.zig");

pub fn main() !void {
    const file = @embedFile("main.wasm");
    var buffer: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const module = try parse.file(file, fba.allocator());
    std.debug.print("module = {}\n", .{module});
    std.debug.print("types = {any}\n", .{module.types});
    std.debug.print("imports = {any}\n", .{module.imports});
}

// const import_functions = struct {
//     fn proc_exit(a: u32) void {
//         _ = a;
//     }

//     fn fd_write(a: u32, b: u32, c: u32, d: u32) u32 {
//         _ = a;
//         _ = b;
//         _ = c;
//         _ = d;
//         return 0;
//     }
// };

// const ImportDefinition = struct {
//     module: []const u8,
//     name: []const u8,
//     func: *const anyopaque,
// };

// const import_definitions = [_]ImportDefinition{
//     .{
//         .module = "wasi_snapshot_preview1",
//         .name = "proc_exit",
//         .func = import_functions.proc_exit,
//     },
//     .{
//         .module = "wasi_snapshot_preview1",
//         .name = "fd_write",
//         .func = import_functions.fd_write,
//     },
// };