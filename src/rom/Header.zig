const std = @import("std");

const Header = @This();

const Region = enum(u8) {
    japan,
    overseas,
};

const header_len = 0x50;
const title_begin = 0x34;
const cgb_flag = 0x43;
const new_licensee = 0x44;
const old_licensee = 0x4B;
const cartridge_type_loc = 0x47;
const rom_size_loc = 0x48;
const ram_size_loc = 0x49;
const region_loc = 0x4A;
const version_loc = 0x4C;

logo: [0x30]u8,
title: []const u8,
licensee: []const u8,
cartridge_type: []const u8,
rom_size: u32,
n_banks: u8,
ram_size: u32,
region: Region,
rom_version: u8,
checksum: bool,

pub fn init(bytes: []const u8) Header {
    std.debug.assert(bytes.len == header_len);

    const title = bytes[title_begin .. title_begin + titleSize(bytes[cgb_flag])];
    const licensee = getLicensee(bytes[old_licensee], bytes[new_licensee .. new_licensee + 2].*);
    const cartridge_type = cartridge_types[bytes[cartridge_type_loc]];
    const rom_size = @as(u32, 32) << @truncate(bytes[rom_size_loc]);
    const n_banks = @as(u8, 2) << @truncate(bytes[rom_size_loc]);
    const ram_size: u32 = switch (bytes[ram_size_loc]) {
        0x02 => 8,
        0x03 => 32,
        0x04 => 128,
        0x05 => 64,
        else => 0,
    };
    const region: Region = switch (bytes[region_loc]) {
        0x00 => .japan,
        else => .overseas,
    };
    const version = bytes[version_loc];

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
        .checksum = true,
    };
}

pub fn write(self: *const Header, writer: anytype) !void {
    try writer.print("title: {s}\n", .{self.title});
    try writer.print("licensee: {s}\n", .{self.licensee});
    try writer.print("type: {s}\n", .{self.cartridge_type});

    try writer.print("rom size: ", .{});
    try std.fmt.fmtIntSizeBin(self.rom_size * 1024).format("", .{}, writer);
    try writer.print("\nram size: ", .{});
    try std.fmt.fmtIntSizeBin(self.ram_size * 1024).format("", .{}, writer);
    try writer.print("\nregion: {s}\n", .{@tagName(self.region)});
    try writer.print("version: {d}\n", .{self.rom_version});
}

fn getLicensee(old: u8, new: [2]u8) []const u8 {
    const hi = new[0] & 0x0F;
    const lo = new[1] & 0x0F;
    const new_code = hi << 4 | lo;

    if (old == 0x33)
        return new_licensee_names[new_code]
    else
        return old_licensee_names[old];
}

fn titleSize(flag: u8) u8 {
    const code = flag & 0xF0;
    if (code == 0x80 or code == 0xC0)
        return 0x0B
    else
        return 0x10;
}

const cartridge_types = blk: {
    var array: [0x100][]const u8 = undefined;
    array[0x00] = "ROM ONLY";
    array[0x01] = "MBC1";
    array[0x02] = "MBC1+RAM";
    array[0x03] = "MBC1+RAM+BATTERY";
    array[0x05] = "MBC2";
    array[0x06] = "MBC2+BATTERY";
    array[0x08] = "ROM+RAM 1";
    array[0x09] = "ROM+RAM+BATTERY 1";
    array[0x0B] = "MMM01";
    array[0x0C] = "MMM01+RAM";
    array[0x0D] = "MMM01+RAM+BATTERY";
    array[0x0F] = "MBC3+TIMER+BATTERY";
    array[0x10] = "MBC3+TIMER+RAM+BATTERY 2";
    array[0x11] = "MBC3";
    array[0x12] = "MBC3+RAM 2";
    array[0x13] = "MBC3+RAM+BATTERY 2";
    array[0x19] = "MBC5";
    array[0x1A] = "MBC5+RAM";
    array[0x1B] = "MBC5+RAM+BATTERY";
    array[0x1C] = "MBC5+RUMBLE";
    array[0x1D] = "MBC5+RUMBLE+RAM";
    array[0x1E] = "MBC5+RUMBLE+RAM+BATTERY";
    array[0x20] = "MBC6";
    array[0x22] = "MBC7+SENSOR+RUMBLE+RAM+BATTERY";
    array[0xFC] = "POCKET CAMERA";
    array[0xFD] = "BANDAI TAMA5";
    array[0xFE] = "HuC3";
    array[0xFF] = "HuC1+RAM+BATTERY";
    break :blk array;
};

// TODO: fix licensee tables
const new_licensee_names = blk: {
    var array: [0x100][]const u8 = undefined;
    array[0x00] = "None";
    array[0x01] = "Nintendo R&D1";
    array[0x08] = "Capcom";
    array[0x13] = "Electronic Arts";
    array[0x18] = "Hudson Soft";
    array[0x19] = "b-ai";
    array[0x20] = "kss";
    array[0x22] = "pow";
    array[0x24] = "PCM Complete";
    array[0x25] = "san-x";
    array[0x28] = "Kemco Japan";
    array[0x29] = "seta";
    array[0x30] = "Viacom";
    array[0x31] = "Nintendo";
    array[0x32] = "Bandai";
    array[0x33] = "Ocean/Acclaim";
    array[0x34] = "Konami";
    array[0x35] = "Hector";
    array[0x37] = "Taito";
    array[0x38] = "Hudson";
    array[0x39] = "Banpresto";
    array[0x41] = "Ubi Soft";
    array[0x42] = "Atlus";
    array[0x44] = "Malibu";
    array[0x46] = "angel";
    array[0x47] = "Bullet-Proof";
    array[0x49] = "irem";
    array[0x50] = "Absolute";
    array[0x51] = "Acclaim";
    array[0x52] = "Activision";
    array[0x53] = "American sammy";
    array[0x54] = "Konami";
    array[0x55] = "Hi tech entertainment";
    array[0x56] = "LJN";
    array[0x57] = "Matchbox";
    array[0x58] = "Mattel";
    array[0x59] = "Milton Bradley";
    array[0x60] = "Titus";
    array[0x61] = "Virgin";
    array[0x64] = "LucasArts";
    array[0x67] = "Ocean";
    array[0x69] = "Electronic Arts";
    array[0x70] = "Infogrames";
    array[0x71] = "Interplay";
    array[0x72] = "Broderbund";
    array[0x73] = "sculptured";
    array[0x75] = "sci";
    array[0x78] = "THQ";
    array[0x79] = "Accolade";
    array[0x80] = "misawa";
    array[0x83] = "lozc";
    array[0x86] = "Tokuma Shoten Intermedia";
    array[0x87] = "Tsukuda Original";
    array[0x91] = "Chunsoft";
    array[0x92] = "Video system";
    array[0x93] = "Ocean/Acclaim";
    array[0x95] = "Varie";
    array[0x96] = "Yonezawa/s’pal";
    array[0x97] = "Kaneko";
    array[0x99] = "Pack in soft";
    array[0xA4] = "Konami (Yu-Gi-Oh!)";
    break :blk array;
};

const old_licensee_names = blk: {
    var array: [0x100][]const u8 = undefined;
    array[0x00] = "None";
    array[0x01] = "Nintendo";
    array[0x08] = "Capcom";
    array[0x09] = "Hot-B";
    array[0x0A] = "Jaleco";
    array[0x0B] = "Coconuts Japan";
    array[0x0C] = "Elite Systems";
    array[0x13] = "EA (Electronic Arts)";
    array[0x18] = "Hudsonsoft";
    array[0x19] = "ITC Entertainment";
    array[0x1A] = "Yanoman";
    array[0x1D] = "Japan Clary";
    array[0x1F] = "Virgin Interactive";
    array[0x24] = "PCM Complete";
    array[0x25] = "San-X";
    array[0x28] = "Kotobuki Systems";
    array[0x29] = "Seta";
    array[0x30] = "Infogrames";
    array[0x31] = "Nintendo";
    array[0x32] = "Bandai";
    array[0x33] = "Indicates that the New licensee code should be used instead.";
    array[0x34] = "Konami";
    array[0x35] = "HectorSoft";
    array[0x38] = "Capcom";
    array[0x39] = "Banpresto";
    array[0x3C] = ".Entertainment i";
    array[0x3E] = "Gremlin";
    array[0x41] = "Ubisoft";
    array[0x42] = "Atlus";
    array[0x44] = "Malibu";
    array[0x46] = "Angel";
    array[0x47] = "Spectrum Holoby";
    array[0x49] = "Irem";
    array[0x4A] = "Virgin Interactive";
    array[0x4D] = "Malibu";
    array[0x4F] = "U.S. Gold";
    array[0x50] = "Absolute";
    array[0x51] = "Acclaim";
    array[0x52] = "Activision";
    array[0x53] = "American Sammy";
    array[0x54] = "GameTek";
    array[0x55] = "Park Place";
    array[0x56] = "LJN";
    array[0x57] = "Matchbox";
    array[0x59] = "Milton Bradley";
    array[0x5A] = "Mindscape";
    array[0x5B] = "Romstar";
    array[0x5C] = "Naxat Soft";
    array[0x5D] = "Tradewest";
    array[0x60] = "Titus";
    array[0x61] = "Virgin Interactive";
    array[0x67] = "Ocean Interactive";
    array[0x69] = "EA (Electronic Arts)";
    array[0x6E] = "Elite Systems";
    array[0x6F] = "Electro Brain";
    array[0x70] = "Infogrames";
    array[0x71] = "Interplay";
    array[0x72] = "Broderbund";
    array[0x73] = "Sculptered Soft";
    array[0x75] = "The Sales Curve";
    array[0x78] = "t.hq";
    array[0x79] = "Accolade";
    array[0x7A] = "Triffix Entertainment";
    array[0x7C] = "Microprose";
    array[0x7F] = "Kemco";
    array[0x80] = "Misawa Entertainment";
    array[0x83] = "Lozc";
    array[0x86] = "Tokuma Shoten Intermedia";
    array[0x8B] = "Bullet-Proof Software";
    array[0x8C] = "Vic Tokai";
    array[0x8E] = "Ape";
    array[0x8F] = "I’Max";
    array[0x91] = "Chunsoft Co.";
    array[0x92] = "Video System";
    array[0x93] = "Tsubaraya Productions Co.";
    array[0x95] = "Varie Corporation";
    array[0x96] = "Yonezawa/S’Pal";
    array[0x97] = "Kaneko";
    array[0x99] = "Arc";
    array[0x9A] = "Nihon Bussan";
    array[0x9B] = "Tecmo";
    array[0x9C] = "Imagineer";
    array[0x9D] = "Banpresto";
    array[0x9F] = "Nova";
    array[0xA1] = "Hori Electric";
    array[0xA2] = "Bandai";
    array[0xA4] = "Konami";
    array[0xA6] = "Kawada";
    array[0xA7] = "Takara";
    array[0xA9] = "Technos Japan";
    array[0xAA] = "Broderbund";
    array[0xAC] = "Toei Animation";
    array[0xAD] = "Toho";
    array[0xAF] = "Namco";
    array[0xB0] = "acclaim";
    array[0xB1] = "ASCII or Nexsoft";
    array[0xB2] = "Bandai";
    array[0xB4] = "Square Enix";
    array[0xB6] = "HAL Laboratory";
    array[0xB7] = "SNK";
    array[0xB9] = "Pony Canyon";
    array[0xBA] = "Culture Brain";
    array[0xBB] = "Sunsoft";
    array[0xBD] = "Sony Imagesoft";
    array[0xBF] = "Sammy";
    array[0xC0] = "Taito";
    array[0xC2] = "Kemco";
    array[0xC3] = "Squaresoft";
    array[0xC4] = "Tokuma Shoten Intermedia";
    array[0xC5] = "Data East";
    array[0xC6] = "Tonkinhouse";
    array[0xC8] = "Koei";
    array[0xC9] = "UFL";
    array[0xCA] = "Ultra";
    array[0xCB] = "Vap";
    array[0xCC] = "Use Corporation";
    array[0xCD] = "Meldac";
    array[0xCE] = ".Pony Canyon or";
    array[0xCF] = "Angel";
    array[0xD0] = "Taito";
    array[0xD1] = "Sofel";
    array[0xD2] = "Quest";
    array[0xD3] = "Sigma Enterprises";
    array[0xD4] = "ASK Kodansha Co.";
    array[0xD6] = "Naxat Soft";
    array[0xD7] = "Copya System";
    array[0xD9] = "Banpresto";
    array[0xDA] = "Tomy";
    array[0xDB] = "LJN";
    array[0xDD] = "NCS";
    array[0xDE] = "Human";
    array[0xDF] = "Altron";
    array[0xE0] = "Jaleco";
    array[0xE1] = "Towa Chiki";
    array[0xE2] = "Yutaka";
    array[0xE3] = "Varie";
    array[0xE5] = "Epcoh";
    array[0xE7] = "Athena";
    array[0xE8] = "Asmik ACE Entertainment";
    array[0xE9] = "Natsume";
    array[0xEA] = "King Records";
    array[0xEB] = "Atlus";
    array[0xEC] = "Epic/Sony Records";
    array[0xEE] = "IGS";
    array[0xF0] = "A Wave";
    array[0xF3] = "Extreme Entertainment";
    array[0xFF] = "LJN";
    break :blk array;
};
