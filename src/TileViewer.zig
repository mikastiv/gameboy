const c = @import("c.zig");
const SdlContext = @import("SdlContext.zig");
const build_options = @import("build_options");
const Bus = @import("Bus.zig");

const TileViewer = @This();

window: ?*c.SDL_Window,
renderer: ?*c.SDL_Renderer,
texture: ?*c.SDL_Texture,

pub fn init(main_window: *c.SDL_Window) !TileViewer {
    if (build_options.tiles_viewer) {
        errdefer SdlContext.printError(@src().fn_name);

        const window = c.SDL_CreateWindow("Tiles Viewer", 800, 600, 0) orelse
            return error.SdlWindowCreation;

        const renderer = c.SDL_CreateRenderer(window, null) orelse
            return error.SdlRendererCreation;

        const tiles_per_row = 16;
        const tiles_per_col = 24;
        const pixels_per_tile_row = 8;
        const pixels_per_tile_col = 8;

        const texture = c.SDL_CreateTexture(
            renderer,
            c.SDL_PIXELFORMAT_RGBA32,
            c.SDL_TEXTUREACCESS_STREAMING,
            tiles_per_row * pixels_per_tile_row,
            tiles_per_col * pixels_per_tile_col,
        ) orelse return error.SdlTextureCreation;

        var w: c_int = undefined;
        _ = c.SDL_GetWindowSize(main_window, &w, null);

        var x: c_int = undefined;
        var y: c_int = undefined;
        _ = c.SDL_GetWindowPosition(main_window, &x, &y);
        _ = c.SDL_SetWindowPosition(window, x + w, y);

        return .{
            .window = window,
            .renderer = renderer,
            .texture = texture,
        };
    } else {
        return .{
            .window = null,
            .renderer = null,
            .texture = null,
        };
    }
}

pub fn deinit(self: TileViewer) void {
    if (build_options.tiles_viewer) {
        c.SDL_DestroyRenderer(self.renderer);
        c.SDL_DestroyWindow(self.window);
        c.SDL_Quit();
    }
}

pub fn update(self: *const TileViewer, bus: *const Bus) !void {
    _ = self; // autofix
    _ = bus; // autofix
}
