# Contributing

## GitHub issues are the source of truth

There is no separate specification in the repository. Design, scope and
acceptance criteria live in GitHub issues, and the code is checked against them.

- **Design first, in an issue.** A feature or a contract change starts as an
  issue that states the problem, the proposed API and semantics, and a checklist
  of requirements. Discuss and revise the design there, before the code.
- **Verify against the issue.** A pull request names the issue it implements
  (`for #N` when it is a slice, `part of #N` when more is coming) and is checked
  against that issue's checklist. If the implementation changes the design,
  update the issue in the same step, so the issue stays current.
- **Close an issue when its checklist is met**, with a comment that links the
  pull requests that did it. Work deliberately left out moves to a new or
  existing issue; do not leave it as an unchecked box in a closed one.
- **Umbrella issues** (`roadmap`) hold the release gates and the order of work.
  Tick a gate only after checking it against the code.
- **The README and the CHANGELOG describe what the code does today.** They are
  not a place for plans: plans belong in issues.

## Labels

- Release scope: `next-major` (required before the next major), `post-major`
  (additive, does not block it), `roadmap` (umbrella).
- Work type: `architecture`, `performance`, `cleanup`, `integration`,
  `testing`, plus GitHub's `enhancement` and `documentation`.
- Ownership: one or more `area:*` labels (`area:input`, `area:output`,
  `area:operations`, `area:server`, `area:pdf`, and so on).

## Pull requests

- Branch from, and target, the release branch named in the roadmap issue
  (currently `release/2.0`), not `main`.
- Add public, black-box tests for behaviour that users can observe
  (`Tests/HokusaiPublicTests`). Add a `CHANGELOG.md` entry under the unreleased
  version.
- Before a release, `Scripts/check-api.sh <git-ref>` lists public API changes
  against a ref.
- Sanitizers (`sanitizers.yml`, address and thread) run weekly (Monday night) and on demand and are not a gate for pull requests: they are slow, and native libraries can produce false positives. A release is published only when a run on the commit to be tagged is green or its reports are understood: start one with `gh workflow run sanitizers.yml` before tagging and check it with `gh run list --workflow sanitizers.yml`.
- A release is a `v*` tag. CI runs on the tag, on the exact commit it names; a
  GitHub Release is published only from a tag whose run is green.
- CI is cheap by design: nothing is run twice. A pull request that changes only documentation skips the build jobs, and a draft skips them (and the benchmark) until it is marked ready. A ready pull request runs Linux with Swift 6.4 and libvips 8.18. The merge to main runs what the pull request did not: the Swift 6.0 / libvips 8.16 baseline and macOS. A `v*` tag and a manual run (`gh workflow run ci.yml --ref <ref>`) build the whole matrix, and a release is published only from a green tag run. Two cheap checks also run on every pull request and are part of `CI complete`: the workflows are linted (`actionlint`), and a change under `Sources/` must update `CHANGELOG.md` (a pull request that has a good reason carries the `no-changelog` label). Dependabot opens one grouped pull request a month to update the GitHub Actions the workflows use. The one required check is `CI complete`. A baseline or macOS-only regression therefore shows up on main, and is fixed forward. The benchmark runs only on a pull request labelled `benchmark`. Open a pull request as a draft while it is still changing, and push in batches.
- Commit messages and pull request descriptions are plain text; do not add
  attribution trailers.
