"""
Back-dating logic for Comprehensive Rust.

Translations (stored as `.po` files) are not in sync with the main
English content. To ensure the translations apply correctly, we build
the translations from the date when the translation was last updated,
as denoted by the `POT-Creation-Date` header.

We do this by creating isolated, read-only external repositories for
each required point in time. This ensures the local workspace remains
clean and the builds are hermetic.
"""

load("@toml.bzl", "toml")

BACKDATED_PATHS = ["src/", "third_party/", "book.toml"]

def _lang_repo_impl(repository_ctx):
    """
    A Repository Rule that creates a complete, backdated workspace for a language.
    It extracts the sources from git and modifies the book.toml in place.
    """
    commit = repository_ctx.attr.commit
    lang = repository_ctx.attr.lang

    # 1. Extract the git archive.
    archive = repository_ctx.path("archive.tar.gz")
    result = repository_ctx.execute(
        ["git", "-C", repository_ctx.workspace_root, "archive"] +
        ["--output", archive] + [commit] + BACKDATED_PATHS,
    )
    if result.return_code != 0:
        fail("Failed to run git archive for commit {}: {}".format(commit, result.stderr))

    repository_ctx.extract(archive)
    repository_ctx.delete(archive)
    repository_ctx.delete("third_party/cxx/blobstore/BUILD")

    # Symlink the current theme from the workspace.
    theme_src = repository_ctx.path(repository_ctx.workspace_root).get_child("theme")
    repository_ctx.symlink(theme_src, "theme")

    # 2. Modify the book.toml file.
    if lang != "en":
        book_path = repository_ctx.path("book.toml")
        book = toml.decode(repository_ctx.read(book_path))

        book["book"]["language"] = lang
        book["output"]["html"]["site-url"] = "/comprehensive-rust/{}/".format(lang)
        book["output"]["html"].pop("redirect", None)

        # Disable pandoc as it's not available in the hermetic Bazel build.
        book.setdefault("output", {}) \
            .setdefault("pandoc", {}) \
            .update(disabled = True, optional = True)

        repository_ctx.file("book.toml", toml.encode(book), executable = False)

    # 3. Generate a BUILD.bazel that provides an aggregate interface.
    repository_ctx.file("BUILD.bazel", """
filegroup(
    name = "srcs",
    srcs = glob(["src/**", "third_party/**", "theme/**"]),
    visibility = ["//visibility:public"],
)

exports_files(
    ["book.toml"],
    visibility = ["//visibility:public"],
)
""", executable = False)

lang_repo = repository_rule(
    implementation = _lang_repo_impl,
    attrs = {
        "commit": attr.string(mandatory = True, doc = "The Git commit to archive."),
        "lang": attr.string(mandatory = True, doc = "The language for the book."),
    },
    doc = "Creates a backdated repository for a specific language.",
)

def _hub_repo_impl(repository_ctx):
    """Creates a hub repository that provides aliases for all
    languages.
    """
    content = ""
    for name, actual in repository_ctx.attr.targets.items():
        content += """alias(
    name = "{}",
    actual = "{}",
    visibility = ["//visibility:public"],
)\n\n""".format(name, actual)
    repository_ctx.file("BUILD.bazel", content, executable = False)

hub_repo = repository_rule(
    implementation = _hub_repo_impl,
    attrs = {
        "targets": attr.string_dict(mandatory = True, doc = "Map of alias name to actual target."),
    },
)

def _extract_date(module_ctx, po_path):
    """
    Parses the POT-Creation-Date from a .po file header.
    """

    # Read the first 10KB of the file to find the header.
    header_chunk = module_ctx.read(po_path)[:10000]
    for line in header_chunk.splitlines():
        if "POT-Creation-Date:" in line:
            parts = line.strip('"\\n').split(": ", 1)
            if len(parts) < 2:
                continue
            return parts[1]
    return "now"

def _lang_repo_name(lang):
    """Generates a Bazel-safe repository name for a language code."""
    return "lang_" + lang.replace("-", "_")

def _backdated_sources_extension_impl(module_ctx):
    """
    The Module Extension that orchestrates the creation of all back-dated repositories.
    It scans the project's .po files, determines the correct git commit for each,
    and instantiates the necessary repositories.
    """

    # English is always at HEAD.
    lang_configs = [struct(name = "en", commit = "HEAD")]

    for mod in module_ctx.modules:
        for tag in mod.tags.language:
            po = module_ctx.path(tag.po)
            name = po.basename.removesuffix(".po")
            date = _extract_date(module_ctx, po)

            # Resolve the POT-Creation-Date to the nearest preceding Git commit.
            rev_list = module_ctx.execute(
                ["git", "-C", po.dirname, "rev-list", "-n", "1", "--before", date, "HEAD"],
            )
            if rev_list.return_code != 0:
                fail("Failed to get commit for {} at {}: {}".format(po, date, rev_list.stderr))

            commit = rev_list.stdout.strip()
            if not commit:
                print("Warning: could not parse commit for {}, defaulting to HEAD".format(date))
                rev_parse = module_ctx.execute(
                    ["git", "-C", po.dirname, "rev-parse", "HEAD"],
                )
                commit = rev_parse.stdout.strip()

            lang_configs.append(struct(
                name = name,
                commit = commit,
            ))

    # Instantiate a complete repository for each language.
    for cfg in lang_configs:
        lang_repo(
            name = _lang_repo_name(cfg.name),
            commit = cfg.commit,
            lang = cfg.name,
        )

    # Instantiate the central @backdated_sources hub.
    hub_targets = {}
    for cfg in lang_configs:
        hub_targets[cfg.name + "_srcs"] = "@%s//:srcs" % _lang_repo_name(cfg.name)
        hub_targets[cfg.name + "_book"] = "@%s//:book.toml" % _lang_repo_name(cfg.name)

    hub_repo(
        name = "backdated_sources",
        targets = hub_targets,
    )

backdated_sources = module_extension(
    implementation = _backdated_sources_extension_impl,
    tag_classes = {
        "language": tag_class(
            attrs = {
                "po": attr.label(mandatory = True, doc = "Label of the .po file."),
            },
            doc = "Defines a language to be included in the translation build.",
        ),
    },
    doc = "A module extension to manage back-dated translation source repositories.",
)
