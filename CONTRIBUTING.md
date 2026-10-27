# Contributing to Brimline

Thank you for your interest in Brimline! Bug reports, ideas, new provider plugins, documentation fixes and code are all welcome.

Brimline is released under the [PolyForm Shield 1.0.0](LICENSE) license. By contributing, you license your contribution under that license and also under the MIT license to Thanaël Fontaine, so that he can use it in his own products too, paid ones included. You confirm that you have the right to contribute it. You also agree to follow the [code of conduct](CODE_OF_CONDUCT.md).

## Ways to help

- **Report a bug:** open an issue with what you did, what you expected, what happened, your macOS version and the Brimline version. **Never paste a token, a cookie or an account's private data**: use fictitious data.
- **Suggest a feature or a provider:** open an issue describing the need first, before writing code, so we can agree on the approach.
- **Security issue:** do **not** open a public issue, see [SECURITY.md](SECURITY.md).

## Rules for changes

- One pull request per change, with what it does and how it was tested.
- `python3 scripts/check_text.py` must pass: no em or en dash, no personal data (home paths, personal email addresses) in tracked files.
- A provider plugin only **reads** the credentials its tool already stores: it never refreshes, rewrites or moves them, and never writes a token to a log or a file.
- Every user-visible change gets a line in the `[Unreleased]` section of [CHANGELOG.md](CHANGELOG.md).
