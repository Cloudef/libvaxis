const std = @import("std");
const Image = @import("Image.zig");

char: Character = .{},
style: Style = .{},
link: Hyperlink = .{},
image: ?Image.Placement = null,
default: bool = false,

/// Segment is a contiguous run of text that has a constant style
pub const Segment = struct {
    text: []const u8,
    style: Style = .{},
    link: Hyperlink = .{},
};

pub const Character = struct {
    grapheme: []const u8 = " ",
    /// width should only be provided when the application is sure the terminal
    /// will measure the same width. This can be ensure by using the gwidth method
    /// included in libvaxis. If width is 0, libvaxis will measure the glyph at
    /// render time
    width: usize = 1,
};

pub const CursorShape = enum {
    default,
    block_blink,
    block,
    underline_blink,
    underline,
    beam_blink,
    beam,
};

pub const Hyperlink = struct {
    uri: []const u8 = "",
    /// ie "id=app-1234"
    params: []const u8 = "",
};

pub const Style = struct {
    pub const Underline = enum {
        off,
        single,
        double,
        curly,
        dotted,
        dashed,
    };

    fg: Color = .default,
    bg: Color = .default,
    ul: Color = .default,
    ul_style: Underline = .off,

    bold: bool = false,
    dim: bool = false,
    italic: bool = false,
    blink: bool = false,
    reverse: bool = false,
    invisible: bool = false,
    strikethrough: bool = false,

    pub fn eql(a: Style, b: Style) bool {
        const SGRBits = packed struct {
            bold: bool,
            dim: bool,
            italic: bool,
            blink: bool,
            reverse: bool,
            invisible: bool,
            strikethrough: bool,
        };
        const a_sgr: SGRBits = .{
            .bold = a.bold,
            .dim = a.dim,
            .italic = a.italic,
            .blink = a.blink,
            .reverse = a.reverse,
            .invisible = a.invisible,
            .strikethrough = a.strikethrough,
        };
        const b_sgr: SGRBits = .{
            .bold = b.bold,
            .dim = b.dim,
            .italic = b.italic,
            .blink = b.blink,
            .reverse = b.reverse,
            .invisible = b.invisible,
            .strikethrough = b.strikethrough,
        };
        const a_cast: u7 = @bitCast(a_sgr);
        const b_cast: u7 = @bitCast(b_sgr);
        return a_cast == b_cast and
            Color.eql(a.fg, b.fg) and
            Color.eql(a.bg, b.bg) and
            Color.eql(a.ul, b.ul) and
            a.ul_style == b.ul_style;
    }
};

pub const Color = union(enum) {
    default,
    index: u8,
    rgb: [3]u8,

    pub const Kind = union(enum) {
        fg,
        bg,
        cursor,
        index: u8,
    };

    /// Returned when querying a color from the terminal
    pub const Report = struct {
        kind: Kind,
        value: [3]u8,
    };

    pub const Scheme = enum {
        dark,
        light,
    };

    pub fn eql(a: Color, b: Color) bool {
        switch (a) {
            .default => return b == .default,
            .index => |a_idx| {
                switch (b) {
                    .index => |b_idx| return a_idx == b_idx,
                    else => return false,
                }
            },
            .rgb => |a_rgb| {
                switch (b) {
                    .rgb => |b_rgb| return a_rgb[0] == b_rgb[0] and
                        a_rgb[1] == b_rgb[1] and
                        a_rgb[2] == b_rgb[2],
                    else => return false,
                }
            },
        }
    }

    pub fn rgbFromUint(val: u24) Color {
        const r_bits = val & 0b11111111_00000000_00000000;
        const g_bits = val & 0b00000000_11111111_00000000;
        const b_bits = val & 0b00000000_00000000_11111111;
        const rgb = [_]u8{
            @truncate(r_bits >> 16),
            @truncate(g_bits >> 8),
            @truncate(b_bits),
        };
        return .{ .rgb = rgb };
    }

    /// parse an XParseColor-style rgb specification into an rgb Color. The spec
    /// is of the form: rgb:rrrr/gggg/bbbb. Generally, the high two bits will always
    /// be the same as the low two bits.
    pub fn rgbFromSpec(spec: []const u8) !Color {
        var iter = std.mem.splitScalar(u8, spec, ':');
        const prefix = iter.next() orelse return error.InvalidColorSpec;
        if (!std.mem.eql(u8, "rgb", prefix)) return error.InvalidColorSpec;

        const spec_str = iter.next() orelse return error.InvalidColorSpec;

        var spec_iter = std.mem.splitScalar(u8, spec_str, '/');

        const r_raw = spec_iter.next() orelse return error.InvalidColorSpec;
        if (r_raw.len != 4) return error.InvalidColorSpec;

        const g_raw = spec_iter.next() orelse return error.InvalidColorSpec;
        if (g_raw.len != 4) return error.InvalidColorSpec;

        const b_raw = spec_iter.next() orelse return error.InvalidColorSpec;
        if (b_raw.len != 4) return error.InvalidColorSpec;

        const r = try std.fmt.parseUnsigned(u8, r_raw[2..], 16);
        const g = try std.fmt.parseUnsigned(u8, g_raw[2..], 16);
        const b = try std.fmt.parseUnsigned(u8, b_raw[2..], 16);

        return .{
            .rgb = [_]u8{ r, g, b },
        };
    }

    test "rgbFromSpec" {
        const spec = "rgb:aaaa/bbbb/cccc";
        const actual = try rgbFromSpec(spec);
        switch (actual) {
            .rgb => |rgb| {
                try std.testing.expectEqual(0xAA, rgb[0]);
                try std.testing.expectEqual(0xBB, rgb[1]);
                try std.testing.expectEqual(0xCC, rgb[2]);
            },
            else => try std.testing.expect(false),
        }
    }
};

pub const PackedGrapheme = enum(u32) {
    _,

    pub fn init(bytes: []const u8) @This() {
        var this: @This() = @enumFromInt(0);
        @memcpy(std.mem.asBytes(&this)[0..bytes.len], bytes[0..]);
        return this;
    }

    pub fn asBytes(self: @This()) [@sizeOf(u32)]u8 {
        return std.mem.toBytes(@intFromEnum(self));
    }
};

pub const Fingerprint = packed struct(u64) {
    perfect_hash: bool = true,
    fg_rgb: bool = false,
    bg_rgb: bool = false,
    ul_rgb: bool = false,
    fg: std.math.IntFittingRange(0, 16) = 16,
    bg: std.math.IntFittingRange(0, 16) = 16,
    ul: std.math.IntFittingRange(0, 16) = 16,
    ul_style: std.math.IntFittingRange(0, std.meta.fields(Style.Underline).len) = 0,
    bold: bool = false,
    dim: bool = false,
    italic: bool = false,
    reverse: bool = false,
    invisible: bool = false,
    strikethrough: bool = false,
    grapheme: PackedGrapheme = PackedGrapheme.init(" "),
    padding: u4 = 0,

    pub const Scalar = u64;

    pub fn asScalar(self: @This()) Scalar {
        return @bitCast(self);
    }
};

pub fn fingerprint(self: @This()) Fingerprint {
    if (self.default) {
        return .{};
    }
    if (self.image) |_| {
        return .{ .perfect_hash = false };
    }
    if (self.link.uri.len > 0 or self.link.params.len > 0) {
        return .{ .perfect_hash = false };
    }
    if (self.char.width > @sizeOf(u32)) {
        return .{ .perfect_hash = false };
    }
    return .{
        .fg_rgb = std.meta.activeTag(self.style.fg) == .rgb,
        .fg = switch (self.style.fg) {
            .default, .rgb => 16,
            .index => |index| @intCast(index),
        },
        .bg_rgb = std.meta.activeTag(self.style.bg) == .rgb,
        .bg = switch (self.style.bg) {
            .default, .rgb => 16,
            .index => |index| @intCast(index),
        },
        .ul_rgb = std.meta.activeTag(self.style.ul) == .rgb,
        .ul = switch (self.style.ul) {
            .default, .rgb => 16,
            .index => |index| @intCast(index),
        },
        .ul_style = @intFromEnum(self.style.ul_style),
        .bold = self.style.bold,
        .dim = self.style.dim,
        .italic = self.style.italic,
        .reverse = self.style.reverse,
        .invisible = self.style.invisible,
        .strikethrough = self.style.strikethrough,
        .grapheme = PackedGrapheme.init(self.char.grapheme),
    };
}
