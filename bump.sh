#!/usr/bin/env bash
# bump.sh — cut a YY.MM.R release and update jdpalmer/tap
set -euo pipefail

usage() {
	cat <<'EOF'
Usage: bump.sh [--dry-run] <project|.|path> [version]

  bump.sh transmute         # sibling ../transmute (next to this repo)
  bump.sh .                 # current directory
  bump.sh jem 26.11.1
  bump.sh --dry-run modc

Writes VERSION, tags, gh release --generate-notes, brew bump-formula-pr.
EOF
	exit 2
}

DRY_RUN=0
TARGET=""
VERSION_ARG=""

while [[ $# -gt 0 ]]; do
	case "$1" in
		--dry-run) DRY_RUN=1; shift ;;
		-h|--help) usage ;;
		-*)
			echo "unknown option: $1" >&2
			usage
			;;
		*)
			if [[ -z "$TARGET" ]]; then
				TARGET=$1
			elif [[ -z "$VERSION_ARG" ]]; then
				VERSION_ARG=$1
			else
				usage
			fi
			shift
			;;
	esac
done

[[ -n "$TARGET" ]] || usage

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
TAP=jdpalmer/tap

for c in git gh brew; do
	command -v "$c" >/dev/null || {
		echo "error: required command not found: $c" >&2
		exit 1
	}
done

run() {
	if [[ $DRY_RUN -eq 1 ]]; then
		printf '+'
		printf ' %q' "$@"
		printf '\n'
	else
		"$@"
	fi
}

# ., path with .git, or sibling of this repo
if [[ -d "$TARGET/.git" ]]; then
	REPO=$(cd "$TARGET" && pwd)
elif [[ -d "$SCRIPT_DIR/../$TARGET/.git" ]]; then
	REPO=$(cd "$SCRIPT_DIR/../$TARGET" && pwd)
else
	echo "error: git repo not found: $TARGET" >&2
	exit 1
fi

NAME=$(basename "$REPO")

is_yymm_r() {
	[[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

next_version() {
	local yy mm prefix latest r file_ver
	yy=$(date +%y)
	mm=$((10#$(date +%m)))
	prefix="${yy}.${mm}."

	latest=$(
		git -C "$REPO" tag -l "${prefix}*" 2>/dev/null \
			| grep -E "^[0-9]+\.[0-9]+\.[0-9]+$" \
			| sort -t. -k3,3n \
			| tail -1 || true
	)
	if [[ -z "$latest" && -f "$REPO/VERSION" ]]; then
		file_ver=$(tr -d '[:space:]' <"$REPO/VERSION")
		if is_yymm_r "$file_ver" && [[ "$file_ver" == "$prefix"* ]]; then
			latest=$file_ver
		fi
	fi

	if [[ -n "$latest" && "$latest" == "$prefix"* ]]; then
		r=${latest##*.}
		echo "${yy}.${mm}.$((r + 1))"
	else
		echo "${yy}.${mm}.0"
	fi
}

if [[ -n "$VERSION_ARG" ]]; then
	is_yymm_r "$VERSION_ARG" || {
		echo "error: version must be YY.MM.R (got '$VERSION_ARG')" >&2
		exit 1
	}
	VER=$VERSION_ARG
else
	VER=$(next_version)
fi

echo "==> $NAME → $VER (formula $TAP/$NAME)"
[[ $DRY_RUN -eq 1 ]] && echo "(dry-run)"

cd "$REPO"

ref=$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null || true)
BRANCH=${ref##*/}
if [[ -z "$BRANCH" ]]; then
	echo "error: set origin/HEAD (git remote set-head origin -a)" >&2
	exit 1
fi
cur=$(git rev-parse --abbrev-ref HEAD)
if [[ "$cur" != "$BRANCH" ]]; then
	echo "error: expected branch '$BRANCH', on '$cur'" >&2
	exit 1
fi
if [[ $DRY_RUN -eq 0 ]]; then
	if ! git diff --quiet || ! git diff --cached --quiet; then
		echo "error: working tree is dirty; commit or stash first" >&2
		exit 1
	fi
fi
if git rev-parse "$VER" >/dev/null 2>&1; then
	echo "error: tag '$VER' already exists" >&2
	exit 1
fi

run git pull --ff-only

if [[ $DRY_RUN -eq 1 ]]; then
	echo "+ write VERSION → $VER"
else
	printf '%s\n' "$VER" >VERSION
fi

run git add VERSION
run git commit -m "Bump version to $VER"
run git tag -a "$VER" -m "$VER"
run git push origin HEAD "$VER"

if [[ $DRY_RUN -eq 1 ]]; then
	echo "+ gh release create $VER --title $VER --generate-notes"
	echo "+ brew bump-formula-pr --no-browse --no-fork --version=$VER $TAP/$NAME"
	echo "+ gh pr merge --merge <tap-pr>"
	echo "==> dry-run complete for $NAME $VER"
	exit 0
fi

gh release create "$VER" --title "$VER" --generate-notes

echo "==> updating $TAP/$NAME"
pr_out=$(brew bump-formula-pr --no-browse --no-fork --version="$VER" "$TAP/$NAME" 2>&1) || {
	echo "$pr_out" >&2
	echo "error: brew bump-formula-pr failed" >&2
	exit 1
}
echo "$pr_out"

pr_url=$(echo "$pr_out" | grep -Eo 'https://github.com/[^ ]+/pull/[0-9]+' | tail -1 || true)
if [[ -n "$pr_url" ]]; then
	gh pr merge "$pr_url" --merge
	echo "==> merged $pr_url"
else
	echo "warning: could not find PR URL in brew output; merge manually if needed" >&2
fi

rel_url=$(gh release view "$VER" --json url --jq .url 2>/dev/null || echo "(release created)")
echo
echo "Done: $NAME $VER"
echo "  release: $rel_url"
[[ -n "$pr_url" ]] && echo "  tap PR:  $pr_url"
