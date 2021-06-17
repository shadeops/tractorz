const std = @import("std");
const json = std.json;

const clibs = @import("clibs.zig");
const curl = clibs.curl;

var tractor_tsid: ?[36:0]u8 = null;

pub const Messages = struct {
    active: u32 = 0,
    blocked: u32 = 0,
    done: u32 = 0,
    err: u32 = 0,
};

pub fn postTractor(allocator: *std.mem.Allocator, post: []const u8) !std.ArrayList(u8) {
    var tractor_url = std.os.getenv("TRACTOR_URL") orelse "http://tractor/Tractor/monitor";

    // global curl init, or fail
    if (curl.curl_global_init(curl.CURL_GLOBAL_ALL) != .CURLE_OK)
        return error.CURLGlobalInitFailed;
    defer curl.curl_global_cleanup();

    // curl easy handle init, or fail
    const handle = curl.curl_easy_init() orelse return error.CURLHandleInitFailed;
    defer curl.curl_easy_cleanup(handle);

    var response_buffer = std.ArrayList(u8).init(allocator);

    // superfluous when using an arena allocator, but
    // important if the allocator implementation changes
    errdefer response_buffer.deinit();

    // setup curl options
    if (curl.curl_easy_setopt(handle, .CURLOPT_URL, tractor_url.ptr) != .CURLE_OK)
        return error.CouldNotSetURL;

    if (curl.curl_easy_setopt(handle, .CURLOPT_POSTFIELDS, post.ptr) != .CURLE_OK)
        return error.CouldNotSetPost;

    // set write function callbacks
    if (curl.curl_easy_setopt(handle, .CURLOPT_WRITEFUNCTION, writeToArrayListCallback) != .CURLE_OK)
        return error.CouldNotSetWriteCallback;
    if (curl.curl_easy_setopt(handle, .CURLOPT_WRITEDATA, &response_buffer) != .CURLE_OK)
        return error.CouldNotSetWriteCallback;

    // perform
    if (curl.curl_easy_perform(handle) != .CURLE_OK)
        return error.FailedToPerformRequest;

    return response_buffer;
}

pub fn tractorLogin(allocator: *std.mem.Allocator) !?[36:0]u8 {
    //std.debug.print("Logging into Tractor\n", .{});
    var buf: [64:0]u8 = undefined;
    var post = try std.fmt.bufPrintZ(buf[0..], "q=login&user={s}", .{std.os.getenv("USER")});
    var response = try postTractor(allocator, post);
    defer response.deinit();

    var p = json.Parser.init(allocator, false);
    defer p.deinit();

    var tree = try p.parse(response.items);
    defer tree.deinit();

    //std.debug.print("login\n{s}\n", .{response.items});
    tractor_tsid = [_:0]u8{0} ** 36;
    for (tree.root.Object.get("tsid").?.String) |v, i| {
        tractor_tsid.?[i] = v;
    }
    //std.debug.print("{s}\n", .{tractor_tsid});
    return tractor_tsid;
}

fn parseResponse(allocator: *std.mem.Allocator, response: std.ArrayList(u8)) !?Messages {
    var p = json.Parser.init(allocator, false);
    defer p.deinit();

    var tree = try p.parse(response.items);
    defer tree.deinit();

    var mbox = tree.root.Object.get("mbox") orelse return null;

    var msgs = Messages{};

    var active_commands: u32 = 0;
    for (mbox.Array.items) |item| {
        if (std.mem.eql(u8, item.Array.items[0].String, "c")) {
            if (std.mem.eql(u8, item.Array.items[4].String, "A")) msgs.active += 1;
            if (std.mem.eql(u8, item.Array.items[4].String, "B")) msgs.blocked += 1;
            if (std.mem.eql(u8, item.Array.items[4].String, "D")) msgs.done += 1;
            if (std.mem.eql(u8, item.Array.items[4].String, "E")) msgs.err += 1;
        }
    }

    //try std.testing.expectEqualStrings("c", tree.root.Object.get("mbox").?.Array.items[0].Array.items[0].String);
    return msgs;
}

pub fn queryTractor(allocator: *std.mem.Allocator) !?Messages {
    var buf: [64:0]u8 = undefined;
    var post = try std.fmt.bufPrintZ(buf[0..], "q=subscribe&jids=0&tsid={s}", .{tractor_tsid.?});
    var response = try postTractor(allocator, post);
    defer response.deinit();

    return parseResponse(allocator, response);
}

fn writeToArrayListCallback(data: *c_void, size: c_uint, nmemb: c_uint, user_data: *c_void) callconv(.C) c_uint {
    var buffer = @intToPtr(*std.ArrayList(u8), @ptrToInt(user_data));
    var typed_data = @intToPtr([*]u8, @ptrToInt(data));
    buffer.appendSlice(typed_data[0 .. nmemb * size]) catch return 0;
    return nmemb * size;
}

pub const ThreadContext = struct {
    allocator: *std.mem.Allocator,
    msgs: Messages,
    is_ready: bool,
};

fn appendNum(ctx: *ThreadContext) !void {
    var prng = std.rand.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.os.getrandom(std.mem.asBytes(&seed));
        break :blk 42;
    });
    const rand = &prng.random;

    while (true) {
        //var val = rand.intRangeAtMost(u32, 1, 100);
        defer std.time.sleep(1 * std.time.ns_per_s);

        var val = (try queryTractor(ctx.allocator)) orelse continue;

        // barrier until is_ready is true
        while (@atomicLoad(bool, &ctx.is_ready, .SeqCst)) {
            // spinLoopHint() ?
        }

        @atomicStore(u32, &ctx.msgs.active, val.active, .SeqCst);
        @atomicStore(u32, &ctx.msgs.blocked, val.blocked, .SeqCst);
        @atomicStore(u32, &ctx.msgs.err, val.err, .SeqCst);
        @atomicStore(u32, &ctx.msgs.done, val.done, .SeqCst);
        @atomicStore(bool, &ctx.is_ready, true, .SeqCst);
    }
}

pub fn startListener(ctx: *ThreadContext) !*std.Thread {
    var thread = try std.Thread.spawn(appendNum, ctx);
    return thread;
}

test "bit compare" {
    var a: u32 = 1;
    var b: u32 = 2;
    try std.testing.expect((a | b) == 3);
}
