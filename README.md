# bump

Cut a `YY.MM.R` release and update [`jdpalmer/tap`](https://github.com/jdpalmer/homebrew-tap).

## Install

```bash
git clone https://github.com/jdpalmer/bump.git
cd bump
mkdir -p ~/bin
ln -sf "$PWD/bump.sh" ~/bin/bump
```

Keep project checkouts as siblings of this repo.

## Prerequisites

- `git`, `gh` (authenticated), `brew`
- Tap trusted: `brew trust jdpalmer/tap` (or per-formula)
- Clean checkout on the repo’s default branch (`origin/HEAD`)

## Convention

1. Root `VERSION` file
2. Formula named like the directory: `jdpalmer/tap/<basename>`
3. Projects embed `VERSION` themselves (`#embed`, generated header, etc.)

## Usage

```bash
bump transmute              # sibling ../transmute next to this repo
bump jem 26.11.1
bump --dry-run .
bump /path/to/modc
```

## What it does

1. Next `YY.MM.R` (or the version you pass)
2. Write `VERSION`
3. Commit, tag, push
4. `gh release create --generate-notes`
5. `brew bump-formula-pr` + merge the PR
