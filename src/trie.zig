const std = @import("std");

/// Entry in the param list
pub const Entry = struct {
    key: []const u8,
    value: []const u8,
};

/// Small radix trie used for routing
/// This radix trie works different from regular radix tries
/// as each node is made up from a piece rather than a singular character
pub fn Trie(comptime T: type) type {
    return struct {
        const Self = @This();

        const max_params: usize = 10;

        /// Node within the Trie, contains links to child nodes
        /// also contains a path piece and whether it's a wildcard
        const Node = struct {
            childs: []*Node,
            label: enum { none, all, param },
            path: []const u8,
            data: ?T,
        };

        /// Root node, which is '/'
        root: Node = Node{
            .childs = &[_]*Node{},
            .label = .none,
            .path = "/",
            .data = null,
        },
        size: usize = 0,

        const ResultTag = enum { none, static, with_params };

        /// Result is an union which is returned when trying to find
        /// from a path
        const Result = union(ResultTag) {
            none: void,
            static: T,
            with_params: struct {
                data: T,
                params: [max_params]Entry,
                param_count: usize,
            },
        };

        /// Inserts new nodes based on the given path
        /// `path`[0] must be '/'
        pub fn insert(self: *Self, comptime path: []const u8, comptime data: T) void {
            if (path.len == 1 and path[0] == '/') {
                self.root.data = data;
                return;
            }

            if (path[0] != '/') @compileError("Path must start with /");
            if (std.mem.count(u8, path, ":") > max_params) @compileError("This path contains too many parameters");

            var it = std.mem.split(path[1..], "/");
            var current = &self.root;
            loop: while (it.next()) |component| {
                for (current.childs) |child| {
                    if (std.mem.eql(u8, child.path, component)) {
                        current = child;
                        continue :loop;
                    }
                }

                self.size += 1;
                var new_node = Node{
                    .path = component,
                    .childs = &[_]*Node{},
                    .label = .none,
                    .data = null,
                };

                if (component.len > 0) {
                    new_node.label = switch (component[0]) {
                        ':' => .param,
                        '*' => .all,
                        else => .none,
                    };
                }

                var childs: [current.childs.len + 1]*Node = undefined;
                std.mem.copy(*Node, &childs, current.childs ++ [_]*Node{&new_node});
                current.childs = &childs;
                current = &new_node;
            }
            current.data = data;
        }

        /// Retrieves T based on the given path
        /// when a wildcard such as * is found, it will return T
        /// If a colon is found, it will add the path piece onto the param list
        pub fn get(self: *Self, path: []const u8) Result {
            if (path.len == 1) {
                return .{ .static = self.root.data.? };
            }

            var params: [max_params]Entry = undefined;
            var param_count: usize = 0;
            var current = &self.root;
            var it = std.mem.split(std.mem.trimRight(u8, path[1..], "/ "), "/");

            loop: while (it.next()) |component| {
                for (current.childs) |child| {
                    if (std.mem.eql(u8, component, child.path) or child.label == .param or child.label == .all) {
                        if (child.label == .all) {
                            if (child.data == null) return .none;
                            if (param_count == 0) return .{ .static = child.data.? };

                            var result = Result{
                                .with_params = .{
                                    .data = current.data.?,
                                    .params = undefined,
                                    .param_count = param_count,
                                },
                            };

                            std.mem.copy(Entry, &result.with_params.params, &params);
                            return result;
                        }
                        if (child.label == .param) {
                            params[param_count] = .{ .key = child.path[1..], .value = component };
                            param_count += 1;
                        }
                        current = child;
                        continue :loop;
                    }
                }
                return .none;
            }

            if (current.data == null) return .none;
            if (param_count == 0) return .{ .static = current.data.? };

            var result = Result{
                .with_params = .{
                    .data = current.data.?,
                    .params = undefined,
                    .param_count = param_count,
                },
            };

            std.mem.copy(Entry, &result.with_params.params, &params);
            return result;
        }
    };
}

test "Insert and retrieve" {
    comptime var trie = Trie(u32){};
    comptime trie.insert("/posts/:id", 1);
    comptime trie.insert("/messages/*", 2);
    comptime trie.insert("/topics/:id/messages/:msg", 3);

    const res = trie.get("/posts/5");
    const res2 = trie.get("/messages/bla");
    const res3 = trie.get("/topics/25/messages/20");
    const res4 = trie.get("/foo");

    std.testing.expectEqual(@as(u32, 1), res.with_params.data);
    std.testing.expectEqual(@as(u32, 2), res2.static);
    std.testing.expectEqual(@as(u32, 3), res3.with_params.data);
    std.testing.expect(res4 == .none);

    std.testing.expectEqualStrings("5", res.with_params.params[0].value);
    std.testing.expectEqualStrings("25", res3.with_params.params[0].value);
    std.testing.expectEqualStrings("20", res3.with_params.params[1].value);
}

test "Insert and retrieve paths with same prefix" {
    comptime var trie = Trie(u32){};
    comptime trie.insert("/api", 1);
    comptime trie.insert("/api/users", 2);
    comptime trie.insert("/api/events", 3);
    comptime trie.insert("/api/events/:id", 4);

    const res = trie.get("/api");
    const res2 = trie.get("/api/users");
    const res3 = trie.get("/api/events");
    const res4 = trie.get("/api/events/1337");
    const res5 = trie.get("/foo");
    const res6 = trie.get("/api/api/events");
    const res7 = trie.get("/api/events/");

    std.testing.expectEqual(@as(u32, 1), res.static);
    std.testing.expectEqual(@as(u32, 2), res2.static);
    std.testing.expectEqual(@as(u32, 3), res3.static);
    std.testing.expectEqual(@as(u32, 4), res4.with_params.data);
    std.testing.expect(res5 == .none);
    std.testing.expect(res6 == .none);
    std.testing.expectEqual(@as(u32, 3), res7.static);

    std.testing.expectEqualStrings("1337", res4.with_params.params[0].value);
}

test "Paths ending with component separator are treated the same" {
    comptime var trie = Trie(u32){};

    // One of these two routes should be ignored, and for now it happens to be the one
    // added second.
    comptime trie.insert("/api", 1);
    comptime trie.insert("/api/", 2);
    
    comptime trie.insert("/api/:id", 3);

    const res = trie.get("/api");
    const res2 = trie.get("/api/");
    const res3 = trie.get("/api/23154");
    const res4 = trie.get("/ap");

    // Both should resolve to the same route, in this case the first one added
    std.testing.expectEqual(@as(u32, 1), res.static);
    std.testing.expectEqual(@as(u32, 1), res2.static);
    std.testing.expectEqual(@as(u32, 3), res3.with_params.data);
    std.testing.expect(res4 == .none);

    std.testing.expectEqualStrings("23154", res3.with_params.params[0].value);
}
