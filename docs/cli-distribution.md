# Hokusai CLI Distribution

This document defines the recommended Homebrew distribution setup for the `hokusai` CLI.

## Recommended Tap Repository

- Recommended name: `ivantokar/homebrew-tap`
- Required? No.
- Best practice: yes, because it follows Homebrew conventions and keeps formulas separated from app source.

Any repository can be used as a tap, but `homebrew-tap` naming is the most recognizable and predictable for users.

## Create the Tap

1. Create a new GitHub repository named `homebrew-tap`.
2. Add a formula at `Formula/hokusai.rb`.
3. Publish tagged release artifacts from `hokusai` (for example, macOS arm64/x86_64 and Linux x86_64/arm64 binaries).
4. Point the formula `url` and `sha256` to those release artifacts.

## User Install Flow

```bash
brew tap ivantokar/homebrew-tap
brew install hokusai
hokusai --help
```

## Notes

- Keep CLI versioning aligned with `hokusai` release tags.
- Update `Formula/hokusai.rb` on every new CLI release.
- Until the tap is ready, users can run the CLI with `swift run hokusai ...`.
