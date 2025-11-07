const std = @import("std");

fn libPath(release_mode: bool) []const u8 {
    return if (release_mode) "vendor/wgpu_native/target/release/" else "vendor/wgpu_native/target/debug/";
}

fn dllPath(release_mode: bool) []const u8 {
    return if (release_mode) "vendor/wgpu_native/target/release/wgpu_native.dll" else "vendor/wgpu_native/target/debug/wgpu_native.dll";
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const release_mode = b.option(bool, "release", "Build in release mode") orelse false;

    const mod = b.addModule("zpu", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .link_libc = true,
        .link_libcpp = true,
    });

    mod.addIncludePath(b.path("vendor/wgpu_native/ffi/"));
    mod.addIncludePath(b.path("vendor/wgpu_native/ffi/webgpu-headers/"));
    mod.addLibraryPath(b.path(libPath(release_mode)));
    mod.linkSystemLibrary("wgpu_native", .{});

    switch (target.result.os.tag) {
        .windows => b.installFile(dllPath(release_mode), "bin/wgpu_native.dll"),
        else => @panic("Unsupported OS"),
    }

    const exe = b.addExecutable(.{
        .name = "zpu",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zpu", .module = mod },
            },
        }),
    });

    b.installArtifact(exe);

    const wgpu_step = b.step("wgpu", "Build wgpu_native");
    const rust_cmd = b.addSystemCommand(if (release_mode) &.{ "cargo", "build", "--release" } else &.{ "cargo", "build" });
    rust_cmd.setCwd(b.path("vendor/wgpu_native/"));
    wgpu_step.dependOn(&rust_cmd.step);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
