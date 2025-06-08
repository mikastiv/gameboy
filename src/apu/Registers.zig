const Registers = @This();

nr50: packed struct(u8) {
    volume_right: u3,
    vin_right: bool,
    volume_left: u3,
    vin_left: bool,
},
nr51: packed struct(u8) {
    ch1_right: bool,
    ch2_right: bool,
    ch3_right: bool,
    ch4_right: bool,
    ch1_left: bool,
    ch2_left: bool,
    ch3_left: bool,
    ch4_left: bool,
},
nr52: packed struct(u8) {
    ch1_on: bool,
    ch2_on: bool,
    ch3_on: bool,
    ch4_on: bool,
    _unused: u3,
    audio_on: bool,
},
