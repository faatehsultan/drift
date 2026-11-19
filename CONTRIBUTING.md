# Contributing to Drift

Thanks for helping! Bug reports, ideas, docs and code are all welcome.

## Ways to help

- **Report a bug:** [open an issue](https://github.com/faatehsultan/drift/issues/new/choose) with your macOS version, Mac model, Drift version (Settings → General → About) and steps to reproduce.
- **Suggest a feature:** open a feature request and describe the problem it solves.
- **Send a pull request:** for anything bigger than a small fix, open an issue first so we can agree on the approach.

## Development setup

```sh
git clone https://github.com/faatehsultan/drift.git
cd drift
make run
```

You need macOS 13+ and Xcode or the Command Line Tools (Swift 5.9+). Glass effects need the macOS 26 SDK; on older SDKs, use `#available` checks so the code still builds.

## Code guidelines

- **SwiftUI state:** use `ObservableObject` models with `@Published`, observed via `@ObservedObject`. Avoid `@State`, `@StateObject`, `@Binding` and `@Observable`: their macros don't expand on some Command Line Tools installs, and Drift should build there.
- **Text input** uses small AppKit wrappers (`NativeField`, `NativeSearchField`, `NativeTextView`) for reliable focus inside the non-activating notch panel.
- **Models** that drive UI are `@MainActor`.
- **Animations** use the shared curves in `Anim` (`morph`, `tab`, `quick`) so motion stays consistent.
- **YouTube Music API changes:** keep fixes inside `Music/InnerTube.swift` and `Music/Parser.swift`.
- **Privacy:** no analytics or tracking, and no new network destinations without a clear reason in the PR.
- Keep files focused and names descriptive. Comment the "why", not the "what".

## Pull requests

1. Fork and create a branch: `git checkout -b fix/peek-flicker`.
2. Make your change, then `make build` and try it on a real Mac.
3. Write clear commit messages in the imperative ("Fix peek flicker on track change").
4. Open the PR and fill in the template. Add a screenshot or short recording for anything visual.

Maintainers handle version bumps and releases (`make release`), so don't edit `VERSION` or `BUILD_NUMBER` in a PR.

## License

By contributing, you agree that your contributions are licensed under the [GPL-3.0](LICENSE).
