const std = @import("std");
const parse = @import("parse.zig");

pub fn main() !void {
    const file = @embedFile("main.wasm");
    var buffer: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const module = try parse.file(file, fba.allocator());
    debug_print(module);
}

fn debug_print_func_type(fn_type: parse.wasm.FuncType) void {
    std.debug.print("fn(", .{});
    for (fn_type.args, 0..) |arg, i| {
        if (i > 0) {
            std.debug.print(", ", .{});
        }
        std.debug.print("{s}", .{@tagName(arg)});
    }
    std.debug.print(") -> (", .{});
    for (fn_type.ret, 0..) |arg, i| {
        if (i > 0) {
            std.debug.print(", ", .{});
        }
        std.debug.print("{s}", .{@tagName(arg)});
    }
    std.debug.print(")", .{});
}

fn debug_print_limit(limit: parse.wasm.Limit) void {
    if (limit.max) |max| {
        std.debug.print("({d},{d})", .{limit.min, max});
    } else {
        std.debug.print("({d},inf)", .{limit.min});
    }
}

fn debug_print(module: *parse.wasm.Module) void {
    std.debug.print("Wasm Module\n", .{});
    std.debug.print("\nSection 1: Types\n", .{});
    for (module.types, 0..) |t, i| {
        std.debug.print(" {d: >3}: ", .{i});
        debug_print_func_type(t);
        std.debug.print("\n", .{});
    }

    std.debug.print("\nSection 2: Imports\n", .{});
    for (module.imports, 0..) |any_import, i| {
        switch (any_import) {
            .func => |f| {
                std.debug.print(" {d: >3}: {s}.{s} = ", .{i, f.module, f.name});
                debug_print_func_type(module.types[f.type_idx]);
                std.debug.print("\n", .{});
            }
        }
    }

    std.debug.print("\nSection 3: Functions\n", .{});
    for (module.functions, 0..) |f, i| {
        std.debug.print(" {d: >3}: ", .{i});
        debug_print_func_type(module.types[f]);
        std.debug.print("\n", .{});
    }

    std.debug.print("\nSection 5: Memory\n", .{});
    for (module.memory, 0..) |mem, i| {
        std.debug.print(" {d: >3}: ", .{i});
        debug_print_limit(mem);
        std.debug.print("\n", .{});
    }

    std.debug.print("\nSection 6: Global\n", .{});
    for (module.global, 0..) |g, i| {
        const mutability = if(g.mutable) "var" else "const";
        std.debug.print(" {d: >3}: {s} {s}", .{i, mutability, @tagName(g.value_type)});
    }
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