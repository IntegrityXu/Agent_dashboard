# Pinned SQLite runtime

SQLite 3.54.1, public-domain upstream amalgamation, downloaded from:
https://www.sqlite.org/2026/sqlite-amalgamation-3540100.zip

Archive SHA3-256 (verified against the official download page):
`92281c86e2957f9b9305890f9ac04204caa7b677cc868dc326d942689df28e30`

`upstream.json` also records the archive SHA-256. `sqlite3.c` and `sqlite3.h` are unmodified upstream files. The upstream public-domain dedication is retained at the beginning of each file.

Apple SQLite on the tested Mac returns SQLITE_CANTOPEN/ENOENT when a read-only connection queries a cleanly closed WAL database without sidecars. Standard SQLite supports this case without changing the database contents. Status Board embeds this runtime to remain independent of Homebrew and the installed system SQLite. All production connections still use SQLITE_OPEN_READONLY; no immutable/no-lock URI or read-write fallback is used.

`SQLiteNamespace.h` prefixes public identifiers with `sb_`, preventing symbol collisions with Apple SQLite/frameworks. Regenerate it from this version's public header when upgrading. Public linkage is retained for Xcode's intermediate object linking; the prefix prevents interposition. Loadable extensions are disabled, threading support is enabled, and double-quoted string literals are disabled. JSON functions are required for agent metadata.

To regenerate the namespace header after updating and verifying the pinned source:

```python
import re
from pathlib import Path
root = Path('Packages/StatusBoardCore/Sources/StatusBoardSQLite/include')
names = sorted(set(re.findall(r'\bsqlite3(?:_[A-Za-z0-9_]+)?\b', (root / 'sqlite3.h').read_text())))
(root / 'SQLiteNamespace.h').write_text('// Generated from the pinned public SQLite header. Keep bundled symbols separate from Apple SQLite.\n#pragma once\n' + ''.join(f'#define {name} sb_{name}\n' for name in names))
```

Regression tests must exercise clean writer shutdown, cold read-only reopening, uncheckpointed WAL updates, simultaneous Apple-writer/bundled-reader behavior, and unchanged main-file bytes. System SQLite remains available only to test fixtures and legacy probes.
