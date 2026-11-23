# Songwriter

A light DAW for songwriting on iPad, built as a Swift Playgrounds app package.
See [SPEC.md](SPEC.md) for the full v1 spec.

## Layout

- `Songwriter.swiftpm/` the Swift Playgrounds app (open it in Swift Playgrounds on iPad)
- `CoreTests/` unit-test package for the pure Swift parts (Model, Theory, MIDI writer, loudness, undo)
- `ci/run.sh` CI script (build, test, publish results to branch `ci-results`)

## CI

Every push (except to `ci-results`) builds the app for the iOS Simulator, runs the unit tests,
and commits logs plus a `STATUS` file to branch `ci-results` under `<commit sha>/` and `latest/`.

## Licences

- GeneralUser GS SoundFont by S. Christian Collins, see `Songwriter.swiftpm/Resources/Licenses/`
- Spectral, Barlow, Barlow Condensed fonts (SIL OFL 1.1), see `Songwriter.swiftpm/Resources/Licenses/`
