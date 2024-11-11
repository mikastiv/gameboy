const std = @import("std");

/// Cast a value to a different type. For a cast between two integer types,
/// will extend the sign then bitcast for a result type with a bigger bit size
/// and will truncate for a smaller bit size.
pub fn cast(comptime T: type, value: anytype) T {
    const V = @TypeOf(value);

    return switch (@typeInfo(T)) {
        .float => switch (@typeInfo(V)) {
            .comptime_int, .comptime_float => value,
            .int => @floatFromInt(value),
            .float => @floatCast(value),
            else => @compileError("bad value type"),
        },
        .int => switch (@typeInfo(V)) {
            .comptime_int => value,
            .int => blk: {
                const dst_info = @typeInfo(T).int;
                const src_info = @typeInfo(V).int;

                const KeepSign = @Type(.{
                    .int = .{
                        .bits = dst_info.bits,
                        .signedness = src_info.signedness,
                    },
                });

                const tmp: KeepSign = if (src_info.bits > dst_info.bits)
                    @truncate(value)
                else
                    value;

                break :blk @bitCast(tmp);
            },
            .float, .comptime_float => @intFromFloat(value),
            else => @compileError("bad value type"),
        },
        else => @compileError("bad result type"),
    };
}

test "cast" {
    const expect = std.testing.expect;

    try expect(cast(u8, @as(i8, -1)) == 0xFF);
    try expect(cast(u16, @as(i8, -1)) == 0xFFFF);
    try expect(cast(u16, @as(u8, 0xFF)) == 0xFF);
    try expect(cast(i16, @as(i8, -1)) == -1);
    try expect(cast(i16, @as(i32, -1)) == -1);
    try expect(cast(i32, @as(u32, std.math.maxInt(u32))) == -1);
    try expect(cast(u16, @as(u32, 0x234AFFFF)) == 0xFFFF);
}
