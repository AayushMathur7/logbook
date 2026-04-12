# LogbookStorage

Legacy scaffold folder.

Storage now lives inside `Sources/LogbookCore/SessionStore.swift`.

Current runtime storage uses a local SQLite database under:

- `~/Library/Application Support/Logbook/logbook.sqlite`

The store persists:

- raw events
- saved sessions
- generated reviews
- capture settings
- review feedback
- review learning memory
