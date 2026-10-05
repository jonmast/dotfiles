#!/usr/bin/env bash
#
# qmllint for The Shell (nix/home/quickshell/), which needs help to run at all.
#
# Two things stand between qmllint and this tree, both of them Quickshell
# conveniences that plain QML does not have:
#
#   1. `import qs.Common` works because Quickshell registers the config root
#      as the module `qs` at runtime. On disk there is no `qmldir` anywhere,
#      so qmllint cannot find those modules and gives up on Theme, Button,
#      Popout — and then reports hundreds of cascading errors about the types
#      it never resolved.
#   2. A singleton in the SAME directory (GoogleTv, Brightness) is visible
#      with no import at all. qmllint resolves the name but not its members,
#      so every `GoogleTv.status` reads as a typo.
#
# So this builds a throwaway mirror of the tree under `qs/`, writes the
# `qmldir` each directory would need, and gives every file an explicit import
# of its own directory. Then it lints the mirror. The mirror is a copy, so
# nothing here can write to the working tree; paths in the output are
# rewritten back to it.
#
# Usage:  qs-lint [FILE...]     no arguments lints the whole shell
#
# Expects QS_LINT_ROOT (the shell's source tree) and QS_LINT_QML_PATH (the QML
# module directories to search, `:`-separated — Quickshell's own types live in
# one and Qt's in another, and missing either turns every `Item` in the tree
# into an unknown type). nix/home/qmllint.nix sets both.
set -euo pipefail

root=${QS_LINT_ROOT:?QS_LINT_ROOT is unset — run this via the qs-lint wrapper}
mirror=$(mktemp -d)
trap 'rm -rf "$mirror"' EXIT

for dir in "$root"/*/; do
    name=$(basename "$dir")
    mkdir -p "$mirror/qs/$name"
    {
        echo "module qs.$name"
        for file in "$dir"*.qml; do
            type=$(basename "$file" .qml)
            # A singleton must be declared as one or its members resolve to
            # nothing, which is the failure this whole script exists to avoid.
            if head -1 "$file" | grep -q "^pragma Singleton"; then
                echo "singleton $type 1.0 $type.qml"
            else
                echo "$type 1.0 $type.qml"
            fi
        done
    } >"$mirror/qs/$name/qmldir"

    # Which types this directory offers, for deciding who needs the import.
    siblings=$(for file in "$dir"*.qml; do basename "$file" .qml; done)

    for file in "$dir"*.qml; do
        self=$(basename "$file" .qml)
        # Only files that actually name a sibling get the import, or qmllint
        # reports the one we injected as unused — a lint tool must not invent
        # findings. Comments do not count as a use (these files discuss their
        # neighbours by name constantly) and neither do imports, since a
        # module can end in a sibling's name: `Quickshell.Services.
        # Notifications` next door to a `Notifications.qml`.
        code=$(sed -e 's://.*::' -e '/^[[:space:]]*import /d' "$file")
        uses=no
        while read -r sibling; do
            [ "$sibling" = "$self" ] && continue
            if grep -qw "$sibling" <<<"$code"; then
                uses=yes
                break
            fi
        done <<<"$siblings"
        if [ "$uses" = no ]; then
            cp "$file" "$mirror/qs/$name/"
            continue
        fi
        # The self-import goes after the existing import block so that line
        # numbers still match the real file — a linter that reports the wrong
        # line is worse than no linter. `pragma` must precede imports, which
        # is the other reason it cannot simply go first.
        awk -v mod="qs.$name" '
            /^import / { last = NR }
            { lines[NR] = $0 }
            END {
                for (i = 1; i <= NR; i++) {
                    if (i == last) printf "%s; import %s\n", lines[i], mod
                    else print lines[i]
                }
            }
        ' "$file" >"$mirror/qs/$name/$(basename "$file")"
    done
done

if [ $# -gt 0 ]; then
    targets=()
    for file in "$@"; do
        absolute=$(realpath "$file")
        targets+=("$mirror/qs/${absolute#"$root"/}")
    done
else
    mapfile -t targets < <(find "$mirror" -name '*.qml' | sort)
fi

# Rules that only ever fire on Quickshell's own types, where the type
# information Qt wants simply is not published: PanelWindow is "not
# creatable" (Quickshell creates it), `margins`/`edges`/`gravity` are
# attached and grouped properties it declares imperatively, and Process's
# exited(QProcess::ExitStatus) names a C++ enum no QML file can import.
# Leaving them on means 30-odd warnings that no edit here can ever fix.
imports=()
IFS=: read -ra paths <<<"${QS_LINT_QML_PATH:?QS_LINT_QML_PATH is unset}"
for path in "${paths[@]}" "$mirror"; do
    imports+=(-I "$path")
done

qmllint \
    --uncreatable-type disable \
    --unresolved-type disable \
    --missing-type disable \
    --signal-handler-parameters disable \
    "${imports[@]}" \
    "${targets[@]}" 2>&1 | sed "s|$mirror/qs/|$root/|g"

exit "${PIPESTATUS[0]}"
