const c = @import("c.zig");
const SdlContext = @import("SdlContext.zig");
const build_options = @import("build_options");
const Bus = @import("Bus.zig");

const TilesViewer = @This();

const tiles_per_row = 16;
const tiles_per_col = 24;
const pixels_per_tile_row = 8;
const pixels_per_tile_col = 8;

window: ?*c.SDL_Window,
renderer: ?*c.SDL_Renderer,
texture: ?*c.SDL_Texture,

pub fn init(main_window: *c.SDL_Window) !TilesViewer {
    if (build_options.tiles_viewer) {
        errdefer SdlContext.printError(@src().fn_name);

        const window = c.SDL_CreateWindow("Tiles Viewer", 600, 600, 0) orelse
            return error.SdlWindowCreation;

        const renderer = c.SDL_CreateRenderer(window, null) orelse
            return error.SdlRendererCreation;

        const texture = c.SDL_CreateTexture(
            renderer,
            c.SDL_PIXELFORMAT_RGBA8888,
            c.SDL_TEXTUREACCESS_TARGET,
            tiles_per_row * pixels_per_tile_row,
            tiles_per_col * pixels_per_tile_col,
        ) orelse return error.SdlTextureCreation;

        if (!c.SDL_SetTextureScaleMode(texture, c.SDL_SCALEMODE_NEAREST)) {
            return error.SdlSetTextureScaleMode;
        }

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

pub fn deinit(self: TilesViewer) void {
    if (!build_options.tiles_viewer) return;

    c.SDL_DestroyRenderer(self.renderer);
    c.SDL_DestroyWindow(self.window);
    c.SDL_Quit();
}

pub fn update(self: *const TilesViewer, bus: *const Bus) !void {
    if (!build_options.tiles_viewer) return;

    errdefer SdlContext.printError(@src().fn_name);

    const colors = [_]u32{ 0xFFFFFF, 0xAAAAAA, 0x555555, 0x000000 };

    if (!c.SDL_SetRenderTarget(self.renderer, self.texture)) {
        return error.SdlSetRenderTarget;
    }

    const bytes_per_tile = 16;
    const tile_count = 384;
    for (0..tile_count) |tile_id| {
        const id: u16 = @intCast(tile_id);
        const x = id % tiles_per_row;
        const y = id / tiles_per_row;

        var tile_offset: u16 = 0;
        while (tile_offset < bytes_per_tile) : (tile_offset += 2) {
            var lo = bus.peek(0x8000 + (id * bytes_per_tile) + tile_offset);
            var hi = bus.peek(0x8000 + (id * bytes_per_tile) + tile_offset + 1);

            lo = @bitReverse(lo);
            hi = @bitReverse(hi);

            inline for (0..8) |bit| {
                const l: u2 = @intCast(lo & 1);
                const h: u2 = @intCast(hi & 1);
                const color_index = h << 1 | l;
                const color = colors[color_index];

                lo >>= 1;
                hi >>= 1;

                const rect: c.SDL_FRect = .{
                    .w = 1,
                    .h = 1,
                    .x = @floatFromInt(x * pixels_per_tile_row + bit),
                    .y = @floatFromInt(y * pixels_per_tile_col + tile_offset / 2),
                };

                const r: u8 = @intCast((color & 0xFF0000) >> 16);
                const g: u8 = @intCast((color & 0xFF00) >> 8);
                const b: u8 = @intCast(color & 0xFF);
                if (!c.SDL_SetRenderDrawColor(self.renderer, r, g, b, c.SDL_ALPHA_OPAQUE)) {
                    return error.SdlRenderDrawColor;
                }

                if (!c.SDL_RenderFillRect(self.renderer, &rect)) {
                    return error.SdlRenderFillRect;
                }
            }
        }
    }

    if (!c.SDL_SetRenderTarget(self.renderer, null)) {
        return error.SdlSetRenderTarget;
    }

    if (!c.SDL_RenderTexture(self.renderer, self.texture, null, null)) {
        return error.SdlRenderTexture;
    }

    if (!c.SDL_RenderPresent(self.renderer)) {
        return error.SdlRenderPresent;
    }
}
