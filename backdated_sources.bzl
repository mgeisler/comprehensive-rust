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

def _git_archive_repo_impl(repository_ctx):
    """
    A Repository Rule that extracts specific paths from a git commit.
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

    # Extract the archive immediately so the files are directly
    # accessible.
    repository_ctx.extract(archive)
    repository_ctx.delete(archive)

    # Remove the stray third_party BUILD file. It creates package
    # boundaries that prevent the top-level glob from seeing all
    # files.
    repository_ctx.delete("third_party/cxx/blobstore/BUILD")

    # Generate a BUILD.bazel that provides an aggregate interface.
    repository_ctx.file("BUILD.bazel", """
filegroup(
    name = "content",
    srcs = glob(["src/**", "third_party/**"]),
    visibility = ["//visibility:public"],
)

exports_files(
    ["book.toml"],
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

def _book_repo_impl(repository_ctx):
    """
    A Repository Rule that creates a modified book.toml for a language.
    """
    lang = repository_ctx.attr.lang
    book_path = repository_ctx.path(repository_ctx.attr.book)

    book = toml.decode(repository_ctx.read(book_path))

    # Use Rust edition and settings from the backdated commit to compile old snippets correctly.
    if repository_ctx.attr.pristine_book:
        pristine_path = repository_ctx.path(repository_ctx.attr.pristine_book)
        pristine = toml.decode(repository_ctx.read(pristine_path))
        if "rust" in pristine:
            book["rust"] = pristine["rust"]

    # Set language and adjust site URL. Clear the redirects since they
    # are in sync with the source files, not the translation.
    book["book"]["language"] = lang
    book["output"]["html"]["site-url"] = "/comprehensive-rust/{}/".format(lang)
    book["output"]["html"].pop("redirect", None)

    # Disable linkcheck for translations.
    if "output" in book:
        book["output"].pop("linkcheck", None)
        book["output"].pop("linkcheck2", None)

    # Point `mdbook-i18n-gettext` to the PO file in the workdir root
    # and ensure that `mdbook serve` notices changes to the PO file.
    gettext = book.setdefault("preprocessor", {}).setdefault("gettext", {})
    gettext["po-dir"] = "."
    build = book.setdefault("build", {})
    build["extra-watch-dirs"] = ["."]

    if repository_ctx.which("pandoc"):
        print("Found `pandoc`, enabling mdbook-pandoc")
        book["output"]["pandoc"]["disabled"] = False
    else:
        print("No `pandoc` found, disabling mdbook-pandoc")

    repository_ctx.file("book.toml", toml.encode(book), executable = False)
    repository_ctx.file("BUILD.bazel", """
exports_files(
    ["book.toml"],
    visibility = ["//visibility:public"],
)
""", executable = False)

book_repo = repository_rule(
    implementation = _book_repo_impl,
    attrs = {
        "lang": attr.string(mandatory = True, doc = "The language for the book."),
        "book": attr.label(mandatory = True, doc = "Label of the book.toml file."),
        "pristine_book": attr.label(mandatory = False, doc = "Label of the backdated book.toml file."),
    },
    doc = "Creates a repository with a modified book.toml.",
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
    """

    # English is always at HEAD.
    lang_configs = [struct(name = "en", commit = "HEAD")]
    repos = {"HEAD": "repo_head"}

    for mod in module_ctx.modules:
        for tag in mod.tags.language:
            po = module_ctx.path(tag.po)
            name = po.basename.removesuffix(".po")

            # Skip English if registered via tag, we already added it.
            if name == "en":
                continue

            date = _extract_date(module_ctx, po)

            rev_list = module_ctx.execute(
                ["git", "-C", po.dirname, "rev-list", "-n", "1", "--before", date, "HEAD"],
            )
            if rev_list.return_code != 0:
                fail("Failed to get commit for {} at {}: {}".format(po, date, rev_list.stderr))

            commit = rev_list.stdout.strip()
            if not commit:
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

    # Instantiate language-specific configuration repositories.
    for cfg in lang_configs:
        if cfg.name != "en":
            pristine_book = "@{repo}//:book.toml".format(repo = repos[cfg.commit])
            book_repo(
                name = "book_%s" % cfg.name,
                lang = cfg.name,
                book = "@@//:book.toml",
                pristine_book = pristine_book,
            )

    # Instantiate the central @backdated_sources hub.
    hub_targets = {}
    for cfg in lang_configs:
        if cfg.name == "en":
            # For English, point directly to the local workspace files.
            # This ensures that the mdbook_server can run in-place,
            # which is necessary for plugins like linkcheck.
            hub_targets["en_content"] = "@@//:content"
            hub_targets["en_book"] = "@@//:book.toml"
        else:
            repo_name = repos[cfg.commit]
            hub_targets[cfg.name + "_content"] = "@%s//:content" % repo_name
            hub_targets[cfg.name + "_book"] = "@book_%s//:book.toml" % cfg.name

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
