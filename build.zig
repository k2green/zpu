const std = @import("std");

fn getRustTarget(b: *std.Build, target: std.Build.ResolvedTarget) ![]const u8 {
    const arch = @tagName(target.result.cpu.arch);
    const os = @tagName(target.result.os.tag);
    const abi = @tagName(target.result.abi);
    const vendor = switch (target.result.os.tag) {
        .macos => "apple",
        .windows => "pc",
        else => "unknown",
    };

    return try std.fmt.allocPrint(b.allocator, "{s}-{s}-{s}-{s}", .{ arch, vendor, os, abi });
}

fn printSlice(slice: []const []const u8) void {
    for (slice) |str|
        std.debug.print("{s} ", .{str});

    std.debug.print("\n", .{});
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const rust_target = try getRustTarget(b, target);
    defer b.allocator.free(rust_target);

    // Create the arguments for the rust commands
    var rust_target_cmd_args = std.ArrayList([]const u8).empty;
    defer rust_target_cmd_args.deinit(b.allocator);
    try rust_target_cmd_args.appendSlice(b.allocator, &.{ "rustup", "target", "add" });
    try rust_target_cmd_args.append(b.allocator, rust_target);

    var wgpu_cmd_args = std.ArrayList([]const u8).empty;
    defer wgpu_cmd_args.deinit(b.allocator);
    try wgpu_cmd_args.appendSlice(b.allocator, &.{ "cargo", "build", "--target", rust_target });

    if (optimize != .Debug)
        try wgpu_cmd_args.append(b.allocator, "--release");

    // First run the command to add the required target, then build wgpu_native with that target
    const rust_target_cmd = b.addSystemCommand(rust_target_cmd_args.items);
    const wgpu_dep = b.dependency("wgpu_native", .{});
    const wgpu_build_cmd = b.addSystemCommand(wgpu_cmd_args.items);
    wgpu_build_cmd.setCwd(wgpu_dep.path("."));

    wgpu_build_cmd.step.dependOn(&rust_target_cmd.step);
    b.getInstallStep().dependOn(&wgpu_build_cmd.step);

    // Get the output path for the library and the corresponding lib file
    const output_path = try std.fmt.allocPrint(b.allocator, "target/{s}/{s}", .{
        rust_target,
        if (optimize == .Debug) "debug" else "release",
    });

    if (target.result.os.tag == .windows or target.result.os.tag == .linux) {
        const lib_format = switch (target.result.os.tag) {
            .windows => "dll",
            .linux => "so",
            else => unreachable,
        };

        const lib_path = try std.fmt.allocPrint(b.allocator, "{s}/wgpu_native.{s}", .{ output_path, lib_format });
        const install_path = try std.fmt.allocPrint(b.allocator, "bin/wgpu_native.{s}", .{lib_format});
        const install_step = b.addInstallFile(wgpu_dep.path(lib_path), install_path);
        install_step.step.dependOn(&wgpu_build_cmd.step);
        b.getInstallStep().dependOn(&install_step.step);
    }

    const mod = b.addModule("zpu", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .link_libc = true,
        .link_libcpp = true,
    });

    mod.addIncludePath(wgpu_dep.path("ffi/"));
    mod.addIncludePath(wgpu_dep.path("ffi/webgpu-headers"));
    mod.addLibraryPath(wgpu_dep.path(output_path));
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
