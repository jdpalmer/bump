# bump

Cut a `YY.MM.R` release for jdpalmer projects and update [`jdpalmer/tap`](https://github.com/jdpalmer/homebrew-tap).

## Install

```bash
git clone https://github.com/jdpalmer/bump.git ~/src/bump
mkdir -p ~/bin
ln -sf ~/src/bump/bump.sh ~/bin/bump
```

Clone project repos as siblings of `bump/` (e.g. `~/src/transmute`, `~/src/modc`). Override with `BUMP_SRC` if needed.

## Prerequisites

- `git`, `gh` (authenticated), `brew`
- Tap trusted: `brew trust jdpalmer/tap` (or per-formula)
- Clean git checkout on each project's default branch

## Usage

```bash
bump transmute              # next YY.MM.R for this calendar month
bump jem 26.11.1            # explicit version
bump --dry-run modc         # print actions only
```

Projects: `transmute`, `modc`, `jem`, `perfectfocus`.

Each project has a root `VERSION` file. `modc` also syncs `MODC_VERSION` in `src/cli.h`.

## What it does

1. Computes the next `YY.MM.R` (or uses the version you pass)
2. Writes `VERSION` (and patches `modc` as needed)
3. Commits, annotated-tags, pushes
4. `gh release create --generate-notes`
5. `brew bump-formula-pr` against `jdpalmer/tap`, then merges the PR
