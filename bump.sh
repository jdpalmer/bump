#!/usr/bin/env bash
# bump.sh — cut a YY.MM.R release and update jdpalmer/tap
set -euo pipefail

usage() {
	cat <<'EOF'
Usage: bump.sh [--dry-run] <project|.|path> [version]

  bump.sh transmute           # $BUMP_SRC/transmute
  bump.sh .                   # current repo
  bump.sh jem 26.11.1         # explicit version
  bump.sh --dry-run modc

Convention: repo root has VERSION; formula is jdpalmer/tap/<basename>.
Projects embed VERSION themselves (Make/#embed); bump only writes the file.

Environment:
  BUMP_SRC   Parent of named checkouts (default: parent of this repo)
  BUMP_TAP   Homebrew tap (default: jdpalmer/tap)
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
BUMP_SRC=${BUMP_SRC:-$(cd "$SCRIPT_DIR/.." && pwd)}
BUMP_TAP=${BUMP_TAP:-jdpalmer/tap}

need() {
	command -v "$1" >/dev/null 2>&1 || {
		echo "error: required command not found: $1" >&2
		exit 1
	}
}

need git
need gh
need brew

run() {
	if [[ $DRY_RUN -eq 1 ]]; then
		printf '+'
		printf ' %q' "$@"
		printf '\n'
	else
		"$@"
	fi
}

# Resolve repo path: absolute/relative path, ".", or sibling name under BUMP_SRC
if [[ "$TARGET" == "." ]]; then
	REPO=$(pwd)
elif [[ "$TARGET" == /* || "$TARGET" == ../* || "$TARGET" == ./* ]]; then
	REPO=$(cd "$TARGET" && pwd)
elif [[ -d "$TARGET/.git" ]]; then
	REPO=$(cd "$TARGET" && pwd)
else
	REPO=$BUMP_SRC/$TARGET
fi

if [[ ! -d "$REPO/.git" ]]; then
	echo "error: git repo not found: $REPO" >&2
	exit 1
fi

NAME=$(basename "$REPO")
FORMULA=$NAME

default_branch() {
	local ref
	ref=$(git -C "$REPO" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null || true)
	if [[ -n "$ref" ]]; then
		echo "${ref##*/}"
		return
	fi
	if git -C "$REPO" show-ref --verify --quiet refs/remotes/origin/main; then
		echo main
	elif git -C "$REPO" show-ref --verify --quiet refs/remotes/origin/master; then
		echo master
	else
		echo "error: cannot determine default branch for $REPO" >&2
		exit 1
	fi
}

BRANCH=$(default_branch)

is_yymm_r() {
	[[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

next_version() {
	local yy mm prefix latest r file_ver
	yy=$(date +%y)
	mm=$(date +%m)
	mm=$((10#$mm))
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

echo "==> $NAME → $VER (formula $BUMP_TAP/$FORMULA)"
[[ $DRY_RUN -eq 1 ]] && echo "(dry-run)"

cd "$REPO"
cur_branch=$(git rev-parse --abbrev-ref HEAD)
if [[ "$cur_branch" != "$BRANCH" ]]; then
	echo "error: expected branch '$BRANCH', on '$cur_branch'" >&2
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
	echo "+ brew bump-formula-pr --no-browse --no-fork --version=$VER $BUMP_TAP/$FORMULA"
	echo "+ gh pr merge --merge <tap-pr>"
	echo "==> dry-run complete for $NAME $VER"
	exit 0
fi

gh release create "$VER" --title "$VER" --generate-notes

echo "==> updating $BUMP_TAP/$FORMULA"
pr_out=$(brew bump-formula-pr --no-browse --no-fork --version="$VER" "$BUMP_TAP/$FORMULA" 2>&1) || {
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
