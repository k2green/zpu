const std = @import("std");
const c = @cImport({
    @cInclude("webgpu/webgpu.h");
});

pub const Error = error{
    FailedToCreateInstance,
};

pub const Instance = struct {
    handle: c.WGPUInstance,

    pub fn create(descriptor: c.WGPUInstanceDescriptor) Error!Instance {
        const handle = c.wgpuCreateInstance(&descriptor) orelse return Error.FailedToCreateInstance;
        return .{ .handle = handle };
    }

    pub fn release(self: *Instance) void {
        if (self.handle) |handle| {
            c.wgpuInstanceRelease(handle);
            self.handle = null;
        }
    }
};
