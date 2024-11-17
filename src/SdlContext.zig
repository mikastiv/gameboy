const std = @import("std");
const c = @import("c.zig");
const build_options = @import("build_options");

const SdlContext = @This();

const DebugWindow = if (build_options.tiles_viewer) *c.SDL_Window else void;
const DebugRenderer = if (build_options.tiles_viewer) *c.SDL_Renderer else void;
const DebugTexture = if (build_options.tiles_viewer) *c.SDL_Texture else void;

window: *c.SDL_Window,
renderer: *c.SDL_Renderer,
texture: *c.SDL_Texture,
debug_window: DebugWindow,
debug_renderer: DebugRenderer,
debug_texture: DebugTexture,

pub fn init(
    window_title: [:0]const u8,
    window_width: comptime_int,
    window_height: comptime_int,
    texture_width: comptime_int,
    texture_height: comptime_int,
) !SdlContext {
    errdefer printError(@src().fn_name);

    if (!c.SDL_Init(c.SDL_INIT_VIDEO))
        return error.SdlInit;
    errdefer c.SDL_Quit();

    const window = c.SDL_CreateWindow(window_title, window_width, window_height, 0) orelse
        return error.SdlWindowCreation;
    errdefer c.SDL_DestroyWindow(window);

    const renderer = c.SDL_CreateRenderer(window, null) orelse
        return error.SdlRendererCreation;
    errdefer c.SDL_DestroyRenderer(renderer);

    const texture = c.SDL_CreateTexture(
        renderer,
        c.SDL_PIXELFORMAT_RGBA32,
        c.SDL_TEXTUREACCESS_STREAMING,
        texture_width,
        texture_height,
    ) orelse return error.SdlTextureCreation;

    var debug_window: DebugWindow = undefined;
    var debug_renderer: DebugRenderer = undefined;
    var debug_texture: DebugTexture = undefined;
    if (build_options.tiles_viewer) {
        debug_window = c.SDL_CreateWindow("Tiles Viewer", 800, 600, 0) orelse
            return error.SdlWindowCreation;

        debug_renderer = c.SDL_CreateRenderer(debug_window, null) orelse
            return error.SdlRendererCreation;

        const tiles_per_row = 16;
        const tiles_per_col = 24;
        const pixels_per_tile_row = 8;
        const pixels_per_tile_col = 8;

        debug_texture = c.SDL_CreateTexture(
            debug_renderer,
            c.SDL_PIXELFORMAT_RGBA32,
            c.SDL_TEXTUREACCESS_STREAMING,
            tiles_per_row * pixels_per_tile_row,
            tiles_per_col * pixels_per_tile_col,
        ) orelse return error.SdlTextureCreation;

        var x: i32 = undefined;
        var y: i32 = undefined;
        _ = c.SDL_GetWindowPosition(window, &x, &y);
        _ = c.SDL_SetWindowPosition(debug_window, x + @as(i32, @intCast(window_width)), y);
    }

    return .{
        .window = window,
        .renderer = renderer,
        .texture = texture,

        .debug_window = debug_window,
        .debug_renderer = debug_renderer,
        .debug_texture = debug_texture,
    };
}

pub fn deinit(self: SdlContext) void {
    c.SDL_DestroyRenderer(self.renderer);
    c.SDL_DestroyWindow(self.window);
    c.SDL_Quit();
}

pub fn renderFrame(self: *const SdlContext, frame: []const u8) !void {
    errdefer printError(@src().fn_name);

    {
        var pixel_raw_ptr: ?*anyopaque = null;
        var pitch: c_int = 0;
        if (!c.SDL_LockTexture(self.texture, null, &pixel_raw_ptr, &pitch)) {
            return error.SdlTextureLock;
        }
        defer c.SDL_UnlockTexture(self.texture);

        const pixel_ptr: [*]u8 = @ptrCast(pixel_raw_ptr);
        const pixels = pixel_ptr[0..frame.len];
        @memcpy(pixels, frame);
    }

    if (!c.SDL_RenderTexture(self.renderer, self.texture, null, null)) {
        return error.SdlRenderTexture;
    }

    if (!c.SDL_RenderPresent(self.renderer)) {
        return error.SdlRenderPresent;
    }
}

fn printError(comptime caller: []const u8) void {
    std.log.err("fn {s}: {s}", .{ caller, c.SDL_GetError() });
}
