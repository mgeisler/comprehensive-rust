#!/bin/sh

# The `mdbook` rule from `rules_rust` invokes `mdbook` in a sandbox
# with a restricted `PATH`. We set `PATH` so that `pandoc` can find
# system tools (like `rsvg-convert` and `lualatex`), and `HOME` so
# `lualatex` has a writable directory to manage its font cache.
export PATH="/usr/bin:/bin:$PATH"
export HOME="/tmp"
exec /usr/bin/pandoc "$@"
