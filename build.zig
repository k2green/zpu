const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const wgpu_dep = b.dependency("wgpu_native", .{});
    const wgpu_build_cmd = b.addSystemCommand(&.{ "cargo", "build" });
    wgpu_build_cmd.setCwd(wgpu_dep.path("."));
    b.getInstallStep().dependOn(&wgpu_build_cmd.step);

    const install_step = b.addInstallFile(wgpu_dep.path("target/debug/wgpu_native.dll"), "bin/wgpu_native.dll");
    b.getInstallStep().dependOn(&install_step.step);

    const mod = b.addModule("zpu", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .link_libc = true,
        .link_libcpp = true,
    });

    mod.addIncludePath(wgpu_dep.path("ffi/"));
    mod.addIncludePath(wgpu_dep.path("ffi/webgpu-headers"));
    mod.addLibraryPath(wgpu_dep.path("target/debug"));
    mod.linkSystemLibrary("wgpu_native", .{});

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
