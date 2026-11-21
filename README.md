# bump

Cut a `YY.MM.R` release and update [`jdpalmer/tap`](https://github.com/jdpalmer/homebrew-tap).

## Install

```bash
git clone https://github.com/jdpalmer/bump.git ~/src/bump
mkdir -p ~/bin
ln -sf ~/src/bump/bump.sh ~/bin/bump
```

Named projects are resolved under `BUMP_SRC` (default: parent of this repo), e.g. `~/src/transmute`.

## Prerequisites

- `git`, `gh` (authenticated), `brew`
- Tap trusted: `brew trust jdpalmer/tap` (or per-formula)
- Clean checkout on the repo’s default branch (`origin/HEAD`)

## Convention

No project registry. For a repo to be bumpable:

1. Root `VERSION` file (written/updated by this tool)
2. Homebrew formula named like the directory: `jdpalmer/tap/<basename>`
3. Optional: if `src/cli.h` defines `MODC_VERSION`, it is kept in sync

## Usage

```bash
bump transmute              # next YY.MM.R for this calendar month
bump jem 26.11.1            # explicit version
bump --dry-run .
bump /path/to/modc
```

## What it does

1. Computes the next `YY.MM.R` (or uses the version you pass)
2. Writes `VERSION` (and patches `MODC_VERSION` when present)
3. Commits, annotated-tags, pushes
4. `gh release create --generate-notes`
5. `brew bump-formula-pr` against the tap, then merges the PR
