with import <nixpkgs> {};
stdenv.mkDerivation {
  name = "c env";
  buildInputs = [ xorg.libX11 xorg.libXext xorg.libxcb libGL pulseaudio systemd.dev ];
}
