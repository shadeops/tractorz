const std = @import("std");

fn buildRaylib(b: *std.build.Builder) void {
    const cmake = b.addSystemCommand(&[_][]const u8{
        "cmake",
        "-B",
        "ext/raylib/build",
        "-S",
        "ext/raylib",
        "-DCMAKE_BUILD_TYPE=Release",
        "-DOpenGL_GL_PREFERENCE=GLVND",
        "-DBUILD_EXAMPLES=OFF",
    });
    cmake.step.make() catch {};

    const cmake_build = b.addSystemCommand(&[_][]const u8{
        "cmake",
        "--build",
        "ext/raylib/build",
        "--",
        "-j",
        "16",
    });
    cmake_build.step.make() catch {};
}

fn buildChipmunk(b: *std.build.Builder) void {
    const cmake = b.addSystemCommand(&[_][]const u8{
        "cmake",
        "-B",
        "ext/Chipmunk2D/build",
        "-S",
        "ext/Chipmunk2D",
        "-DCMAKE_BUILD_TYPE=Release",
        "-DBUILD_DEMOS=OFF",
        "-DBUILD_SHARED=OFF",
    });
    cmake.step.make() catch {};

    const cmake_build = b.addSystemCommand(&[_][]const u8{
        "cmake",
        "--build",
        "ext/Chipmunk2D/build",
        "--",
        "-j",
        "16",
    });
    cmake_build.step.make() catch {};
}

fn buildCurl(b: *std.build.Builder) void {
    const cmake = b.addSystemCommand(&[_][]const u8{
        "cmake",
        "-B",
        "ext/curl/build",
        "-S",
        "ext/curl",
        "-DCMAKE_BUILD_TYPE=Release",
        "-DHTTP_ONLY=ON",
        "-DBUILD_CURL_EXE=OFF",
        "-DBUILD_SHARED_LIBS=OFF",
        "-DCMAKE_USE_OPENSSL=OFF",
        "-DCMAKE_USE_LIBSSH2=OFF",
        "-DCMAKE_USE_LIBSSH=OFF",
        "-DCURL_ZLIB=OFF",
    });
    cmake.step.make() catch {};

    const cmake_build = b.addSystemCommand(&[_][]const u8{
        "cmake",
        "--build",
        "ext/curl/build",
        "--",
        "-j",
        "16",
    });
    cmake_build.step.make() catch {};
}

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    buildRaylib(b);
    buildChipmunk(b);
    buildCurl(b);

    const exe = b.addExecutable("tractorz", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.addIncludeDir("ext/Chipmunk2D/include");
    exe.addIncludeDir("ext/curl/include");
    exe.addLibPath("ext/Chipmunk2D/build/src");
    exe.addLibPath("ext/raylib/build/raylib");
    exe.addLibPath("ext/curl/build/lib");
    exe.linkSystemLibraryName("chipmunk");
    exe.linkSystemLibraryName("raylib");
    exe.linkSystemLibraryName("curl");
    exe.linkLibC();
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run Tests");
    const tests = b.addTest("src/tractor.zig");
    tests.setBuildMode(mode);
    tests.addIncludeDir("ext/Chipmunk2D/include");
    tests.addIncludeDir("ext/curl/include");
    tests.addLibPath("ext/Chipmunk2D/build/src");
    tests.addLibPath("ext/raylib/build/raylib");
    tests.addLibPath("ext/curl/build/lib");
    tests.linkSystemLibraryName("chipmunk");
    tests.linkSystemLibraryName("raylib");
    tests.linkSystemLibraryName("curl");
    tests.linkLibC();
    test_step.dependOn(&tests.step);
}
