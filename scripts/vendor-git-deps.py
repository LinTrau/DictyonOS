#!/usr/bin/env python3
"""Point git dependencies in a Cargo.toml at their vendored copies.

Used by dictyonos/kernel.nix.

rustPlatform.fetchCargoVendor keeps git-sourced crates under
source-git-N/<name>-<version>. Cargo refuses to resolve a *replaced* git source
without a pre-existing lockfile ("the source ... requires a lock file to be
present first before it can be used against vendored source code"), and
cargo-osdk regenerates its base crate -- a fresh workspace with no lock -- on
every build. Rewriting the workspace-level git dependencies to plain path
dependencies removes git from the resolution graph entirely, which is both
offline-safe and lockfile-free.

The vendored directories are exactly the revisions the lockfile pins, so the
rewrite is semantics-preserving.
"""
import os
import re
import sys


def vendored_crates(vendor_dir):
    """Map crate name -> path of its vendored copy."""
    crates = {}
    for entry in sorted(os.listdir(vendor_dir)):
        if not entry.startswith("source-git-"):
            continue
        source_dir = os.path.join(vendor_dir, entry)
        for crate in sorted(os.listdir(source_dir)):
            # Directory names look like <name>-<version>; split on the last dash
            # that precedes a digit.
            match = re.match(r"^(.*?)-(\d[^-]*)$", crate)
            name = match.group(1) if match else crate
            crates.setdefault(name, os.path.join(source_dir, crate))
    return crates


def dependency_blocks(text):
    """Yield (start, end) spans of `name = { ... }` blocks."""
    for match in re.finditer(r"(?m)^[ \t]*([A-Za-z0-9_-]+)[ \t]*=[ \t]*\{", text):
        start = match.end() - 1
        depth = 0
        i = start
        in_string = False
        while i < len(text):
            ch = text[i]
            if in_string:
                if ch == "\\":
                    i += 2
                    continue
                if ch == '"':
                    in_string = False
            elif ch == '"':
                in_string = True
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    yield start, i + 1
                    break
            i += 1


def rewrite(text, crates, path_root=None):
    spans = list(dependency_blocks(text))
    out = text
    rewritten = []
    # Walk backwards so earlier spans keep their offsets.
    for start, end in reversed(spans):
        block = out[start:end]
        git = re.search(r'git[ \t]*=[ \t]*"([^"]*)"', block)
        if not git or "asterinas" not in git.group(1):
            continue
        name = git.group(1).rstrip("/").rsplit("/", 1)[-1]
        if name.endswith(".git"):
            name = name[:-4]
        if name not in crates:
            continue
        target = crates[name]
        if path_root is not None:
            # Caller keeps its own (writable, patched) copy of each crate; use the
            # same directory name under that root.
            target = os.path.join(path_root, os.path.basename(target))
        block = re.sub(r'git[ \t]*=[ \t]*"[^"]*"', 'path = "%s"' % target, block)
        block = re.sub(r',[ \t]*(rev|tag|branch)[ \t]*=[ \t]*"[^"]*"', "", block)
        out = out[:start] + block + out[end:]
        rewritten.append(name)
    return out, sorted(rewritten)


def main():
    if len(sys.argv) not in (3, 4):
        sys.exit("usage: vendor-git-deps.py Cargo.toml VENDOR_DIR [PATH_ROOT]")
    manifest, vendor_dir = sys.argv[1], sys.argv[2]
    path_root = sys.argv[3] if len(sys.argv) == 4 else None
    crates = vendored_crates(vendor_dir)
    with open(manifest, encoding="utf-8") as fh:
        text = fh.read()
    new_text, rewritten = rewrite(text, crates, path_root)
    if not rewritten:
        print("vendor-git-deps: no git dependency needed rewriting")
        return
    with open(manifest, "w", encoding="utf-8") as fh:
        fh.write(new_text)
    for name in rewritten:
        target = os.path.join(path_root, os.path.basename(crates[name])) if path_root else crates[name]
        print("vendor-git-deps: %s -> %s" % (name, target))


if __name__ == "__main__":
    main()
