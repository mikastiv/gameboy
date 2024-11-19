const Registers = @This();

pub const Control = packed struct(u8) {
    bgw_on: bool,
    obj_on: bool,
    obj_size: bool,
    bg_map: bool,
    bgw_data: bool,
    win_on: bool,
    win_map: bool,
    lcd_on: bool,

    pub fn objSize(self: Registers) u8 {
        return if (self.bit.obj_size) 16 else 8;
    }

    pub fn bgTileMapArea(self: Registers) u16 {
        return if (self.bit.bg_map) 0x9C00 else 0x9800;
    }

    pub fn bgwTileDataArea(self: Registers) u16 {
        return if (self.bit.bgw_data) 0x8000 else 0x8800;
    }

    pub fn winTileMapArea(self: Registers) u16 {
        return if (self.bit.win_map) 0x9C00 else 0x9800;
    }
};

pub const Mode = enum(u2) {
    hblank = 0,
    vblank = 1,
    oam_scan = 2,
    drawing = 3,
};

pub const Stat = packed struct(u8) {
    mode: Mode,
    match_flag: bool,
    hblank_int: bool,
    vblank_int: bool,
    oam_int: bool,
    match_int: bool,
    _unused: bool = false,
};

ctrl: Control,
stat: Stat,
scx: u8,
scy: u8,
wx: u8,
wy: u8,
ly: u8,
lyc: u8,
bg_pal: u8,
obj_pal: [2]u8,

pub const init: Registers = .{
    .ctrl = .{
        .bgw_on = false,
        .obj_on = false,
        .obj_size = false,
        .bg_map = false,
        .bgw_data = false,
        .win_on = false,
        .win_map = false,
        .lcd_on = false,
    },
    .stat = .{
        .mode = .oam_scan,
        .match_flag = false,
        .hblank_int = false,
        .vblank_int = false,
        .oam_int = false,
        .match_int = false,
    },
    .scx = 0,
    .scy = 0,
    .wx = 0,
    .wy = 0,
    .ly = 0,
    .lyc = 0,
    .bg_pal = 0,
    .obj_pal = .{ 0, 0 },
};
