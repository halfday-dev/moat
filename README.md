# Moat — Phase 0 PoC

Per-user network flow logging on macOS using `NEFilterDataProvider`. Phase 0 is **observe-only** — all flows are allowed; the filter simply logs which user/process made each connection and to where.

## Architecture

```
┌─────────────────────────────────────────┐
│ Moat.app (SwiftUI host)                 │
│  • Activates system extension           │
│  • Enables/disables content filter      │
│  • Tails shared JSONL log file          │
├─────────────────────────────────────────┤
│ MoatFilter.systemextension              │
│  (NEFilterDataProvider)                 │
│  • Sees every network flow              │
│  • Extracts UID via audit_token_to_ruid │
│  • Logs: timestamp, UID, process, host  │
│  • Returns .allow() for everything      │
├─────────────────────────────────────────┤
│ MoatCore (shared library)               │
│  • RuleEngine: UID + hostname → verdict │
│  • Supports wildcard domain matching    │
│  • FlowLogEntry model                   │
└─────────────────────────────────────────┘
```

## Project Structure

```
moat/
├── Package.swift            SPM manifest (MoatCore + tests)
├── Moat/                    Host app (requires Xcode to build)
│   ├── MoatApp.swift
│   ├── ContentView.swift
│   ├── SystemExtensionManager.swift
│   ├── Moat.entitlements
│   └── Info.plist
├── MoatFilter/              System extension (requires Xcode)
│   ├── FilterDataProvider.swift
│   ├── main.swift
│   ├── MoatFilter.entitlements
│   └── Info.plist
├── MoatCore/                Shared logic (builds via SPM)
│   ├── RuleEngine.swift
│   ├── Rule.swift
│   └── FlowLog.swift
└── MoatTests/               Unit tests (runs via SPM)
    └── RuleEngineTests.swift
```

## Building

### RuleEngine & Tests (SPM)

```bash
cd moat
swift build   # builds MoatCore
swift test    # runs RuleEngineTests
```

### Full App + System Extension (Xcode)

System extensions **cannot** be built with SPM alone — they require Xcode targets with proper signing.

1. Open/create an Xcode project with the source files
2. Create two targets: `Moat` (app) and `MoatFilter` (system extension)
3. Set bundle IDs: `dev.halfday.moat` and `dev.halfday.moat.filter`
4. Select your development team
5. Apply the `.entitlements` files to each target
6. Embed `MoatFilter.systemextension` in the app at `Contents/Library/SystemExtensions/`
7. Build & Run

## Testing

```bash
swift test
```

Tests cover:
- User with no rules → allow
- Default-deny + allowlisted domain → allow
- Default-deny + non-allowlisted domain → deny
- Wildcard matching (`*.github.com` ↔ `api.github.com`)
- Wildcard does NOT match base domain
- Default-allow + blocklisted domain → deny
- Empty/nil hostname → default policy applies
- Case-insensitive matching
- Multi-user rule isolation

## Known Limitations

- **Dev-signed only** — System extensions require proper entitlements from Apple for distribution. Works with SIP disabled or `systemextensionsctl developer on`.
- **Observe only** — Phase 0 allows all flows; the RuleEngine exists but isn't wired into the filter yet.
- **No UI for rules** — Rules are defined in code; a management UI is planned for Phase 1.
- **Log via file** — Uses a shared JSONL file for IPC; future phases will use XPC or App Groups.
- **Requires macOS 13+**

## Next Phases

- **Phase 1:** Wire RuleEngine into FilterDataProvider, add rule management UI
- **Phase 2:** Per-user policy profiles, admin dashboard
- **Phase 3:** MDM integration, remote policy push
