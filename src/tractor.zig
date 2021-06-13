const std = @import("std");
const json = std.json;

const clibs = @import("clibs.zig");
const curl = clibs.curl;
    
const tractor_url = "http://conduit.local/Tractor/monitor";

pub fn fetchURL() !void  {

    var arena_state = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena_state.deinit();
    var allocator = &arena_state.allocator;

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
    defer response_buffer.deinit();

    // setup curl options
    if (curl.curl_easy_setopt(handle, .CURLOPT_URL, tractor_url) != .CURLE_OK)
        return error.CouldNotSetURL;

    const post = "q=subscribe&jids=0&tsid=60c30eb8-4601a8c0-00003";
    if (curl.curl_easy_setopt(handle, .CURLOPT_POSTFIELDS, post) != .CURLE_OK)
        return error.CouldNotSetPost;

    // set write function callbacks
    if (curl.curl_easy_setopt(handle, .CURLOPT_WRITEFUNCTION, writeToArrayListCallback) != .CURLE_OK)
        return error.CouldNotSetWriteCallback;
    if (curl.curl_easy_setopt(handle, .CURLOPT_WRITEDATA, &response_buffer) != .CURLE_OK)
        return error.CouldNotSetWriteCallback;

    // perform
    if (curl.curl_easy_perform(handle) != .CURLE_OK)
        return error.FailedToPerformRequest;

    std.log.info("Got response of {d} bytes", .{response_buffer.items.len});
    std.debug.print("{s}\n", .{response_buffer.items});
}

fn writeToArrayListCallback(data: *c_void, size: c_uint, nmemb: c_uint, user_data: *c_void) callconv(.C) c_uint {
    
    var buffer = @intToPtr(*std.ArrayList(u8), @ptrToInt(user_data));
    var typed_data = @intToPtr([*]u8, @ptrToInt(data));
    buffer.appendSlice(typed_data[0 .. nmemb * size]) catch return 0;
    return nmemb * size;
}

const ThreadContext = struct {
    count: u32,
    is_ready: bool,
};

fn appendNum(ctx: * ThreadContext) !void {
    var prng = std.rand.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.os.getrandom(std.mem.asBytes(&seed));
        break :blk 42;
    });
    const rand = &prng.random;
   
    while(true) {
        std.time.sleep(1 * std.time.ns_per_s);
        var rand_val = rand.intRangeAtMost(u32, 1, 100);
       
        // barrier until is_ready is true
        while (@atomicLoad(bool, &ctx.is_ready, .SeqCst) ) {
            // spinLoopHint() ?
        }

        @atomicStore(u32, &ctx.count, rand_val, .SeqCst);
        @atomicStore(bool, &ctx.is_ready, true, .SeqCst);
    }
}

pub fn startListener(ctx: * ThreadContext) !*std.Thread {
    var thread = try std.Thread.spawn(appendNum, ctx);
    return thread;
}

pub fn runnin() !void {

    var ctx: ThreadContext = .{
        .count = 0,
        .is_ready = false,
    };
    var thread = try startListener(&ctx);
    //defer thread.wait();

    while(true) {
        if (@atomicLoad(bool, &ctx.is_ready, .SeqCst)) {
            var count = @atomicRmw(u32, &ctx.count, .Xchg, 0, .SeqCst);
            @atomicStore(bool, &ctx.is_ready, false, .SeqCst);
            std.debug.print("{}\n", .{count});
        } else {
            std.time.sleep(16 * std.time.ms_per_s);
        }
    }
}

test "json parse" {

    var p = json.Parser.init(std.testing.allocator, false);
    defer p.deinit();

    const s = 
        \\{
        \\"mbox": [
        \\  ["c", 22,1,1,"A",264,"conduit/192.168.1.54",9005,1,1,0,0, "wolfwood", 1623522582.381],
        \\  ["c", 22,1,1,"D",9,"conduit/192.168.1.54",9005,1,0,1,0, "wolfwood", 1623522583.224],
        \\  ["c", 22,0,0,"D",0,".",0,1,0,1,0, "wolfwood", 1623522583.231],
        \\  ["j", "Done",22,"wolfwood", 1623522583.235]
        \\],
        \\"trigger": "updates"
        \\}
    ;
    
    var tree = try p.parse(s);
    defer tree.deinit();

    try std.testing.expectEqualStrings("c", tree.root.Object.get("mbox").?.Array.items[0].Array.items[0].String);
}

