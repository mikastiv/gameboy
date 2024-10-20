const std = @import("std");

const Header = @This();

const Region = enum(u8) {
    japan = 0x00,
    overseas_only = 0x01,
};

const CartridgeType = enum(u8) {
    rom_only = 0x00,
    mbc1 = 0x01,
    mbc1_ram = 0x02,
    mbc1_ram_battery = 0x03,
    mbc2 = 0x05,
    mbc2_battery = 0x06,
    rom_ram_1 = 0x08,
    rom_ram_battery_1 = 0x09,
    mmm01 = 0x0B,
    mmm01_ram = 0x0C,
    mmm01_ram_battery = 0x0D,
    mbc3_timer_battery = 0x0F,
    mbc3_timer_ram_battery_2 = 0x10,
    mbc3 = 0x11,
    mbc3_ram_2 = 0x12,
    mbc3_ram_battery_2 = 0x13,
    mbc5 = 0x19,
    mbc5_ram = 0x1A,
    mbc5_ram_battery = 0x1B,
    mbc5_rumble = 0x1C,
    mbc5_rumble_ram = 0x1D,
    mbc5_rumble_ram_battery = 0x1E,
    mbc6 = 0x20,
    mbc7_sensor_rumble_ram_battery = 0x22,
    pocket_camera = 0xFC,
    bandai_tama5 = 0xFD,
    huc3 = 0xFE,
    huc1_ram_battery = 0xFF,
};

logo: [0x30]u8,
title: []const u8,
licensee: []const u8,
cartridge_type: CartridgeType,
rom_size: u32,
n_banks: u8,
ram_size: u32,
region: Region,
rom_version: u8,
checksum: bool,

pub fn init(rom: []const u8) Header {
    const bytes = rom[0x100..0x150];

    const cgb_flag = bytes[0x43];
    const title = bytes[0x34 .. 0x34 + titleSize(cgb_flag)];
    const licensee = getLicensee(bytes[0x4B], bytes[0x44..0x46].*);
    const cartridge_type: CartridgeType = @enumFromInt(bytes[0x47]);
    const rom_size = @as(u32, 32) << @truncate(bytes[0x48]);
    const n_banks = @as(u8, 2) << @truncate(bytes[0x48]);
    const ram_size: u32 = switch (bytes[0x49]) {
        0x02 => 8,
        0x03 => 32,
        0x04 => 128,
        0x05 => 64,
        else => 0,
    };
    const region: Region = @enumFromInt(bytes[0x4A]);
    const version = bytes[0x4C];
    const checksum = getChecksum(bytes[0x34..0x4D]);

    return .{
        .logo = bytes[0x04..0x34].*,
        .title = title,
        .licensee = licensee,
        .cartridge_type = cartridge_type,
        .rom_size = rom_size,
        .n_banks = n_banks,
        .ram_size = ram_size,
        .region = region,
        .rom_version = version,
        .checksum = checksum == bytes[0x4D],
    };
}

pub fn write(self: *const Header, writer: anytype) !void {
    try writer.print("title: {s}\n", .{self.title});
    try writer.print("licensee: {s}\n", .{self.licensee});
    try writer.print("region: {s}\n", .{@tagName(self.region)});
    try writer.print("version: {d}\n", .{self.rom_version});
    try writer.print("checksum: {s}\n", .{if (self.checksum) "ok" else "bad"});

    try writer.print("type: {s}\n", .{@tagName(self.cartridge_type)});
    try writer.print("rom size: ", .{});
    try writer.print("{}\n", .{std.fmt.fmtIntSizeBin(self.rom_size * 1024)});
    try writer.print("ram size: ", .{});
    try writer.print("{}\n", .{std.fmt.fmtIntSizeBin(self.ram_size * 1024)});
}

fn getChecksum(bytes: []const u8) u8 {
    var sum: u8 = 0;
    for (bytes) |byte| {
        sum = sum -% byte -% 1;
    }

    return sum;
}

fn getLicensee(old: u8, new: [2]u8) []const u8 {
    return if (old == 0x33)
        new_licensee_names.get(&.{ new[0], new[1] }) orelse "Unknown"
    else
        old_licensee_names.get(&.{old}) orelse "Unknown";
}

fn titleSize(flag: u8) u8 {
    const code = flag & 0xF0;
    if (code == 0x80 or code == 0xC0)
        return 0x0B
    else
        return 0x10;
}

const new_licensee_names = std.StaticStringMap([]const u8).initComptime(.{
    .{ "00", "None" },
    .{ "01", "Nintendo R&D1" },
    .{ "08", "Capcom" },
    .{ "13", "Electronic Arts" },
    .{ "18", "Hudson Soft" },
    .{ "19", "b-ai" },
    .{ "20", "kss" },
    .{ "22", "pow" },
    .{ "24", "PCM Complete" },
    .{ "25", "san-x" },
    .{ "28", "Kemco Japan" },
    .{ "29", "seta" },
    .{ "30", "Viacom" },
    .{ "31", "Nintendo" },
    .{ "32", "Bandai" },
    .{ "33", "Ocean/Acclaim" },
    .{ "34", "Konami" },
    .{ "35", "Hector" },
    .{ "37", "Taito" },
    .{ "38", "Hudson" },
    .{ "39", "Banpresto" },
    .{ "41", "Ubi Soft" },
    .{ "42", "Atlus" },
    .{ "44", "Malibu" },
    .{ "46", "angel" },
    .{ "47", "Bullet-Proof" },
    .{ "49", "irem" },
    .{ "50", "Absolute" },
    .{ "51", "Acclaim" },
    .{ "52", "Activision" },
    .{ "53", "American sammy" },
    .{ "54", "Konami" },
    .{ "55", "Hi tech entertainment" },
    .{ "56", "LJN" },
    .{ "57", "Matchbox" },
    .{ "58", "Mattel" },
    .{ "59", "Milton Bradley" },
    .{ "60", "Titus" },
    .{ "61", "Virgin" },
    .{ "64", "LucasArts" },
    .{ "67", "Ocean" },
    .{ "69", "Electronic Arts" },
    .{ "70", "Infogrames" },
    .{ "71", "Interplay" },
    .{ "72", "Broderbund" },
    .{ "73", "sculptured" },
    .{ "75", "sci" },
    .{ "78", "THQ" },
    .{ "79", "Accolade" },
    .{ "80", "misawa" },
    .{ "83", "lozc" },
    .{ "86", "Tokuma Shoten Intermedia" },
    .{ "87", "Tsukuda Original" },
    .{ "91", "Chunsoft" },
    .{ "92", "Video system" },
    .{ "93", "Ocean/Acclaim" },
    .{ "95", "Varie" },
    .{ "96", "Yonezawa/s’pal" },
    .{ "97", "Kaneko" },
    .{ "99", "Pack in soft" },
    .{ "A4", "Konami (Yu-Gi-Oh!)" },
});

const old_licensee_names = std.StaticStringMap([]const u8).initComptime(.{
    .{ "\x00", "None" },
    .{ "\x01", "Nintendo" },
    .{ "\x08", "Capcom" },
    .{ "\x09", "Hot-B" },
    .{ "\x0A", "Jaleco" },
    .{ "\x0B", "Coconuts Japan" },
    .{ "\x0C", "Elite Systems" },
    .{ "\x13", "EA (Electronic Arts)" },
    .{ "\x18", "Hudsonsoft" },
    .{ "\x19", "ITC Entertainment" },
    .{ "\x1A", "Yanoman" },
    .{ "\x1D", "Japan Clary" },
    .{ "\x1F", "Virgin Interactive" },
    .{ "\x24", "PCM Complete" },
    .{ "\x25", "San-X" },
    .{ "\x28", "Kotobuki Systems" },
    .{ "\x29", "Seta" },
    .{ "\x30", "Infogrames" },
    .{ "\x31", "Nintendo" },
    .{ "\x32", "Bandai" },
    .{ "\x34", "Konami" },
    .{ "\x35", "HectorSoft" },
    .{ "\x38", "Capcom" },
    .{ "\x39", "Banpresto" },
    .{ "\x3C", ".Entertainment i" },
    .{ "\x3E", "Gremlin" },
    .{ "\x41", "Ubisoft" },
    .{ "\x42", "Atlus" },
    .{ "\x44", "Malibu" },
    .{ "\x46", "Angel" },
    .{ "\x47", "Spectrum Holoby" },
    .{ "\x49", "Irem" },
    .{ "\x4A", "Virgin Interactive" },
    .{ "\x4D", "Malibu" },
    .{ "\x4F", "U.S. Gold" },
    .{ "\x50", "Absolute" },
    .{ "\x51", "Acclaim" },
    .{ "\x52", "Activision" },
    .{ "\x53", "American Sammy" },
    .{ "\x54", "GameTek" },
    .{ "\x55", "Park Place" },
    .{ "\x56", "LJN" },
    .{ "\x57", "Matchbox" },
    .{ "\x59", "Milton Bradley" },
    .{ "\x5A", "Mindscape" },
    .{ "\x5B", "Romstar" },
    .{ "\x5C", "Naxat Soft" },
    .{ "\x5D", "Tradewest" },
    .{ "\x60", "Titus" },
    .{ "\x61", "Virgin Interactive" },
    .{ "\x67", "Ocean Interactive" },
    .{ "\x69", "EA (Electronic Arts)" },
    .{ "\x6E", "Elite Systems" },
    .{ "\x6F", "Electro Brain" },
    .{ "\x70", "Infogrames" },
    .{ "\x71", "Interplay" },
    .{ "\x72", "Broderbund" },
    .{ "\x73", "Sculptered Soft" },
    .{ "\x75", "The Sales Curve" },
    .{ "\x78", "t.hq" },
    .{ "\x79", "Accolade" },
    .{ "\x7A", "Triffix Entertainment" },
    .{ "\x7C", "Microprose" },
    .{ "\x7F", "Kemco" },
    .{ "\x80", "Misawa Entertainment" },
    .{ "\x83", "Lozc" },
    .{ "\x86", "Tokuma Shoten Intermedia" },
    .{ "\x8B", "Bullet-Proof Software" },
    .{ "\x8C", "Vic Tokai" },
    .{ "\x8E", "Ape" },
    .{ "\x8F", "I’Max" },
    .{ "\x91", "Chunsoft Co." },
    .{ "\x92", "Video System" },
    .{ "\x93", "Tsubaraya Productions Co." },
    .{ "\x95", "Varie Corporation" },
    .{ "\x96", "Yonezawa/S’Pal" },
    .{ "\x97", "Kaneko" },
    .{ "\x99", "Arc" },
    .{ "\x9A", "Nihon Bussan" },
    .{ "\x9B", "Tecmo" },
    .{ "\x9C", "Imagineer" },
    .{ "\x9D", "Banpresto" },
    .{ "\x9F", "Nova" },
    .{ "\xA1", "Hori Electric" },
    .{ "\xA2", "Bandai" },
    .{ "\xA4", "Konami" },
    .{ "\xA6", "Kawada" },
    .{ "\xA7", "Takara" },
    .{ "\xA9", "Technos Japan" },
    .{ "\xAA", "Broderbund" },
    .{ "\xAC", "Toei Animation" },
    .{ "\xAD", "Toho" },
    .{ "\xAF", "Namco" },
    .{ "\xB0", "acclaim" },
    .{ "\xB1", "ASCII or Nexsoft" },
    .{ "\xB2", "Bandai" },
    .{ "\xB4", "Square Enix" },
    .{ "\xB6", "HAL Laboratory" },
    .{ "\xB7", "SNK" },
    .{ "\xB9", "Pony Canyon" },
    .{ "\xBA", "Culture Brain" },
    .{ "\xBB", "Sunsoft" },
    .{ "\xBD", "Sony Imagesoft" },
    .{ "\xBF", "Sammy" },
    .{ "\xC0", "Taito" },
    .{ "\xC2", "Kemco" },
    .{ "\xC3", "Squaresoft" },
    .{ "\xC4", "Tokuma Shoten Intermedia" },
    .{ "\xC5", "Data East" },
    .{ "\xC6", "Tonkinhouse" },
    .{ "\xC8", "Koei" },
    .{ "\xC9", "UFL" },
    .{ "\xCA", "Ultra" },
    .{ "\xCB", "Vap" },
    .{ "\xCC", "Use Corporation" },
    .{ "\xCD", "Meldac" },
    .{ "\xCE", ".Pony Canyon or" },
    .{ "\xCF", "Angel" },
    .{ "\xD0", "Taito" },
    .{ "\xD1", "Sofel" },
    .{ "\xD2", "Quest" },
    .{ "\xD3", "Sigma Enterprises" },
    .{ "\xD4", "ASK Kodansha Co." },
    .{ "\xD6", "Naxat Soft" },
    .{ "\xD7", "Copya System" },
    .{ "\xD9", "Banpresto" },
    .{ "\xDA", "Tomy" },
    .{ "\xDB", "LJN" },
    .{ "\xDD", "NCS" },
    .{ "\xDE", "Human" },
    .{ "\xDF", "Altron" },
    .{ "\xE0", "Jaleco" },
    .{ "\xE1", "Towa Chiki" },
    .{ "\xE2", "Yutaka" },
    .{ "\xE3", "Varie" },
    .{ "\xE5", "Epcoh" },
    .{ "\xE7", "Athena" },
    .{ "\xE8", "Asmik ACE Entertainment" },
    .{ "\xE9", "Natsume" },
    .{ "\xEA", "King Records" },
    .{ "\xEB", "Atlus" },
    .{ "\xEC", "Epic/Sony Records" },
    .{ "\xEE", "IGS" },
    .{ "\xF0", "A Wave" },
    .{ "\xF3", "Extreme Entertainment" },
    .{ "\xFF", "LJN" },
});
