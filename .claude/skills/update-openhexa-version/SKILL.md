---
name: update-openhexa-version
description: Update the Debian packaging to a new OpenHEXA release. Given a version number (e.g. 5.12.0), researches upstream changes in BLSQ/openhexa-app, bumps compose.yml image tags, adds new ENV vars to .env.dist and new services to compose.yml, prepends a debian/changelog stanza, and updates README.md/UPGRADING.md. Use when asked to bump/update/upgrade the OpenHEXA version of the Debian image.
---

# Update the Debian image to a new OpenHEXA version

This repo packages OpenHEXA (app + frontend + JupyterHub + Forgejo) as a Debian
package. A version bump means: research what changed upstream, propagate it to
the packaging files, and write the release changelog. Follow the steps in
order. **Stop at working-tree changes — never commit or push.** Pushing to
`main` triggers CI to build, smoke-test, and publish the APT repo, so the user
reviews and commits themselves. (The one exception is an automated CI run —
see "Running in CI" at the end.)

Historical reference: `git diff ed43e25 5ca8171` is the net diff of the
4.6.0 → 5.6.2 upgrade — a feature-heavy bump showing the full cascade (new
Forgejo service, new `.env.dist` sections, script changes). Use it as the
model for what a big upgrade touches.

## Step 0 — Inputs and current state

- Require a target version `X.Y.Z` (e.g. `5.12.0`). If none was given, ask.
- Read the current version from the `blsq/openhexa-app:` image tag in
  `compose.yml`. Sanity-check that:
  - the `blsq/openhexa-frontend:` tag carries the same version;
  - the top stanza of `debian/changelog` matches it (convention: the Debian
    upstream version equals the OpenHEXA release it ships, e.g. `5.10.1-1`).
- Verify the target version is newer than the current one (semver compare).
  If the tree is dirty, warn the user before editing.

## Step 1 — Research upstream changes (the core of this task)

Upstream is https://github.com/BLSQ/openhexa-app (a monorepo: `backend/` is
the Django app, `frontend/` the NextJS app).

1. **Read the release notes of every release between current and target**,
   not just the target:
   ```bash
   gh release list -R BLSQ/openhexa-app --limit 40
   gh release view <tag> -R BLSQ/openhexa-app
   ```
2. **Diff the config surface** between the two tags. List changed files via
   `gh api repos/BLSQ/openhexa-app/compare/<current>...<target> --paginate -q '.files[].filename'`
   and inspect the ones that matter for this packaging repo:
   - `backend/config/settings/` (where ENV vars are consumed)
   - any `.env` / `.env.dist` template files
   - `docker-compose*` files (new services, new internal wiring)
   - Dockerfiles / entrypoints (command or port changes)

Extract four things:

1. **New, renamed, or removed ENV vars** → must land in `.env.dist`
   (user-facing config) and/or the `x-app` `environment:` block in
   `compose.yml` (internal Docker-network wiring like service URLs).
2. **New infrastructure** (like Forgejo in 5.0.0) → a new `compose.yml`
   service. Be aware this cascades: `debian/install` (ship new files),
   `.gitignore`, `script/setup.sh` (data dirs, generated secrets),
   `script/openhexa.sh` (backup/restore), `script/common_functions.sh`
   (env plumbing). Check each against the `ed43e25..5ca8171` reference diff.
3. **Breaking changes and one-off migration commands** → UPGRADING.md
   material.
4. **Companion image requirements**: if release notes require a newer
   `blsq/openhexa-base-environment` or `blsq/openhexa-jupyterhub`, **flag it
   to the user but do not bump those tags** — Renovate owns them. Only the
   app and frontend tags are bumped by this skill.

Summarize the findings to the user before editing anything, stating whether
this is a routine bump (tags + changelog only) or a feature bump (cascade).

## Step 2 — compose.yml

- Bump both image tags to the target version — always both, kept identical:
  - `x-app` anchor: `image: "blsq/openhexa-app:<TARGET>"`
  - `frontend` service: `image: "blsq/openhexa-frontend:<TARGET>"`
- Add any new *internal* env vars to the `x-app` `environment:` block,
  following the existing style (a `#` comment explaining each var).
- Add new services following the `forgejo` service as the structural
  example: `platform: linux/amd64`, the `openhexa` network, a healthcheck,
  a restart policy, `${VAR:-default}` host ports, bind mounts via env vars.

## Step 3 — .env.dist

Add new *user-facing* vars in the existing convention:

- Grouped under a section banner (`# Section name` + `####…` underline).
- Each var preceded by an explanatory comment; sensible default values.
- Secrets that `setup.sh` generates on first install are written as
  `${VAR}` envsubst placeholders (e.g. `GIT_SERVER_ADMIN_PASSWORD`) — and
  adding one implies a matching generation change in `script/setup.sh`.

`openhexa.sh env-check` diffs a user's `.env` against `.env.dist`, so
`.env.dist` must be complete: every var the new release reads belongs here.

## Step 4 — debian/changelog

Prepend a new stanza at the top of `debian/changelog`. Do not use `dch`
(devscripts is generally not installed here); hand-write it in this exact
format — spacing matters:

```
openhexa (<TARGET>-1) stable; urgency=medium

  [ <git user.name> ]
  * Update OpenHEXA to version <TARGET>
  * <one bullet per notable change: new ENV vars in .env.dist, new
    services, breaking changes; wrap continuation lines with 4-space indent>

 -- <git user.name> <git user.email>  <output of `date -R`>
```

- Version is `<TARGET>-1` (package version = OpenHEXA version; the old
  `N.0-1` scheme in stanzas before 5.10.1-1 is obsolete).
- Author name/email come from `git config user.name` / `user.email` when a
  human runs this skill; in CI the stanza is authored by blsqbot instead —
  see "Running in CI".
- The trailer line starts with one space, and has two spaces before the date.
- Detail scales with the release: a routine bump gets one or two bullets,
  a feature bump itemizes new ENV vars, services, and breaking changes
  (compare the terse `3.0-1` stanza with the detailed `4.0-1` one).

## Step 5 — UPGRADING.md and README.md

**UPGRADING.md** — add a new version section at the top of the version list
(newest first) whenever the release introduces new env vars, breaking
changes, or manual migration steps. Follow the existing structure:
`## <version>` with `### New environment variables` (a copy-pasteable
`bash` block matching `.env.dist` defaults), `### Breaking changes`, and
`### Manual steps`. A routine bump with no manual steps needs no entry.

**README.md** — update the two version example strings (the version
convention example under "Release, changelog, and versions" and the
`../openhexa_<version>-1_amd64.deb` build-output path). Add or adjust
configuration-property sections only if new user-facing knobs were
introduced (see the "Forgejo Git server" section as the model).

## Step 6 — Verify and report (no commit)

- Validate the compose file parses: `docker compose config -q` (or
  `yq . compose.yml` if Docker is unavailable).
- `grep -rn "<OLD_VERSION>" . --exclude-dir=.git` — the old version must
  only remain in historical records (older `debian/changelog` stanzas,
  UPGRADING.md history), nowhere load-bearing.
- Report to the user: the upstream findings summary, every file edited and
  why, anything flagged but not done (companion images, script cascades
  needing their own testing). Leave the changes uncommitted for review;
  remind them that pushing to `main` builds, smoke-tests, and publishes
  the APT repo via GitHub Actions.

## Running in CI

When the `CI` environment variable is set, this skill is being run by the
`update_openhexa_version` GitHub Actions workflow, not by a human at a
terminal. Three things change:

1. **Step 6's "no commit" rule is lifted.** Commit the working-tree changes to
   a new branch and open a pull request instead of stopping. Everything in
   steps 0–5 is unchanged — the research still drives the edits.
2. **The changelog stanza is authored by blsqbot.** In Step 4, use the
   workflow's `GIT_AUTHOR_NAME` / `GIT_AUTHOR_EMAIL` environment variables
   (`blsqbot <blsqbot@users.noreply.github.com>`) for both the `[ ... ]`
   header and the ` -- ` trailer line — do not read `git config`, which is
   unset in CI, and never attribute the stanza to Claude or a maintainer.
3. **The report goes in the PR body, not the terminal.** Everything Step 6
   says to report — the upstream findings summary, every file edited and why,
   and anything flagged but not done (companion image requirements, script
   cascades needing their own testing) — belongs in the pull request
   description, where the reviewer will actually read it.

The workflow passes the target version, the current version, and the branch
name in its prompt; it has already verified the target is newer and that no
PR for it exists. Never push to `main` — always the branch.
