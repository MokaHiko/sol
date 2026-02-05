        // TODO: Make lazy integration
        // Wren integration
        shape_example.module.addIncludePath(b.path("src/wren/src"));
        shape_example.module.addIncludePath(b.path("src/wren/src/vm"));
        shape_example.module.addIncludePath(b.path("src/wren/src/include"));
        shape_example.module.addIncludePath(b.path("src/wren/src/optional"));
        shape_example.module.addCSourceFiles(.{
            .root = b.path("src/wren/src"),
            .files = &[_][]const u8{
                "optional/wren_opt_meta.c",
                "optional/wren_opt_random.c",

                "vm/wren_compiler.c",
                "vm/wren_core.c",
                "vm/wren_debug.c",
                "vm/wren_primitive.c",
                "vm/wren_utils.c",
                "vm/wren_value.c",
                "vm/wren_vm.c",
            },
        });

// Example
const c = @cImport({
    @cInclude("wren.h");
});

export fn writeFn(vm: ?*c.struct_WrenVM, msg: [*c]const u8) void {
    sol.log.err("{s}", .{msg});
    _ = vm;
}

var config: c.WrenConfiguration = .{};
c.wrenInitConfiguration(&config);
config.writeFn = &writeFn;
// config.errorFn = &errorFn;

const vm = c.wrenNewVM(&config);

const module = "main";
// const script = "System.print(\"I am running in a VM!\")";
const script = "System.print(10 + 10)";

const result = c.wrenInterpret(vm, module, script);
sol.log.err("WREN SCRIPT RESULT {d}", .{result});

switch (result) {
    c.WREN_RESULT_COMPILE_ERROR => sol.log.trace("Compile Error!\n", .{}),
    c.WREN_RESULT_RUNTIME_ERROR => sol.log.trace("Runtime Error!\n", .{}),
    c.WREN_RESULT_SUCCESS => sol.log.trace("Success!\n", .{}),

    else => {},
}

c.wrenFreeVM(vm);
