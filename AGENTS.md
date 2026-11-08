# Mój Słownik

Personal iPhone dictionary and practice app for Russian speakers learning Polish.
SwiftUI, SwiftData, Swift 5.9, iOS 17+. No backend, accounts or synchronization.
All vocabulary is local; web translation sends entered/scanned text to external services.
UI copy is Russian; code, file names and project instructions are English.

## Architecture and reading map

- MojSlownikApp creates ModelContainer(Word); RootTabView hosts Dictionary/Training tabs.
- Models/Word.swift: russian/polish pair, source language, creation date and SRS state.
- Services/: language detection, translation, speech, OCR tokenization and SM-2 scheduling.
- Views/: screens; Theme/Theme.swift: shared colors and cardStyle.
- Translation: Apple on supported iOS 18+ devices → Google gtx → MyMemory.
  Translation is editable before saving. Apple sessions require translationTask.
- OCR requires a physical device; Polish diacritics may be lost.
- Filter due words in memory with words.filter(\.isDue), not SwiftData #Predicate.
- Preserve existing stored words when changing the model.
- Read [docs/architecture.md](docs/architecture.md) for detailed flows and constraints
  only when needed. Do not preload the whole source tree or all agent instructions.
- Installation and signing on a personal iPhone: README.md.

## Feature workflow

Use `$feature-flow <context>` when requested. Everything after the skill name is
free-form task context; no ticket numbers or mode flags.
Skill: .agents/skills/feature-flow/SKILL.md.
Codex agent definitions: .codex/agents/feature-*.toml. Plans: .codex/plans/.
Prefer existing services and Theme and the smallest complete change.
Do not create, update or run E2E/UI automation; preserve existing UI tests and targets.
Do not commit/push without authorization or discard existing user changes.

## Verification

After adding source files or changing project.yml, run `xcodegen generate`.
The generated .xcodeproj is not tracked. Build with no warnings:

```sh
xcodebuild -project MojSlownik.xcodeproj -scheme MojSlownik \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Choose an installed device with `xcrun simctl list devices available` if needed.
If CommandLineTools is active, set DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer.
Use focused unit checks for nontrivial logic where practical. Do not run the scheme's
`xcodebuild test`, which includes UI tests. Documentation-only changes need no app build.
Manual UI checks for affected areas: add Russian and Polish words, edit/save translations,
complete flashcards (ratings update dueDate) and quiz. On a physical iPhone, scan a line,
check its translation, select a word in text and chips, and confirm the scan result
remains after dismissing AddWordView. Report unavailable checks honestly.

Keep this file concise. Update detailed architecture with code in docs/architecture.md;
keep workflow procedures in the skill and task history in plans.
