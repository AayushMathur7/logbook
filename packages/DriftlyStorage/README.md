# DriftlyStorage

Legacy scaffold folder.

Storage now lives inside `Sources/DriftlyCore/SessionStore.swift`.

Current runtime storage uses a local SQLite database under:

- `~/Library/Application Support/Driftly/driftly.sqlite`

The store persists:

- raw events
- saved sessions
- generated reviews
- capture settings
- review feedback
- review learning memory
