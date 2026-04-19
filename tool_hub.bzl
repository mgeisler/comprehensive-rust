def _tool_hub_impl(ctx):
    outputs = []

    for target, name in ctx.attr.tools.items():
        tool = target[DefaultInfo].files_to_run.executable
        output = ctx.actions.declare_file("%s/%s" % (ctx.label.name, name))
        ctx.actions.symlink(output = output, target_file = tool, is_executable = True)
        outputs.append(output)

    return [DefaultInfo(files = depset(outputs))]

tool_hub = rule(
    implementation = _tool_hub_impl,
    attrs = {
        "tools": attr.label_keyed_string_dict(
            doc = "Map of tool targets to their desired name.",
            allow_files = True,
            cfg = "exec",
        ),
    },
)
