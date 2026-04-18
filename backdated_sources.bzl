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

BACKDATED_PATHS = ["src/", "third_party/", "book.toml"]

def _git_archive_repo_impl(repository_ctx):
    """
    A Repository Rule that extracts specific paths from a git commit.

    Args:
        repository_ctx: The repository context providing access to git
        and the filesystem.
    """
    commit = repository_ctx.attr.commit

    # Use `git archive` to create a tarball of the specific files at
    # the given commit.
    archive = repository_ctx.path("archive.tar.gz")
    result = repository_ctx.execute(
        ["git", "-C", repository_ctx.workspace_root, "archive"] +
        ["--output", archive] + [commit] + BACKDATED_PATHS,
    )
    if result.return_code != 0:
        fail("Failed to run git archive for commit {}: {}".format(commit, result.stderr))

    # Every Bazel repository must have a BUILD.bazel file. We generate
    # one that exposes the archive for use in the main build.
    repository_ctx.file("BUILD.bazel", """
filegroup(
    name = "archive",
    srcs = ["archive.tar.gz"],
    visibility = ["//visibility:public"],
)
""", executable = False)

git_archive_repo = repository_rule(
    implementation = _git_archive_repo_impl,
    attrs = {
        "commit": attr.string(mandatory = True, doc = "The Git commit to archive."),
    },
    doc = "Creates a repository by archiving specific paths from a local Git commit.",
)

def _alias_repo_impl(repository_ctx):
    """
    A simple repository rule that creates aliases to another repository.
    This allows us to have stable repository names (like @lang_da) that point
    to content-addressed repositories (like @repo_abcd123).
    """
    repository_ctx.file("BUILD.bazel", """
alias(
    name = "archive",
    actual = "{}",
    visibility = ["//visibility:public"],
)
""".format(repository_ctx.attr.actual_archive), executable = False)

alias_repo = repository_rule(
    implementation = _alias_repo_impl,
    attrs = {
        "actual_archive": attr.string(mandatory = True),
    },
)

def _hub_repo_impl(repository_ctx):
    """
    Creates a 'hub' repository that provides aliases for all languages.
    This simplifies the main BUILD.bazel by allowing it to use `@backdated_sources//:da.tar.gz`.
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
        # Parse date from a line looking like this (including the
        # quotes and escaped newline):
        #
        # "POT-Creation-Date: 2024-01-24T13:24:49+01:00\n"
        if "POT-Creation-Date:" in line:
            parts = line.strip('"\\n').split(": ", 1)
            if len(parts) < 2:
                continue
            return parts[1]

    # Default to "now" if we don't find the header. This resolves to
    # the current HEAD, which Bazel then pins in the lock file for stability.
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

    # Initialize with English at HEAD.
    lang_configs = [struct(name = "en", commit = "HEAD")]
    repos = {"HEAD": "repo_head"}

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
                # Fallback to HEAD if no commit is found before the date.
                rev_parse = module_ctx.execute(
                    ["git", "-C", po.dirname, "rev-parse", "HEAD"],
                )
                commit = rev_parse.stdout.strip()

            lang_configs.append(struct(
                name = name,
                commit = commit,
            ))

            if commit not in repos:
                repos[commit] = "repo_" + commit[:12]

    # Instantiate the physical data repositories.
    for commit, name in repos.items():
        git_archive_repo(
            name = name,
            commit = commit,
        )

    # Create stable aliases for each language (e.g., @lang_da -> @repo_abcd...).
    for cfg in lang_configs:
        alias_repo(
            name = _lang_repo_name(cfg.name),
            actual_archive = "@%s//:archive" % repos[cfg.commit],
        )

    # Instantiate the central @backdated_sources hub.
    hub_targets = {}
    for cfg in lang_configs:
        hub_targets[cfg.name + ".tar.gz"] = "@%s//:archive" % _lang_repo_name(cfg.name)

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
