const std = @import("std");

fn getWgpuDirName(b: *std.Build, target: std.Build.ResolvedTarget, release_mode: bool) ![]const u8 {
    const os: []const u8 = switch (target.result.os.tag) {
        .windows => "windows",
        else => @panic("Unsupported OS"),
    };

    const arch: []const u8 = switch (target.result.cpu.arch) {
        .x86_64 => "x86_64",
        else => @panic("Unsupported arch"),
    };

    const version: []const u8 = if (release_mode) "release" else "debug";
    return try std.fmt.allocPrint(b.allocator, "{s}-{s}-{s}", .{ os, arch, version });
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const release_mode = b.option(bool, "release", "Should the project be build in release mode") orelse false;
    const wgpu_folder = try getWgpuDirName(b, target, release_mode);
    const wgpu_path = b.pathJoin(&.{ "vendor", "webgpu", wgpu_folder });
    const wgpu_install_file = switch (target.result.os.tag) {
        .windows => b.pathJoin(&.{ wgpu_path, "wgpu_native.dll" }),
        else => @panic("Unsupported OS"),
    };

    const mod = b.addModule("zpu", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .link_libc = true,
        .link_libcpp = true,
    });

    mod.addIncludePath(b.path("vendor/webgpu/include"));
    mod.addLibraryPath(b.path(wgpu_path));
    mod.linkSystemLibrary("wgpu_native", .{});
    b.installFile(wgpu_install_file, switch (target.result.os.tag) {
        .windows => "bin/wgpu_native.dll",
        else => @panic("Unsupported OS"),
    });

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
