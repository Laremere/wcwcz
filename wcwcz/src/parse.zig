// Generic wasm file parser.

const std = @import("std");

pub const wasm = struct {
    pub const Module = struct {
        types: []FuncType = undefined,
        imports: []Import = undefined,
        functions: []u32 = undefined,
    };

    pub const ValType = enum {
        i32,
        i64,
        f32,
        f64,
        v128,
        func_ref,
        extern_ref,
    };

    pub const FuncType = struct {
        args: []ValType,
        ret: []ValType,
    };

    pub const ImportFunction = struct {
    	module: []const u8,
    	name: []const u8,
        type_idx: u32,
    };

    pub const Import = union(enum) {
        func: ImportFunction,
        // table, memory, and global ommited until used.
    };
};

// All pointers are either allocated by the allocator arg, or point to the original file.
pub fn file(comptime slice: []const u8, allocator: std.mem.Allocator) !*wasm.Module {
    var r = Reader{.slice = slice};
    const module = try allocator.create(wasm.Module);

    const magic = try r.bytes_fixed(4);
    for ([4]u8{0x00, 0x61, 0x73, 0x6d}, magic) |expected, actual| {
        if (expected != actual) {
            return WasmParseError.WrongMagic;
        }
    }

    const version = try r.bytes_fixed(4);
    for ([4]u8{0x01, 0x00, 0x00, 0x00}, version) |expected, actual| {
        if (expected != actual) {
            return WasmParseError.WrongVersion;
        }
    }

    while (r.slice.len > 0) {
        const id = try r.byte();
        const length = try r.u(32);
        const section_slice = try r.bytes(length);

        var section_r = Reader{.slice = section_slice};
        switch (id) {
            1 => {
                module.types = try parse_vec(&section_r, allocator, parse_function_type);
            },
            2 => {
                module.imports = try parse_vec(&section_r, allocator, parse_import);
            },
            3 => {
            	module.functions = try parse_vec(&section_r, allocator, parse_function_index);
        	},
            else => {
		        std.debug.print("unparsed section:\n", .{});    
		        std.debug.print("section id = {d}\n", .{id});    
		        std.debug.print("section length = {d}\n", .{length});
		        std.debug.print("section contents = {}\n\n", .{std.fmt.fmtSliceHexUpper(section_slice)});
           	},
        }
    }

    return module;
}

fn get_return_type(comptime f: anytype) type {
    switch (@typeInfo(@TypeOf(f))) {
        .Fn => |fn_field| {
            if (fn_field.return_type) |return_type| {
                return clear_error_type(return_type);    
            }
            @compileError("get_return_type expects a function with a return type.");
        },
        else => @compileError("get_return_type expects a function."),
    }
}

fn clear_error_type(comptime t: anytype) type {
        switch (@typeInfo(t)) {
        .ErrorUnion => |eu| {
            return eu.payload;
        },
        else => return t,
    }
}

fn parse_vec(r: *Reader, allocator: std.mem.Allocator, comptime f: anytype) ![]get_return_type(f) {
    const count = try r.u(32);
    const arr = try allocator.alloc(get_return_type(f), @intCast(count));
    for (arr) |*i| {
        i.* = try f(r, allocator);
    }
    return arr;
}

fn parse_function_type(r: *Reader, allocator: std.mem.Allocator) !wasm.FuncType {
    const header = try r.byte();
    if (header != 0x60) {
        return WasmParseError.InvalidFormat;
    }
    const args = try parse_vec(r, allocator, parse_value_type);
    const ret = try parse_vec(r, allocator, parse_value_type);
    return wasm.FuncType{.args = args, .ret = ret};
}

fn parse_value_type(r: *Reader, allocator: std.mem.Allocator) !wasm.ValType {
    _ = allocator;
    return switch (try r.byte()) {
        0x7F => wasm.ValType.i32,
        0x7E => wasm.ValType.i64,
        0x7D => wasm.ValType.f32,
        0x7C => wasm.ValType.f64,
        0x7B => wasm.ValType.v128,
        0x70 => wasm.ValType.func_ref,
        0x6F => wasm.ValType.extern_ref,
        else => WasmParseError.InvalidFormat,
    };
}

fn parse_import(r: *Reader, allocator: std.mem.Allocator) !wasm.Import {
    _ = allocator;
    const module = try r.bytes_n();
    const name = try r.bytes_n();
    const import_type = try r.byte();
    const import_index = try r.u(32);

    if (import_type == 0x00) {
	    return wasm.Import{
	        .func = .{
	        	.module = module,
	        	.name = name,
	            .type_idx = import_index,
	        },
	    };
    }
    return WasmParseError.ImportTypeNotSupported;
}

fn parse_function_index(r: *Reader, allocator: std.mem.Allocator) !u32 {
	_ = allocator;
	return r.u(32);
}

const Reader = struct {
    slice: []const u8,

    fn bytes_fixed(self: *Reader, comptime length: comptime_int) WasmParseError!*const [length]u8 {
        if (self.slice.len < length) {
            return WasmParseError.UnexpectedEndOfFileOrSection;
        }
        const r = self.slice[0..length];
        self.slice = self.slice[length..];
        return r;
    }

    fn bytes(self: *Reader, length: u32) WasmParseError![]const u8 {
        if (self.slice.len < length) {
            return WasmParseError.UnexpectedEndOfFileOrSection;
        }
        const r = self.slice[0..length];
        self.slice = self.slice[length..];
        return r;
    }

    fn bytes_n(self: *Reader)  WasmParseError![]const u8 {
        const length = try self.u(32);
        return self.bytes(length);
    }

    fn byte(self: *Reader) !u8 {
        if (self.slice.len < 1) {
            return WasmParseError.UnexpectedEndOfFileOrSection;
        }
        const r = self.slice[0];
        self.slice = self.slice[1..];
        return r;
    }

    fn u(self: *Reader, comptime bits: comptime_int) !@Type(.{.Int = .{.signedness = .unsigned, .bits = bits}}) {
        const T = @Type(.{.Int = .{.signedness = .unsigned, .bits = bits}});
        var r: T = 0;
        var offset: u8 = 0;
        while (true) {
            const b = try self.byte();
            r |= @as(T, b & 0b0111_1111) << @intCast(offset);
            if (b < 0b1000_0000) {
                return r;
            }
            offset += 7;
        }
    }
};

const WasmParseError = error {
    UnexpectedEndOfFileOrSection,
    WrongMagic,
    WrongVersion,
    InvalidFormat,
    ImportTypeNotSupported,
};