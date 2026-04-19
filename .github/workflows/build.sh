#!/usr/bin/env bash
set -Eeuo pipefail

# Usage: build.sh <book-lang> <dest-dir>
#
# Build the course for a specific language. The sources are back-dated
# to match the state of the translation using the POT-Creation-Date
# header of po/$book_lang.po. The output can be found in $dest_dir.
#
# The src/ and third_party/ directories are left in a dirty state so
# you can run `mdbook test` and other commands afterwards.
#
# See also TRANSLATIONS.md.

book_lang=${1:?"Usage: $0 <book-lang> <dest-dir>"}
dest_dir=${2:?"Usage: $0 <book-lang> <dest-dir>"}

echo "::group::Building $book_lang course"

bazel build //:mdbook-plugins
ls -l bazel-bin/mdbook-plugins
export PATH="$PWD/bazel-bin/mdbook-plugins:$PATH"

bazel build "//:backdated-$book_lang.tar.gz"
rm -rf src/ third_party/ book.toml
tar -xzf "bazel-bin/backdated-$book_lang.tar.gz"

if [ "$book_lang" != "en" ]; then
    # Set language and adjust site URL. Clear the redirects since they are
    # in sync with the source files, not the translation.
    export MDBOOK_BOOK__LANGUAGE=$book_lang
    export MDBOOK_OUTPUT__HTML__SITE_URL=/comprehensive-rust/$book_lang/
    export MDBOOK_OUTPUT__HTML__REDIRECT='{}'

    # Include language-specific Pandoc configuration
    if [ -f ".github/pandoc/$book_lang.yaml" ]; then
        export MDBOOK_OUTPUT__PANDOC__PROFILE__PDF__DEFAULTS=".github/pandoc/$book_lang.yaml"
    fi
fi

# Enable mdbook-pandoc to build PDF version of the course
export MDBOOK_OUTPUT__PANDOC__DISABLED=false

mdbook build -d "$dest_dir"

mv "$dest_dir/pandoc/pdf/comprehensive-rust.pdf" "$dest_dir/html/"
(cd "$dest_dir/exerciser" && zip --recurse-paths ../html/comprehensive-rust-exercises.zip comprehensive-rust-exercises/)

echo "::endgroup::"
