const std = @import("std");
const c = @import("c.zig");

const SdlContext = @This();

renderer: *c.SDL_Renderer,
texture: *c.SDL_Texture,

pub fn renderFrame(self: *const SdlContext, frame: []const u8) !void {
    {
        var pixel_raw_ptr: ?*anyopaque = null;
        var pitch: c_int = 0;
        if (!c.SDL_LockTexture(self.texture, null, &pixel_raw_ptr, &pitch)) {
            printError(@src().fn_name);
            return error.SdlTextureLock;
        }
        defer c.SDL_UnlockTexture(self.texture);

        const pixel_ptr: [*]u8 = @ptrCast(pixel_raw_ptr);
        const pixels = pixel_ptr[0..frame.len];
        @memcpy(pixels, frame);
    }

    if (!c.SDL_RenderTexture(self.renderer, self.texture, null, null)) {
        printError(@src().fn_name);
        return error.SdlRenderTexture;
    }

    if (!c.SDL_RenderPresent(self.renderer)) {
        printError(@src().fn_name);
        return error.SdlRenderPresent;
    }
}

fn printError(comptime caller: []const u8) void {
    std.log.err("fn {s}: {s}", .{ caller, c.SDL_GetError() });
}
