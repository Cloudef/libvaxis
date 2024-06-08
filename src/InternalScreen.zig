const std = @import("std");
const assert = std.debug.assert;
const Style = @import("Cell.zig").Style;
const Cell = @import("Cell.zig");
const MouseShape = @import("Mouse.zig").Shape;
const CursorShape = Cell.CursorShape;
const Fingerprint = Cell.Fingerprint;

const log = std.log.scoped(.internal_screen);

const InternalScreen = @This();

width: usize = 0,
height: usize = 0,

buf: []Fingerprint = undefined,

cursor_row: usize = 0,
cursor_col: usize = 0,
cursor_vis: bool = false,
cursor_shape: CursorShape = .default,

mouse_shape: MouseShape = .default,

/// sets each cell to the default cell
pub fn init(alloc: std.mem.Allocator, w: usize, h: usize) !InternalScreen {
    var screen = InternalScreen{
        .buf = try alloc.alloc(Fingerprint, w * h),
    };
    @memset(screen.buf, .{});
    screen.width = w;
    screen.height = h;
    return screen;
}

pub fn deinit(self: *InternalScreen, alloc: std.mem.Allocator) void {
    alloc.free(self.buf);
}

/// writes a cell to a location. 0 indexed
pub fn writeFingeprint(
    self: *InternalScreen,
    col: usize,
    row: usize,
    fp: Fingerprint,
) void {
    if (self.width <= col) {
        // column out of bounds
        return;
    }
    if (self.height <= row) {
        // height out of bounds
        return;
    }
    const i = (row * self.width) + col;
    assert(i < self.buf.len);
    self.buf[i] = fp;
}
