# Backend sync: words and folders with Supabase

Mode: FULL. Base: `fc638123f24d31d3c0fcb57b5ddf7c80b3106274` on branch `t3/backend-sync`, clean tree
(`git status --porcelain` empty). Nothing pre-existing to attribute.

## Goal

A signed-in user's words, folders and folder memberships sync between the iPhone and Supabase
(`public.words`, `public.folders`), offline-first. Local SwiftData stays the source of truth
(D1 in backend-abstraction-prep.md). The app works offline exactly as it does now and catches up at the next
trigger. Sync runs:
- after sign-in (first link: local rows are uploaded and server rows downloaded);
- at launch with a restored session, and when the app returns to the foreground;
- about 5 s after the last local edit;
- when the app goes to the background, and before sign-out.

Every run first pulls deltas after a cursor, then pushes dirty rows. Conflicts are resolved by
server-assigned `updated_at` (closes Gap B). Server rows are validated before they touch
SwiftData, and nothing ever hard-deletes a local word.

## Constraints

User instruction (verbatim): "замержил - теперь от main /ios-feature-flow хочу чтобы ты сделал
синхронизацию с бекендом и бд ты ранее записвал в план часть логики которую мы обсуждали"

Binding project rules this plan relies on (AGENTS.md):
- Only `Backend/` may `import Supabase`; in tests only `MojSlownikTests/SupabaseAdapterTests.swift`.
- Schema changes go in new migration files only. Every table keeps RLS `(select auth.uid()) = user_id`
  with WITH CHECK, no `anon` grants, no SECURITY DEFINER in `public`, and a rolled-back test in
  `supabase/tests`. Run Supabase security advisors after applying a migration.
- Server rows are untrusted: `RemoteRecordValidator` runs before SwiftData. `RemoteMergePolicy` never hard-deletes.
- SwiftData: never lose words; new properties are optional or defaulted; no renames.
- Logging: enum events and keys only, no user text, emails or error messages.
- Repositories stay synchronous and `@MainActor`. Views do not write persistence.
- UI copy is Russian. Read DESIGN.md before UI work. Changed user-facing flows get fixture-based E2E.

Discussed design (input from the orchestrator, refined here): the triggers above, no separate
offline queue, LWW with server time, delta pull with an `updated_at` cursor and an index, batched
upserts, pagination under PostgREST's 1000-row cap, pull on foreground with no Realtime, and
RLS by `user_id`.

## Decisions (proposed; the ones marked "confirm" need the user, see Open decisions)

- **S1 Scope (confirm, O1).** Sync covers words (including SRS fields and `folderIDs`) and folders.
  Achievements (`achievements.v1`) and daily activity (`dailyStudyActivity.v1`) stay device-local,
  so Gaps D and G stay open by design.
- **S2 No SwiftData remodel.** Local `Word` keeps `russian`/`polish`. Wire mapping:
  `term = polish`, `term_language = "pl"`, `translation = russian`, `translation_language = "ru"`,
  `entered_language = sourceLanguageCode` (an invalid value falls back to `"pl"`),
  `category = WordCategory.stableID`. On the way in, a validated pair is always `{ru, pl}` in
  either order (`AppLanguage` has only those two), so the side whose language is `.russian`
  becomes `russian`.
  The only model change is one **additive optional property** per model (S3), a lightweight
  migration of the same kind as `uuid`/`updatedAt`/`deletedAt` (LegacySchemaMigrationTests).
- **S3 Per-row dirty tracking, not a device-clock watermark.** New `serverUpdatedAt: Date? = nil` on
  `Word` and `WordFolder`. It holds only one of three things:
  - **server** `updated_at` values;
  - `nil` ("never synced to the linked account");
  - the re-link sentinel `Date.distantPast` (S9).

  Device time is **never** written into it (AC-5).
  - `isSyncDirty = serverUpdatedAt != lastModifiedAt`. This is equality, never ordering. Every
    existing write already sets `updatedAt = now` (FolderStore.swift:35/57/80/134/194,
    ScanWordStore.swift:34/97/125, SwiftDataRepositories.swift:71, DailyStudyStore.swift:107/139,
    `markDeleted`), so it marks the row dirty without touching any write site.
  - After a push ack or an applied pull, the sync sets **both** `updatedAt` and `serverUpdatedAt`
    to the server timestamp.
  - Rejected alternative: "dirty = `updatedAt > lastPushAt`". It is unsafe because the device
    clock can move backwards (a manual time change or an NTP correction), and edits made in that
    window would never be pushed.
- **S4 Server time (closes Gap B).** A new migration adds a BEFORE INSERT OR UPDATE trigger on
  `words` and `folders`:
  - `new.updated_at := greatest(date_trunc('milliseconds', clock_timestamp()), old.updated_at + interval '1 millisecond')`.
    On INSERT there is no `old`, so it uses the clock value only.
  - The trigger function is SECURITY INVOKER, `set search_path = ''`, and lives in a non-exposed
    schema `private`.
  - `clock_timestamp()` instead of `now()`, together with the `+1 ms` floor, guarantees that every
    committed version of a row has a strictly larger `updated_at` than the previous version.
    Without it, two devices upserting the same row concurrently could leave a final server row
    that is older than the loser's ack, and the loser's later pull would skip it forever.
  - Millisecond truncation makes `updated_at` round-trip exactly through Swift `Date` and the
    cursor (S6).
  - Clients never send `updated_at`.
- **S5 Merge rule (confirm, O3/O4).** This rewrites the pure `RemoteMergePolicy.decide`
  (RemoteMergePolicy.swift:20-31). Branches are evaluated in order:
  1. No local row: an active remote row gives `.insert`, or adoption (S8). A remote tombstone
     gives `.keepLocal`.
  2. `serverUpdatedAt == .distantPast` (re-link sentinel, S9): **the server wins**. A remote
     tombstone gives `.softDelete`, or `.acknowledge` if the local row is already deleted. Otherwise
     `.update` (this restores a local tombstone).
  3. `serverUpdatedAt != nil` and `remote.updatedAt <= serverUpdatedAt`: `.keepLocal` (an echo or a
     stale row; both values are server time).
  4. Local row not dirty: a remote tombstone gives `.softDelete(at:)`, or `.acknowledge` if the
     local row is already deleted. An active remote row gives `.update`.
  5. Local row dirty (a true concurrent change): a remote tombstone against an active local row
     gives `.softDelete` ("delete wins"). Anything else gives `.keepLocal`, and the next push
     overwrites the server ("the last device to sync wins").

  New case `.acknowledge`: it sets only `updatedAt = serverUpdatedAt = remote.updatedAt`. The rule
  is whole-row for SRS and for `folderIDs` (Gaps E and F are accepted at word granularity). No
  decision hard-deletes.
- **S6 Cursor and pagination.** One cursor per table and per linked account:
  `SyncCursor { updatedAtMillis: Int64, id: UUID }`.
  - Each pull starts at `(cursor.updatedAtMillis − 60 000, nil UUID)`. The 60 s overlap covers
    transactions that committed out of `clock_timestamp()` order. Re-fetched rows are no-ops by S5.
  - The query is
    `select <columns> where user_id = eq.<ownerID> and updated_at = gte.<ts> and or=(updated_at.gt."<ts>",and(updated_at.eq."<ts>",id.gt.<uuid>)) order by updated_at, id limit 500`.
    - The `user_id` filter means rows of another session's account are never asked for.
    - The redundant `gte` gives the `(user_id, updated_at, id)` index a range start.
    - `limit 500` stays under the 1000-row `max_rows`.
  - `<ts>` is built from integer milliseconds (UTC `yyyy-MM-ddTHH:mm:ss.SSSZ`), never from a
    `DateFormatter`, so equality is exact.
  - Ties are expected (all rows of one upsert can share a millisecond), and the `id` tiebreak
    handles them.
  - Pages repeat until one returns fewer than `limit` rows. The cursor is persisted after each
    page is applied and saved.
  - Rejected rows follow item 9 and S12: content errors are skipped and the cursor moves past them.
    A `foreignOwner` row (impossible with the filter) means the response is untrustworthy: the
    cycle aborts, nothing of that page is applied, and the cursor is not saved.
- **S7 Push.** Each cycle builds one snapshot of dirty rows with a `uuid`, **tombstones included**.
  Every dirty tombstone is uploaded; S5 never materializes a local row from a remote tombstone,
  so this is cheap and closes the "lost ack, then delete" hole.
  - Folders are pushed first, then words, in batches of 200 via `upsert(onConflict: "user_id,id")`
    returning `id,updated_at`.
  - Every row encodes **every** key, with explicit `null`s. supabase-swift sends `columns=` as the
    union of keys (PostgrestQueryBuilder.swift:239-248), and an omitted `deleted_at` would never
    clear a server tombstone.
  - `user_id` is sent explicitly as the linked account. If the session changed underneath, RLS
    WITH CHECK rejects the request instead of writing into another account.
  - Outgoing schedules are clamped on the wire only (the local row is untouched):
    `easeFactor` to 1.3…10, `intervalDays` to 0…36 500, `dueDate ≤ now + 36 500 d`,
    `knowledgeTier` outside 0…3 → nil, an unknown grade raw value → nil. This handles words
    scheduled before the SRSEngine cap (SRSEngine.swift:31-32).
  - Each outgoing row is then validated with the same `RemoteRecordValidator.validate` that other
    devices run on pull. The payload carries the validator's **trimmed** `term`/`translation`/`name`.
  - Text length is counted in **Unicode scalars**, matching the server's `char_length` on a UTF-8
    database. Swift `count` counts graphemes and would let combining-mark text through that the
    server CHECK rejects.
  - Rows that fail validation are skipped, stay dirty, and are counted in the log.
  - Acks are applied only if the row's `lastModifiedAt` still equals the snapshot. An edit made
    during the request keeps the row dirty.
  - A permanently rejected batch (SQLSTATE 22/23, HTTP 413) is retried row by row. A row the
    server still rejects goes into a session-scoped `rejected: Set<RowVersion(id, lastModifiedAt)>`.
    It is not retried until it changes or the app restarts, and the skip is logged with
    `reason=server_rejected` and no id.
- **S8 Duplicate adoption on pull (confirm, O5).** When S5 says `.insert` for a remote word and an
  active local word **not yet synced to this account** (`serverUpdatedAt == nil` or the sentinel)
  has the same normalized pair, the local row is re-keyed instead of inserting a duplicate:
  - `uuid = remote.id`, remote fields applied, `folderIDs = remote ∪ local` (remote order first),
    and `updatedAt = serverUpdatedAt = remote.updatedAt`.
  - If the union added ids, `updatedAt = now` (dirty, pushed next).
  - Lookup is a dictionary `[normalizedPairKey: Word]` built **once per apply call** from the
    unsynced active words, giving O(n), not O(n²). The key uses `Word.matches`' normalization
    (trim, NFC, lowercase) as `"<polish>\u{1F}<russian>"`.
  - Folders work the same way, via a `[FolderStore.nameKey: WordFolder]` dictionary: an unsynced
    active local folder with the same name key adopts the remote id, and every local
    `Word.folderIDs` entry is rewritten (those words become dirty).
  - `persistentModelID` is unchanged, so daily activity keeps working. FolderPicker reconciles a
    vanished selection (FolderPicker.swift:48, :294).
  - Any other name collision is accepted as a duplicate name.
- **S9 Account linking (confirm, O2).** `sync.v1` in UserDefaults stores `linkedAccountID`, the
  cursors, `capabilityVersion` and `lastSyncedAt`.
  - **Linking** (first link, or re-link after confirmation) clears the cursors and resets the
    per-row state:
    - a row that is clean (`!isSyncDirty`) and was synced (`serverUpdatedAt != nil`) gets
      `serverUpdatedAt = .distantPast`, the sentinel. It is uploaded only if the account lacks it;
      otherwise the server version wins (S5 branch 2). Stale device copies therefore never
      overwrite newer SRS, categories or memberships in the account.
    - every other row gets `nil`: real local changes, uploaded and LWW-merged by S5.
  - No link: the first signed-in account is linked automatically.
  - Same account: delta sync.
  - **Different account: sync is paused** (status `accountMismatch`). Nothing is uploaded. The
    account sheet offers «Объединить словарь с этим аккаунтом» behind a confirmation, which runs
    linking for the new account.
  - Sign-out keeps local data and the link (invariant). It cancels a running cycle after the
    bounded final sync.
- **S10 Server hard deletes are revoked (confirm, O8).**
  - `authenticated` loses DELETE, TRUNCATE (which bypasses RLS), REFERENCES and TRIGGER on
    `words`/`folders`. `anon` gets the same explicit revoke, as a no-op safety net.
  - The two delete policies are dropped.
  - Soft delete is the only deletion path. Account deletion still cascades through the
    `auth.users` FK.
- **S11 Tombstone purge (Gap C) is out of scope (confirm, O7).**
- **S12 Validator changes (confirm, O9 for the text part).**
  - **Text:** allow interior U+0009/U+000A/U+000D, because AddWordView's fields are multiline
    (AddWordView.swift:145, :192). The length check uses `unicodeScalars.count` (S7).
  - **Dates:** `updated_at` is server-assigned, so it gets only the lower bound `earliestDate`
    and no device-clock upper bound. `created_at`/`deleted_at` are bounded by
    `max(now, updatedAt) + allowedClockSkew`, and `due_date` by
    `max(now, updatedAt) + 36 500 d + skew`.
  - A device whose clock is days behind therefore no longer rejects other devices' fresh rows,
    which would otherwise be skipped past by the cursor forever. Remaining `invalidDate` rows are
    genuinely implausible content and are skipped.
- **S13 Engine placement.** These pieces live in `Services/` and import Foundation and SwiftData
  only, so tests use a fake remote with no network and no Supabase import:
  - the transport protocol `SyncRemote`;
  - the orchestration in `SyncEngine`;
  - the SwiftData side in `SwiftDataSyncStore`.

  `Backend/SupabaseSyncRemote.swift` is the only new file that imports Supabase. The wire DTOs
  sit next to the existing ones in `Backend/RemoteRecords.swift`. `Stores/SyncStore.swift` owns
  the triggers, status, linking and UI state.
- **S14 Triggers (confirm, O10).**
  - **Every** cycle, including background and sign-out, runs: pull folders delta → pull words
    delta → push folders → push words. Usually that is 2 small GETs plus the needed upserts.
    Pulling first is what makes "delete wins" hold for background and sign-out syncs (a stale
    edit cannot upsert `deleted_at = null` over a tombstone it has not seen).
  - One cycle runs at a time. A trigger during a running cycle schedules exactly one follow-up.
  - Debounce is 5 s after the last local change. Foreground syncs are throttled to 30 s.
- **S15 UI (confirm, O6).** A small «Синхронизация» card in the signed-in account sheet:
  - status line, «Синхронизировать сейчас» text button, and the mismatch block from S9;
  - reuses `cardStyle`, the calm `info.circle` footnote pattern and text buttons, with no new
    tokens;
  - simulator screenshots go to the user for approval instead of an HTML mockup (O11).
- **S16 Quiet achievements after pulled changes.**
  - After a pull that inserted, updated or adopted words or folders, `SyncStore` calls
    `AchievementStore.recordNextUnlocksSilently(now:)`.
  - That one-shot flag is consumed by the next `sync(vocabulary:)` call that unlocks something,
    and expires after 10 s.
  - Unlocks caused by synced vocabulary are recorded without banners or `achievement.unlocked`
    logs, like the first-install sync (AchievementStore.swift:79-89).

## Acceptance criteria

- **AC-1** Signed in on a device with no link: within one cycle every active local word and folder exists in
  `public.words`/`public.folders` with the S2 mapping. Server rows of that account appear locally
  (Словарь list, FolderPicker) without restarting the app.
- **AC-2** After a local add, edit, category change, membership change, delete or SRS review, a
  cycle runs about 5 s after the last change and pushes the row. Delete reaches the server as
  `deleted_at` (also for rows whose earlier push ack was lost), never as a hard delete.
- **AC-3** Pulls fetch only the signed-in account's rows with `(updated_at, id)` after the cursor
  minus 60 s, in pages of at most 500. 1 200 rows sharing one `updated_at` all arrive. On
  foreground this happens at most once per 30 s.
- **AC-4** Offline: edits work as today, nothing is lost, and the rows stay dirty. A failed page
  or batch changes nothing for itself: its rows stay unapplied or dirty, and its cursor is not
  saved. Pages and batches completed before it in the same cycle stay committed. The next
  successful trigger continues from there.
- **AC-5** The server assigns `updated_at` (client values are ignored), and it strictly increases
  per row. `serverUpdatedAt` only ever holds server values, nil, or the re-link sentinel. Clients
  compare only server timestamps with each other, or equality of local values.
- **AC-6** The merge follows S5, also in background and sign-out cycles: a remote tombstone beats a
  dirty local edit and is never undone by that device's push. No sync path hard-deletes a local
  row: the row count never decreases.
- **AC-7** Every server row passes `RemoteRecordValidator` before SwiftData. Content-invalid and
  unsupported rows are skipped and counted, and the cursor advances past them. A foreign-owner
  response aborts the cycle without advancing. The local rows of skipped ids are held and not
  pushed, so they never overwrite a newer client's version, until a later pull applies those ids
  or a capability bump re-pulls them.
- **AC-8** With a different linked account, nothing is uploaded until the user confirms
  «Объединить». After confirming, local rows the account lacks are uploaded. Rows the account
  already has keep the account's version, unless they were edited locally while unsynced.
- **AC-9** Sign-out keeps all local words and folders. A final cycle is attempted within the
  existing 3 s sign-out bound.
- **AC-10** Going to the background starts a cycle inside a background task that ends exactly
  once.
- **AC-11** A pull that changes folders refreshes `FolderLibraryStore.options` (closes Gap A).
  Rows pulled into an already-open Словарь update or disappear without a relaunch.
- **AC-12** The account sheet shows the sync status in Russian («Синхронизировано: …»,
  «Синхронизация…», «Не удалось синхронизировать. Повторим позже.», mismatch text), and
  «Синхронизировать сейчас» runs a cycle.
- **AC-13** Logs contain only enum events with counts, trigger and reason names, and error
  domain/code. No word, folder name, row id, email or message is logged.
- **AC-14** The DB tests prove:
  - the trigger behaviour;
  - upsert under RLS (own rows only, WITH CHECK on `user_id`);
  - DELETE and TRUNCATE are denied;
  - the `private` function is not callable or usable by API roles;
  - keyset ordering over ties;
  - the new indexes exist.

  `scripts/test-db.sh` passes.
- **AC-15** Existing installs open with every word intact. New properties are nil, so all rows
  are dirty until the first link.
- **AC-16** Achievements unlocked only because of pulled vocabulary show no banner.

## Changes by file

### Models

1. `MojSlownik/Models/Word.swift`.
   - Add `var serverUpdatedAt: Date? = nil` after `deletedAt` (line 15), with the comment "server
     updated_at of the last synced version; nil = never synced to the linked account;
     .distantPast = re-link sentinel".
   - In the extension, add `var isSyncDirty: Bool { serverUpdatedAt != lastModifiedAt }`.
   - Move the private `normalized(_:)` inside `matches` (lines 48-51) to
     `static func normalizedText(_:)`, reused by `matches` with unchanged behaviour.
   - Add `var syncPairKey: String { Word.normalizedText(polish) + "\u{1F}" + Word.normalizedText(russian) }`.
2. `MojSlownik/Models/WordFolder.swift`. Add the same property after line 11 and the same
   `isSyncDirty`.

### Services (Foundation/SwiftData only; no `import Supabase`)

3. **New `Services/SyncRemote.swift`.**
   - `struct SyncCursor: Codable, Equatable, Sendable { let updatedAtMillis: Int64; let id: UUID }`
     with these helpers:
     - `init(updatedAt: Date, id:)`, using `Int64((updatedAt.timeIntervalSince1970 * 1000).rounded())`;
     - `func overlapping(by: Int64 = 60_000) -> SyncCursor`, which uses the nil UUID as id;
     - `var timestampString: String`, built from integer arithmetic: UTC `yyyy-MM-ddTHH:mm:ss.SSSZ`
       via `Calendar(identifier: .gregorian)` with a UTC time zone for the date part and
       `millis % 1000` for the fraction.
   - `struct RemoteAck: Decodable, Equatable, Sendable { let id: UUID; let updatedAt: Date }`
     (`updated_at` key).
   - `enum SyncRemoteError: Error, Equatable { case rejected, unauthorized }`. Any other error is
     transient.
   - The protocol:
     ```swift
     @MainActor protocol SyncRemote: AnyObject {
         func fetchFolders(ownerID: UUID, after cursor: SyncCursor?, limit: Int) async throws -> [RemoteFolderRecord]
         func fetchWords(ownerID: UUID, after cursor: SyncCursor?, limit: Int) async throws -> [RemoteWordRecord]
         func upsertFolders(_ rows: [RemoteFolderUpsert]) async throws -> [RemoteAck]
         func upsertWords(_ rows: [RemoteWordUpsert]) async throws -> [RemoteAck]
     }
     ```
4. **New `Services/SyncState.swift`.**
   - `struct SyncState: Codable, Equatable` with `linkedAccountID: UUID?`, `capabilityVersion: Int`
     (default 0), `foldersCursor: SyncCursor?`, `wordsCursor: SyncCursor?`, `lastSyncedAt: Date?`
     and `heldIDs: Set<UUID>` (default empty; item 6).
     Its custom `init(from:)` uses `decodeIfPresent` with defaults, like `AchievementState`.
   - `@MainActor protocol SyncStateRepository { func load() -> SyncState; func save(_:) throws }`.
   - `UserDefaultsSyncStateRepository(defaults:key: "sync.v1")`. Missing or corrupt data gives
     `SyncState()`.
5. **New `Services/SwiftDataSyncStore.swift`.** `@MainActor final class SwiftDataSyncStore(container:now:)`.
   Each method uses one fresh `ModelContext(container)` with `autosaveEnabled = false` and an
   explicit save. On failure it calls `rollback()` and rethrows, the same pattern as
   ScanWordStore.swift:51-56.
   - `static let relinkSentinel = Date.distantPast`.
   - `func prepareLink() throws`: S9 reset for every word and folder (sentinel for clean, synced
     rows; nil otherwise).
   - `func knownFolderIDs() throws -> Set<UUID>`: all folder ids, tombstones included. The engine
     reads it once per cycle, after the folder pull and before the word pull, and passes it to
     `RemoteRecordValidator.validate(_:ownerID:knownFolderIDs:now:)`, which requires it.
   - `func applyFolders(_ rows: [ValidatedRemoteFolder]) throws -> SyncApplyResult` and
     `func applyWords(_ rows: [ValidatedRemoteWord]) throws -> SyncApplyResult`:
     - Fetch all rows once per call. Build `[UUID: Word]` (rows without a uuid are ignored) and
       the S8 adoption dictionaries once.
     - Decide with `RemoteMergePolicy` (item 9).
     - Apply:
       - Insert: build `Word(russian:polish:sourceLanguage:createdAt:category:)`, then set
         `uuid`, the SRS fields, `folderIDs`, `updatedAt = serverUpdatedAt = remote.updatedAt`
         and `deletedAt = nil`.
       - Update: assign text through `.lowercased()` (the Word.init invariant) and set
         `categoryRawValue = category.rawValue`, `sourceLanguageCode = enteredLanguage.rawValue`,
         `deletedAt = remote.deletedAt` (nil restores a tombstone), and
         `updatedAt = serverUpdatedAt = remote.updatedAt`.
       - Soft delete: `deletedAt = remote.deletedAt`, `updatedAt = serverUpdatedAt = remote.updatedAt`.
         Other words' memberships are untouched; they arrive as their own rows.
       - Acknowledge: timestamps only.
       - Adoption: S8. An adopted row is removed from the adoption dictionary so that it is
         adopted only once.
     - Save once per call and return
       `SyncApplyResult { inserted, updated, softDeleted, adopted: Int; var changedAnything: Bool; var foldersChanged: Bool }`.
   - `func pendingFolders(ownerID:now:excluding:) throws -> [PendingRow<RemoteFolderUpsert>]` and
     `func pendingWords(ownerID:now:excluding: Set<UUID>) throws -> [PendingRow<RemoteWordUpsert>]`:
     - Take all dirty rows with an identity, tombstones included, except the ids in `excluding`
       (the held ids, item 6).
     - Map with clamping and trimmed text (S7), then validate through `RemoteRecordValidator` by
       building the matching `RemoteWordRecord`/`RemoteFolderRecord` with `userID = ownerID` and
       `updatedAt = now`.
     - `PendingRow { id, snapshot: Date (lastModifiedAt), payload }`. Invalid rows are returned
       separately as a count per `RemoteRecordError` case.
     - `pendingWords` first runs `WordIdentityBackfill.assignMissing(in:rollbackOnFailure:)`,
       which normally does nothing.
   - `func markPushed(_ acks: [RemoteAck], snapshots: [UUID: Date], kind: .words/.folders) throws`:
     for each ack whose row still has `lastModifiedAt == snapshot`, set
     `updatedAt = serverUpdatedAt = ack.updatedAt`.
6. **New `Services/SyncEngine.swift`.** `@MainActor final class SyncEngine` with
   `init(remote: any SyncRemote, local: SwiftDataSyncStore, state: any SyncStateRepository, now: () -> Date)`,
   `static let pageSize = 500`, `pushBatchSize = 200`, `capabilityVersion = 1` and
   `overlapMillis = 60_000`. It keeps the session-scoped `rejected` set (S7).
   - `func link(to accountID: UUID) throws`: `local.prepareLink()`, then save
     `SyncState(linkedAccountID: accountID, capabilityVersion: Self.capabilityVersion)` with
     cleared cursors.
   - `func run(ownerID: UUID) async throws -> SyncReport`. There is no mode: every cycle pulls,
     then pushes (S14).
     - Throws `SyncEngineError.notLinked` unless `state.linkedAccountID == ownerID`.
     - A capability-version bump clears the cursors.
     - Pull folders, then words. For each page:
       1. Fetch with `ownerID`, from `cursor?.overlapping` and then from the keyset of the
          previous page's last row.
       2. Validate each record. Content errors (`invalidID`, `invalidText`, `invalidLanguage`,
          `unsupportedLanguage`, `invalidCategory`, `unsupportedCategory`, `tooManyFolders`,
          `invalidDate`, `invalidSchedule`) are skipped and counted. `foreignOwner` throws
          `SyncEngineError.untrustedResponse`; nothing of the page is applied.
          The id of every content-skipped row joins `SyncState.heldIDs`, a persisted
          `Set<UUID>` capped at 5 000. These are server rows this build cannot read, and a newer
          client may have written them.
       3. Apply. An id whose remote row is applied successfully leaves `heldIDs`.
       4. Save the cursor of the last fetched row.
       5. Check `Task.checkCancellation()` between pages.
     - Then push folders, then words, in batches, calling `pending…(excluding: heldIDs)`. Local
       rows of held ids are never pushed, so they cannot overwrite a newer client's category,
       language or dates. A capability bump or `link` clears `heldIDs`, together with the cursors,
       and the rows are pulled again. `SyncRemoteError.rejected` sends a batch row by row (S7). Any other error aborts the cycle; already-acked batches stay marked.
     - It sets `lastSyncedAt = now` and returns
       `SyncReport { pulled, pushed, skipped: [String: Int], foldersChanged, vocabularyChanged }`.
   - No `import Supabase`, no UI and no logging. The store logs.
7. **New `Services/LocalChangeSignal.swift`.**
   `@MainActor final class LocalChangeSignal { var handler: (() -> Void)?; func notify() { handler?() } }`.
8. **New `Services/UITestSyncRemote.swift` (`#if DEBUG`).** `InMemorySyncRemote: SyncRemote`, a
   network-free server model used by unit tests and UI tests.
   - It stores records by `(userID, id)` and filters fetches by `ownerID`.
   - It mimics the trigger: `updatedAt = max(clock truncated to ms, previous + 1 ms)`, with one
     timestamp per upsert call so batches tie.
   - It implements keyset `after` semantics exactly like S6, throws `.unauthorized` when an upsert
     row's `user_id` differs from `currentUserID`, and returns acks.
   - Hooks:
     - `nextError`;
     - `failAll`;
     - `failNextCalls: Int` (the first N calls throw a transient `URLError(.notConnectedToInternet)`);
     - `rejectWhere: (RemoteWordUpsert) -> Bool` (returns `.rejected`);
     - `beforeAck: (() -> Void)?` (to simulate edits during a push);
     - `scriptedChanges: ((inout Server) -> Void)?` and `func armScriptedChanges()`. Arming
       applies the changes server-side once; later calls do nothing. It is never keyed to counting
       fetch calls;
     - `requestedCursors` (an assertion log);
     - `seed(...)`.
   - `enum UITestSyncState: String, CaseIterable` with `makeRemote(now:)` and
     `seedState(into: SyncStateRepository, now:)`. Its cases:
     - `empty`: an empty server, no link.
     - `remoteVocabulary`: for `StaticAuthBackend.testAccount`, the server has folder «Из облака»
       (id `…f9`), words `most/мост` (in that folder) and `ser/сыр`, and `kot/кот` with a
       different id (exercises S8 against `basicVocabulary`).
     - `failsOnce`: an empty server with `failNextCalls = 1`.
     - `linkedToOtherAccount`: `sync.v1` linked to `00000000-0000-4000-8000-0000000000e2`.
     - `syncedThenRemoteChanges`: for use with the `syncedVocabulary` fixture.
       - The server holds exactly the fixture rows: same fixed uuids, same ms timestamps, owner
         = test account.
       - `sync.v1` is linked to the test account, with cursors at the newest fixture row.
       - `scriptedChanges`: `dom` becomes a tombstone, and `kot` gets translation `котик`. Both
         are newer server versions.
       - `AppResources.uiTest` sets `sync.onCycleSucceeded = { remote.armScriptedChanges() }`, so
         the changes appear only after the first successful cycle.
9. `Backend/RemoteMergePolicy.swift`. It stays in Backend and needs no Supabase import.
   - Add the `.acknowledge` decision case.
   - `LocalRecordState` becomes `{ serverUpdatedAt: Date?, isDirty: Bool, isDeleted: Bool }`.
   - `decide(local:remoteUpdatedAt:remoteDeletedAt:)` implements the S5 branches 1-5 exactly, with
     the sentinel compared against `Date.distantPast`.
   - `Word.localRecordState`/`WordFolder.localRecordState` are built from the new fields.
   - Update the type comment.
10. `Backend/RemoteRecords.swift`.
    - S12 in `validText` (lines 242-250): allow `\t`, `\n`, `\r`, and use
      `trimmed.unicodeScalars.count <= maxLength`.
    - S12 in `validateTimestamps` (lines 252-261) and the due-date bound (line 170) take
      `updatedAt` into account: `updatedAt` gets only the lower bound;
      `latest = max(now, updatedAt) + allowedClockSkew` for `createdAt`/`deletedAt`; the due date
      is bounded by `max(now, updatedAt) + maxIntervalDays·86 400 + skew`.
    - Add `struct RemoteWordUpsert: Encodable, Equatable, Sendable` with all columns except
      `updated_at`: `id, user_id, term, term_language, translation, translation_language,
      entered_language, category, folder_ids, created_at, deleted_at, ease_factor,
      interval_days, repetitions, due_date, last_review_grade, knowledge_tier,
      consecutive_soft_misses`. A hand-written `encode(to:)` uses `encode` (never
      `encodeIfPresent`), so `null` is explicit.
    - Add `struct RemoteFolderUpsert` with `id, user_id, name, sort_order, created_at, deleted_at`,
      encoded the same way.
    - Add `static let selectColumns` strings listing exactly the decoded columns.
    - Update the header comment.
11. **New `Backend/SupabaseSyncRemote.swift`** (`import Supabase`).
    `@MainActor final class SupabaseSyncRemote: SyncRemote` over `SupabaseClientProvider`.
    - Fetch:
      `client.from(table).select(columns).eq("user_id", value: ownerID).gte("updated_at", value: cursor.timestampString).or(keysetFilter(after: cursor)).order("updated_at").order("id").limit(limit).execute()`.
      The `gte`/`or` filters are omitted when the cursor is nil. Decode with `RemoteRecordDecoder`
      from `response.data`.
    - Upsert:
      `client.from(table).upsert(rows, onConflict: "user_id,id", returning: .representation).select("id,updated_at").execute().value`.
    - `nonisolated static func keysetFilter(after: SyncCursor) -> String` returns
      `updated_at.gt."<ts>",and(updated_at.eq."<ts>",id.gt.<uuid lowercased>)`.
    - `nonisolated static func classify(_:) -> Error` maps errors as follows:
      - SQLSTATE `22*`/`23*` and HTTP 413 map to `.rejected`, like SupabaseLogUploader.swift:34-52.
      - `42501`, HTTP 401 and `PGRST301`/`PGRST302` map to `.unauthorized`.
      - Everything else is transient.
    - No SDK logger and no `print`.
12. `Services/AppLog.swift`.
    - New `LogEvent` cases: `syncCompleted = "sync.completed"`, `syncFailed = "sync.failed"`,
      `syncRowsSkipped = "sync.rows_skipped"`, `syncLinked = "sync.linked"`,
      `syncAccountMismatch = "sync.account_mismatch"`.
    - New `LogKey` cases: `trigger`, `pulled`, `pushed`, `skipped`, `reason`, `relink`.
13. `Services/BackgroundLogFlush.swift`. Add
    `static func run(name: String, begin: Begin? = nil, end: End? = nil, work: @escaping @MainActor () async -> Void) -> Task<Void, Never>`
    containing today's body (lines 20-37) with `work()` in place of `logger.flush()`.
    `start(logger:begin:end:)` becomes `run(name: "app-log-flush", …) { await logger.flush() }`,
    so behaviour is unchanged.
14. `Services/WordIdentityBackfill.swift`. When a row gets a fresh uuid (line 27), also set
    `word.serverUpdatedAt = nil`. The rollback path restores it.
15. `Services/FolderStore.swift`. Make `nameKey(_:)` (line 100) internal (`static func nameKey`) for
    S8. No behaviour change.
16. `Services/UITestFixtures.swift`.
    - Add the case `syncedVocabulary`: the same five words as `basicVocabulary`, with **fixed
      uuids** (`…0000000000a1`…`a5`; `kot` = a1, `dom` = a2).
    - For each row, `updatedAt = serverUpdatedAt =` its `createdAt` truncated to ms, so the rows
      are clean.
    - Expose `static let syncedWordIDs` for `UITestSyncState` to mirror on the server.
17. `Services/UITestLaunchConfiguration.swift`.
    - Add `static let syncKey = "UITEST_SYNC"` and `var sync: UITestSyncState = .empty`.
    - Parse it like `auth`, with `ParseError.unknownSyncState`. A sync value without a fixture
      implies `.empty`.

### Stores

18. **New `Stores/SyncStore.swift`.** `@MainActor @Observable final class SyncStore`.
    - Init:
      `init(engine: SyncEngine?, state: any SyncStateRepository, folders: FolderLibraryStore, achievements: AchievementStore?, logger: (any AppLogging)?, debounce: Duration = .seconds(5), foregroundInterval: TimeInterval = 30, now: @escaping () -> Date = Date.init)`.
    - Observable state:
      - `enum Status: Equatable { case unavailable, signedOut, idle, syncing, synced(Date), failed, accountMismatch }`;
      - `private(set) var status`;
      - `var isSyncing`;
      - `var canSyncNow`.
    - Entry points:
      - `accountDidChange(_ account: AuthAccount?)`:
        - nil cancels the debounce and the running cycle and sets `.signedOut`.
        - A different account than the linked one gives `.accountMismatch`, logs it and does
          not sync.
        - No link: `engine.link(to:)`, log `syncLinked` (`relink: false`), then a cycle.
        - The same account runs a cycle.
        - With no engine the status is `.unavailable`.
      - `confirmLinkToCurrentAccount()`: from `.accountMismatch` it runs `engine.link`, logs
        `syncLinked(relink: true)` and starts a cycle.
      - `localDataChanged()`: restarts the debounce task; the cycle runs when it fires.
      - `sceneDidBecomeActive()`: a cycle if signed in, linked, and the last start was at least
        `foregroundInterval` ago.
      - `syncNow()`: manual cycle with no throttle.
      - `syncBeforeLeaving() async`: waits for the running cycle, then runs one more cycle (pull
        then push, S14) and returns. Used for background and sign-out.
    - One `Task` at a time. A trigger during a run sets `needsFollowUp`, giving one extra cycle.
    - `@ObservationIgnored var onCycleSucceeded: (() -> Void)?` is called after each successful
      cycle. Only UI-test wiring sets it (item 8).
    - After each successful cycle:
      - if `report.foldersChanged`, `try? folders.load()` (Gap A);
      - if `report.vocabularyChanged`, `achievements?.recordNextUnlocksSilently(now:)` (S16).
    - Logging:
      - On success: `syncCompleted` with the trigger, `pulled` and `pushed`, only when a count is
        non-zero or the trigger is `link`/`manual`.
      - `syncRowsSkipped` with `reason` and `count`, once per reason per cycle.
      - On failure: `syncFailed` with the error domain/code and the trigger, logged only when it
        differs from the previous failure's domain/code.
      - Cancellation is never logged.
    - `var statusText: String` comes from a pure `static func text(for:)` (copy in item 25).
19. `Stores/AchievementStore.swift`.
    - Add `@ObservationIgnored private var quietUntil: Date?` and
      `func recordNextUnlocksSilently(now: Date = .now) { quietUntil = now.addingTimeInterval(10) }`.
    - In `sync(vocabulary:now:)` (lines 75-90): compute
      `let quiet = quietUntil.map { now < $0 } ?? false`. If `!ids.isEmpty`, consume it with
      `quietUntil = nil`. Use `let announce = didInitialSync && !quiet`.
    - Persisted format unchanged (`achievements.v1` untouched).
20. `Stores/AuthStore.swift`.
    - Add `@ObservationIgnored var onAccountChange: ((AuthAccount?) -> Void)?`, called in
      `start()` right after `self.state = newState` (line 61). The guard at line 59 means token
      refreshes never call it.
    - Add `@ObservationIgnored var beforeSignOut: (@MainActor () async -> Void)?`. `flushBounded()`
      (lines 107-114) runs it as a second group task next to `logger.flush()`, and the group waits
      until both finish or the 3 s timeout fires (count finished work tasks instead of the single
      `group.next()`).
21. `Stores/VocabularyStore.swift`, `Stores/FolderLibraryStore.swift`, `Stores/DailyStudyStore.swift`.
    - Add the init parameter `changeSignal: LocalChangeSignal? = nil`.
    - Call `changeSignal?.notify()` after every successful write:
      - VocabularyStore: lines 17-58;
      - FolderLibraryStore: `create`, `delete`, `rename`, `reorder` (lines 28-51);
      - DailyStudyStore: `review` and `recordPracticeAnswer` (lines 96-150), after
        `context.save()` succeeds.
    - Failures never notify.

### App wiring

22. `MojSlownik/MojSlownikApp.swift`.
    - Add `@State private var sync: SyncStore` and `.environment(sync)` on RootTabView (lines 47-53).
    - `.onChange(of: scenePhase)` (lines 56-60):
      - `.background`: also
        `BackgroundLogFlush.run(name: "sync") { await sync.syncBeforeLeaving() }`;
      - `.active`: `sync.sceneDidBecomeActive()`.
    - `AppResources` (lines 65-98):
      - New init parameter `syncRemote: (any SyncRemote)? = nil` and stored `let sync: SyncStore`.
      - One `LocalChangeSignal` is passed to the three stores.
      - Build `SyncStore(engine:…, state: stateRepo, folders: folders, achievements: achievements, logger: logger)`
        with `stateRepo = UserDefaultsSyncStateRepository(defaults: defaults)`.
      - Then set `changeSignal.handler`, `auth.onAccountChange` and
        `auth.beforeSignOut = { [weak sync] in await sync?.syncBeforeLeaving() }`.
      - `production()` passes `SupabaseSyncRemote(provider: supabase)`.
      - `unitTestHost()` and `preview` pass nil.
      - `uiTest` (lines 124-132) passes `configuration.sync.makeRemote(now:)` and calls
        `configuration.sync.seedState(into:now:)` on the wiped suite before the stores are built.

### Views

23. `MojSlownik/Views/AccountView.swift`.
    - Add `@Environment(SyncStore.self) private var sync`.
    - In `signedIn(_:)` (lines 106-143), between `accountCard` and «Выйти», add `syncCard` unless
      `sync.status == .unavailable`. The card has:
      - Header «Синхронизация» (`.subheadline.weight(.semibold)`, `appInk`).
      - A status row: a `ProgressView` while syncing. Text is `.footnote` `subtleText`, combined
        for accessibility, identifier `syncStatus`.
      - In `.failed`, the calm `Label(…, systemImage: "info.circle")` footnote (DESIGN.md §5
        Patterns).
      - «Синхронизировать сейчас» (`appAccentText`, min height 44, disabled while syncing,
        identifier `syncNowButton`), hidden in `.accountMismatch`.
      - In `.accountMismatch`: the explanation (identifier `syncMismatch`) and
        «Объединить словарь с этим аккаунтом» (identifier `syncMergeButton`), which opens
        `.confirmationDialog`:
        - title «Добавить слова и папки с этого iPhone в аккаунт?»;
        - message «Слова на устройстве останутся. Они появятся в этом аккаунте и на его других устройствах.»;
        - buttons «Объединить» (calls `sync.confirmLinkToCurrentAccount()`) and «Отмена».
    - `.cardStyle()`, `AppSpacing.m` padding, full width, wrapping at AX sizes.
    - Both previews inject `AppResources.preview.sync`.
24. `WordListView.swift:101`: no change (the environment is inherited).

### Copy (Russian; `SyncStore.text(for:)`)

25. The status lines:
    - `.idle` with no `lastSyncedAt`: «Ещё не синхронизировано»;
    - `.syncing`: «Синхронизация…»;
    - `.synced(d)`: «Синхронизировано: <d>», with `d` formatted
      `Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: "ru_RU"))`;
    - `.failed`: «Не удалось синхронизировать. Повторим позже.»;
    - `.accountMismatch`: «Словарь на этом iPhone связан с другим аккаунтом. Синхронизация выключена.».

### Database (new files only)

26. **New `supabase/migrations/<UTC timestamp after 20261118092306>_sync_server_timestamps.sql`.**
    Create the name with `supabase migration new sync_server_timestamps` if the CLI is available.
    Otherwise use the current UTC `YYYYMMDDHHMMSS`. The file contains, in order:
    - A header comment with the security model and the reasoning for `clock_timestamp()` plus the
      `+1 ms` floor.
    - `create schema if not exists private;`
      `revoke all on schema private from public, anon, authenticated;`
    - `create function private.set_server_updated_at() returns trigger language plpgsql security invoker set search_path = '' as $$ begin if tg_op = 'UPDATE' then new.updated_at := greatest(date_trunc('milliseconds', pg_catalog.clock_timestamp()), old.updated_at + interval '1 millisecond'); else new.updated_at := date_trunc('milliseconds', pg_catalog.clock_timestamp()); end if; return new; end $$;`
      followed by `revoke all on function private.set_server_updated_at() from public, anon, authenticated;`.
    - Normalize existing rows to ms precision, before creating the triggers:
      `update public.words set updated_at = date_trunc('milliseconds', updated_at) where updated_at <> date_trunc('milliseconds', updated_at);`
      and the same for folders.
    - `create trigger words_set_server_updated_at before insert or update on public.words for each row execute function private.set_server_updated_at();`
      and the same for folders.
    - `create index words_user_id_updated_at_id_idx on public.words (user_id, updated_at, id);`
      and `create index folders_user_id_updated_at_id_idx on public.folders (user_id, updated_at, id);`.
      Then `drop index public.words_user_id_updated_at_idx; drop index public.folders_user_id_updated_at_idx;`
      (the old ones come from 20261117230400_words_language_neutral.sql:44 and
      20261117224918_words_folders_rls.sql:46).
    - S10: `drop policy words_delete_own on public.words; drop policy folders_delete_own on public.folders;`
      `revoke delete, truncate, references, trigger on table public.words, public.folders from authenticated, anon;`
    - Column comments on `words.updated_at`/`folders.updated_at`: "Server-assigned (trigger
      private.set_server_updated_at), ms precision, strictly increasing per row; sync cursor."
27. **New `supabase/tests/sync_server_timestamps.sql`.** One `begin … rollback` block, with
    fixture users A and B as in rls_words_folders.sql. As A (`set local role authenticated`):
    - insert a word with `updated_at = '2100-01-01'`: the stored value is ≤ `clock_timestamp()`
      and equals its own `date_trunc('milliseconds', …)`;
    - two consecutive updates: `updated_at` strictly increases each time;
    - `insert … on conflict (user_id, id) do update set term = excluded.term, deleted_at = excluded.deleted_at`
      as A succeeds and clears `deleted_at` when given `null`;
    - an upsert with `user_id` = B raises `insufficient_privilege`;
    - `delete from public.words` and `truncate public.words` each raise `insufficient_privilege`,
      and the same for folders.

    As owner:
    - **Ties:** `set local session_replication_role = replica` (triggers off), insert 3 rows for A
      with an identical `updated_at` and 1 row at a later one, then
      `set local session_replication_role = origin`.
    - Then as A, the keyset query
      `where user_id = A and updated_at >= X and (updated_at > X or (updated_at = X and id > <first id>)) order by updated_at, id`
      returns the remaining tied rows in id order, then the later row.

    Privilege assertions (as owner):
    - `has_table_privilege('authenticated', 'public.words', 'DELETE')`, then `'TRUNCATE'`, then
      `'REFERENCES'`, then `'TRIGGER'` are all false, for words and folders;
    - the `anon` variants are false;
    - `has_schema_privilege('authenticated', 'private', 'usage')` and the `anon` variant are
      false;
    - `private.set_server_updated_at` is not SECURITY DEFINER;
    - triggers exist on both tables;
    - both `*_user_id_updated_at_id_idx` indexes exist;
    - no SECURITY DEFINER function exists in `public`.

    End with a `'sync_server_timestamps: all assertions passed'` row.
28. `supabase/tests/rls_words_folders.sql` (a test, not a migration).
    - Lines 86-92: B's deletes now expect `insufficient_privilege`. Wrap them like lines 34-41.
    - Lines 137-143: keep the soft delete. Replace the hard-delete success with an
      `insufficient_privilege` expectation.
    - Lines 190-192: the policy count is 8 → 6, and the message becomes "one policy each for
      select/insert/update".

### Docs

29. `AGENTS.md` line 4: "no synchronization yet" → "words and folders sync with the account
    (offline-first, see docs/architecture.md › Sync)".
30. `docs/architecture.md`:
    - Line 4: same change as AGENTS.md.
    - Application Map: Backend gains `SupabaseSyncRemote.swift`; Account and logs gains
      `Stores/SyncStore.swift`.
    - A new compact **Sync** section with S3-S9, S12, S14, S16, the wire mapping, cursor
      semantics, the conflict rule, linking and logging.
    - Backend Readiness: A and B closed; C open; D and G device-local by design (quiet unlocks
      after pulls); E and F accepted at word granularity; H: RLS and category done, pair
      uniqueness intentionally absent, mitigated by S8.
    - Achievements: note the quiet flag.
    - Tests and CI: mention `SyncFlowTests`.
31. `README.md`: no change.

## Reuse

- `RemoteRecordValidator` (incoming and outgoing), `RemoteRecordDecoder`, and `RemoteMergePolicy`
  (rewritten but kept as a pure seam).
- `Word.matches` normalization (extracted, not duplicated) and `FolderStore.nameKey`.
- `SupabaseClientProvider` and the `SupabaseLogUploader.classify` pattern.
- The isolated-context explicit-save and rollback pattern of ScanWordStore/FolderStore, and
  `WordIdentityBackfill.assignMissing`.
- `BackgroundLogFlush` (generalized), `AppLogging`/`logged`, `AppLog.isCancellation`, and the
  `AppLogQueue` batch-then-singles idea.
- `AchievementStore`'s existing silent path (`didInitialSync` semantics).
- `StaticAuthBackend`, `UITestLaunchConfiguration`, `UITestFixture`, `E2ETestCase`.
- Theme: `cardStyle`, `AppSpacing`, `subtleText`, `appInk`, `appAccentText`, and the calm error
  pattern. No new tokens or components.

## Data compatibility

- SwiftData:
  - Two additive optional properties, migrated automatically.
  - Existing rows read nil, so they are dirty and uploaded at the first link.
  - The sentinel (`Date.distantPast`) is only written by linking.
  - No rename, no removal. Tombstones stay.
  - Sync writes `updatedAt` = server time on synced rows; nothing in the UI reads `updatedAt`.
- UserDefaults: new key `sync.v1` only. `achievements.v1` and `dailyStudyActivity.v1` are
  byte-compatible; the quiet flag is in memory only. Daily-activity PersistentIdentifier keys
  survive because rows are modified in place, adoption included.
- Server:
  - The tables are expected to be empty. The migration's ms-normalization only touches existing
    rows.
  - The column set is unchanged.
  - Revoking DELETE/TRUNCATE affects no shipped client.
- Older app builds on other devices ignore the server.

## Verification

Run `xcodegen generate` after adding the files.

Unit tests (`MojSlownikUnitTests`; in-memory `ModelContainer`, `InMemorySyncRemote`, no network):
- `RemoteMergePolicyTests` (rewrite):
  - every S5 branch in order;
  - the sentinel with a newer or older remote → server wins (update, soft delete or
    acknowledge);
  - a tie with a real base → keepLocal;
  - no decision hard-deletes;
  - `localRecordState`/`isSyncDirty` from Word/WordFolder.
- `RemoteRecordValidatorTests`:
  - interior `\n`/`\t`/`\r` accepted, NUL and ESC still rejected;
  - 500 scalars accepted and 501 scalars rejected, using a combining-mark string whose
    grapheme count is lower;
  - `updatedAt` far ahead of a slow device clock accepted;
  - `createdAt` ahead of `now` but ≤ `updatedAt + skew` accepted;
  - `createdAt > max(now, updatedAt) + skew` rejected;
  - `updatedAt` before 2020 rejected.
  - Update `testRejectsImplausibleDates` for the new bounds.
- **New `SyncEngineTests`:**
  1. First link uploads all active words and folders with the exact S2 mapping (trimmed text,
     category stableID, `entered_language`).
  2. A local tombstone whose earlier push ack was lost (simulated by `nextError` after the server
     stored it) is uploaded as a tombstone in the next cycle; the server row ends up deleted.
  3. A never-synced tombstone is uploaded; nothing is created locally from tombstones.
  4. Pull inserts remote folders and words, and `foldersChanged`/`vocabularyChanged` are true.
  5. A second cycle requests `cursor.overlapping(60 000)` with `ownerID`, and re-fetched rows
     change nothing.
  6. 1 200 remote words sharing one `updated_at` all arrive through keyset paging.
  7. Remote newer and local clean gives an update; a remote tombstone soft-deletes, and the local
     row count is unchanged.
  8. Local dirty and remote newer: local is kept and then pushed.
  9. **Remote tombstone + dirty local edit in a background-triggered cycle** (via `run`, the only
     mode): local soft-deleted, nothing pushed with `deleted_at = null`, server still deleted.
  10. **Re-link sentinel:** a device with clean rows synced to account A links to B, where B has
      the same id with newer SRS. B's version wins locally and nothing stale is pushed. A row B
      lacks is uploaded. A row edited locally after the last sync keeps LWW (S5 branch 5).
  11. An edit made during a push (via `beforeAck`) keeps the row dirty and pushes it next.
  12. Content-invalid remote rows are skipped and counted, and the cursor advances.
      `foreignOwner` throws `untrustedResponse`: the page is not applied and the cursor is not
      saved.
  13. A legacy schedule is pushed clamped; the local row is unchanged.
  14. A 600-scalar word is not pushed, stays dirty and is counted.
  15. **A second-page failure:** page 1 is applied and its cursor saved; page 2 throws; page-2 rows
      are not applied; the next cycle resumes from the page-1 cursor.
  16. A second-batch push failure: batch 1 is marked synced, batch 2 stays dirty.
  17. `.rejected` on a batch isolates one bad row. That row lands in `rejected` and is not
      re-sent in the next cycle unless it is edited.
  18. Adoption for words (pair) and folders (name key, memberships rewritten), including the
      sentinel rows. Shape guard instead of a wall-clock bound: 2 000 unsynced local words plus
      2 000 matching remote rows produce 2 000 adoptions and no inserts. The internal test counter
      `SwiftDataSyncStore.adoptionIndexBuilds` increases by exactly 1 per `applyWords` call.
  24. **Held ids.** A remote word with an unsupported category (`"future_cat"`) and a local
      sentinel or nil row with the same id: the remote row is skipped and its id held, and the
      local row is not pushed in that cycle or the next. A capability bump clears `heldIDs` and
      re-pulls. A later supported version of the row is applied and the id leaves `heldIDs`.
  19. `run` with an unlinked owner throws `notLinked` with no request.
  20. A capability bump clears the cursors.
  21. Unknown remote folder ids are kept.
  22. A multi-line word round-trips.
  23. A remote pair in (ru term, pl translation) order maps correctly.
- **New `SwiftDataSyncStoreTests`:**
  - `prepareLink` gives the sentinel for clean, synced rows and nil for the rest;
  - `markPushed` sets both fields only when the snapshot matches;
  - a save failure leaves no partial change (failing-container approach from
    SaveFailureRestoreTests if applicable).
- **New `SyncStoreTests`** (debounce `.milliseconds(20)`, injectable `now`, real `SyncEngine` over
  `InMemorySyncRemote`, `AppLogSpy`):
  - nil account → `.signedOut`;
  - first account → link plus a cycle → `.synced`;
  - same account after a relaunch → no relink;
  - a different account → `.accountMismatch`, zero upserts, one mismatch log;
  - `confirmLinkToCurrentAccount` uploads;
  - three changes within the debounce → one cycle;
  - a trigger during a run → exactly one follow-up;
  - the foreground throttle;
  - `syncBeforeLeaving` pulls before pushing;
  - nil account mid-run cancels without a failure log;
  - repeated identical failures log once;
  - `folders.load()` is called when folders change;
  - `recordNextUnlocksSilently` is called only when `vocabularyChanged`;
  - `text(for:)` covers every status.
  - **AC-13:** run link, cycles, a failure and the mismatch path with seeded words, folder names,
    the account email and known uuids. Then every `AppLogSpy` entry's encoded properties must
    contain none of those strings, nor any uuid string.
- **`AchievementStoreTests`:**
  - after `recordNextUnlocksSilently`, an unlocking `sync` records the unlock with no
    `pendingAnnouncements` and no `achievement.unlocked` log;
  - the next unlocking `sync` announces normally (one-shot);
  - after 10 s the flag has expired;
  - a non-unlocking `sync` does not consume the flag.
- **New `SyncStateRepositoryTests`:** round trip; missing or corrupt data gives the default;
  partial JSON decodes with defaults.
- `SupabaseAdapterTests`:
  - upsert DTOs encoded with `PostgrestClient.Configuration.jsonEncoder` contain every key,
    with explicit nulls;
  - the exact `keysetFilter` string;
  - `SyncCursor.timestampString` exactness (`.999`, `.000`, and a decoded `.123`);
  - `classify` mappings;
  - constructing `SupabaseSyncRemote` does not create the client.
- `AuthStoreTests`: `onAccountChange` fires on sign-in and sign-out but not on a token-refresh
  repeat; `beforeSignOut` runs and is cut at the timeout together with the log flush.
- `VocabularyStoreTests`, `FolderLibraryStoreTests`, `DailyStudyStoreTests`: the change signal
  fires after successful writes only.
- `WordTests`: `matches` behaviour is unchanged; `syncPairKey` normalizes NFC, case and
  whitespace.
- `BackgroundLogFlushTests`: `run(name:work:)` ends exactly once on completion and on expiry.
- `LegacySchemaMigrationTests`: add a frozen `LegacySchemaV2` (the model at fc63812). It opens
  through `AppResources` with every row intact and `serverUpdatedAt == nil`.
- `WordIdentityBackfillTests`: a re-keyed duplicate gets `serverUpdatedAt = nil`.
- `UITestSupportTests`:
  - `UITEST_SYNC` parsing;
  - the `syncedVocabulary` fixture has the fixed uuids, the rows are clean, and they mirror
    `syncedThenRemoteChanges` exactly;
  - the `remoteVocabulary` seed contents and owner;
  - `linkedToOtherAccount` yields `.accountMismatch`;
  - the fixture names are pinned (update the pinned list).
- `AppLogTests`: the new events match the server pattern.

E2E (`MojSlownikE2E`, new `MojSlownikUITests/SyncFlowTests.swift`, dictionary shard by default).
`E2ETestCase.launch` gains `sync: SyncState? = nil`, mirroring `UITestSyncState`, and its
`Fixture` enum gains `syncedVocabulary`.
1. `testSignInDownloadsAccountWords`: `launch(.basicVocabulary, auth: .signedOut, sync: .remoteVocabulary)`.
   Sign in with Google; the sheet closes. `мост` and `сыр` appear in Словарь, `кот` appears once
   (S8), and «Из облака» is in the folder menu.
2. `testPulledUpdateAndDeleteChangeOpenDictionary`: `launch(.syncedVocabulary, auth: .signedIn, sync: .syncedThenRemoteChanges)`.
   Wait for `дом` and `кот`. Open the account sheet and **wait until `syncStatus` contains
   «Синхронизировано»**: the launch cycle has finished, so the changes are armed and the button is
   enabled. Wait until `syncNowButton` is enabled, tap it, and wait for «Синхронизировано» again.
   Close the sheet. In the same Словарь, with no
   relaunch, `дом` disappears and `котик` is shown. The cell count drops by one.
3. `testFailedSyncRecoversWithManualSync`: `launch(.basicVocabulary, auth: .signedIn, sync: .failsOnce)`.
   Open the account sheet: `syncStatus` contains «Не удалось синхронизировать». Tap
   `syncNowButton`: `syncStatus` contains «Синхронизировано».
4. `testOtherLinkedAccountAsksBeforeMerging`: `launch(.basicVocabulary, auth: .signedIn, sync: .linkedToOtherAccount)`.
   Wait for `syncMismatch` to exist, then check that `syncNowButton` is absent. Wait until
   `syncMergeButton` is enabled and tap it, then «Объединить». Wait until `syncStatus` contains
   «Синхронизировано».
5. Existing `AccountFlowTests` stay green with the default `empty` remote.

Database: `scripts/test-db.sh <empty Postgres URL>` (CI's postgres:17 runs as superuser, so
`session_replication_role` is allowed).

Build (zero warnings) and tests, with a device picked from `xcrun simctl list devices available`:
```sh
xcodegen generate
xcodebuild -project MojSlownik.xcodeproj -scheme MojSlownik -onlyUsePackageVersionsFromResolvedFile \
  -destination 'platform=iOS Simulator,name=<device>' build | grep -E 'error:|warning:|SUCCEEDED|FAILED'
xcodebuild -project MojSlownik.xcodeproj -scheme MojSlownikUnitTests -onlyUsePackageVersionsFromResolvedFile \
  -destination 'platform=iOS Simulator,name=<device>' test | grep -E 'error:|warning:|SUCCEEDED|FAILED|Executed'
xcodebuild -project MojSlownik.xcodeproj -scheme MojSlownikE2E -onlyUsePackageVersionsFromResolvedFile \
  -destination 'platform=iOS Simulator,name=<device>' test | grep -E 'error:|warning:|SUCCEEDED|FAILED|Executed'
scripts/check-secrets.sh
```

Orchestrator steps (not the implementer):
- apply the migration via MCP `apply_migration`;
- run both supabase/tests files via MCP `execute_sql` (each rolls back);
- run MCP `get_advisors` (security and performance), with fixes in a new migration.

Manual checks (physical iPhone, real project):
- Sign in and add a word; the row appears within about 5 s.
- A second device receives it on foreground.
- Edit in airplane mode, reconnect and foreground: the edit is pushed.
- Background right after an edit: the row is pushed.
- Delete on device A while B has an unsynced review; background B: the word stays deleted.
- Sign in with another account: the mismatch block appears, and «Объединить» uploads.
- The first sign-in with a large server vocabulary shows no achievement banners.
- Simulator screenshots of the account sheet (light, dark, AX5) for design approval (O11).

## Risks

- **Main-actor apply cost.** Pages of 500 are applied synchronously on the main actor. The first
  link with thousands of words may hitch briefly. Adoption is O(n) (S8), and unit test 18 guards
  regressions.
- **@Query freshness after saves from an isolated context.** It relies on the same SwiftData
  behaviour ScanWordStore depends on. E2E 1 and 2 guard the visible cases.
- **Whole-row conflicts (Gaps E and F).** Concurrent offline edits to the same word lose one
  device's change. "Delete wins" can delete a word the other device just reviewed; it is
  soft-deleted and stays in the store.
- **Residual delete race.** If A's delete commits between B's pull and B's push in the same
  cycle, B's push still restores the word. The window is one round trip; accepted.
- **Re-link sentinel.** A row synced earlier and then edited locally on this device keeps local
  precedence (LWW) in the new account. That is intended, but it means an old device can still
  win for rows it genuinely changed.
- **Tombstones grow** without a purge (Gap C).
- **Overlap window.** A transaction committing more than 60 s after its `clock_timestamp()` would
  be missed. PostgREST's statement timeout makes this practically impossible.
- **Trigger EXECUTE assumption.** Postgres does not check EXECUTE on trigger functions at fire
  time. If the DB test fails, drop the function revoke and keep the private schema.
- **`session_replication_role` on the hosted project.** If MCP `execute_sql` on Supabase refuses
  `set local session_replication_role`, run the tie block only in CI and skip it on the hosted
  run. The orchestrator notes this; the CI run is authoritative.
- **Quiet-unlock flag.** It may also silence a genuine local unlock that happens within 10 s
  after a pull. This is rare and only drops a banner, never the unlock.
- **Adoption re-keying.** It can clear an open folder selection (FolderPicker reconciles).
- **Account mismatch UX.** It depends on the confirmation copy; the default is to do nothing.
- **Session-scoped server rejection set.** A row the server keeps rejecting is retried once per
  app launch. This is bounded and logged without ids.

## Decisions (user, 2026-11-19)

Asked with AskUserQuestion; each answer chose the recommended option:
- **O1 → (a)** Sync words and folders (with progress and memberships); achievements and daily activity stay per device.
- **O2 → (a)** Different account on a linked device: pause sync, offer «Объединить» with confirmation.
- **O3 → (a)** Last device to sync wins, deletion beats a concurrent edit, every cycle pulls before it pushes.
- **O6 → (a)** Account sheet: status line, «Синхронизировать сейчас», mismatch block.

Not asked (recommended option adopted, consistent with the answers above): O4 (a), O5 (a), O7 (a),
O8 (a), O9 (a), O10 (a), O11 (a) (simulator screenshots go to the user), O12 (a).

## Open decisions (recommended option first)

- **O1 Sync scope.** (a) Words, folders and memberships only; achievements and daily activity stay
  per device (recommended). (b) Also sync achievements and daily activity, which needs Gaps D and
  G (a separate task).
- **O2 Signing in with a different account on a linked device.** (a) Pause sync and offer
  «Объединить» with confirmation; the account's existing versions win for unchanged rows
  (recommended). (b) Never sync until the original account signs in again. (c) Merge
  automatically (risk: A's words uploaded to B).
- **O3 True concurrent conflict.** (a) The last device to sync wins, but a deletion beats a
  concurrent edit; every cycle pulls before it pushes (recommended). (b) The last device to sync
  always wins, so an edit resurrects a deleted word. (c) The server always wins and unsynced
  local edits are discarded.
- **O4 SRS merge (Gap F).** (a) Whole row per O3 (recommended). (b) Field-group merge keeping the
  more advanced schedule.
- **O5 Duplicate pairs when an unsynced local word matches an incoming server word.** (a) Adopt
  the server row: one word, server progress, union of folders (recommended). (b) Keep both rows.
- **O6 Account sheet UI.** (a) Status line plus «Синхронизировать сейчас» plus the mismatch block
  (recommended). (b) Status line only (plus the mismatch block if O2 (a)). (c) No UI.
- **O7 Tombstone purge (Gap C).** (a) Out of scope (recommended). (b) Purge acknowledged local
  tombstones older than 90 days.
- **O8 Server deletes.** (a) Revoke DELETE, TRUNCATE, REFERENCES and TRIGGER and drop the delete
  policies; soft delete only (recommended). (b) Keep them.
- **O9 Multi-line words.** (a) Allow interior newline and tab so they sync (recommended). (b) Keep
  rejecting them; they never leave the device, and the skip is logged.
- **O10 Timing.** (a) 5 s debounce, 30 s foreground throttle, pull then push in every cycle,
  background and sign-out included (recommended). (b) Push-only for debounce, background and
  sign-out. That saves 2 GETs but breaks "delete wins" and adoption.
- **O11 Design approval for the sync card.** (a) No HTML mockup: it reuses existing patterns, and
  simulator screenshots go to the user before merge (recommended). (b) An HTML mockup first.
- **O12 Achievement banners after a pull.** (a) Record unlocks caused by pulled vocabulary
  silently, through a one-shot 10 s flag (recommended). (b) Show the banners as usual (a burst
  after the first sign-in).

## Revision log

- **Round 1 (plan-critic, 12 confirmed findings plus 1 minor).** All accepted:
  1. Dirty tombstones are always uploaded. Device time is never written into `serverUpdatedAt`
     (S3, S7, AC-2/AC-5, test 2/3).
  2. Every cycle pulls before pushing, background and sign-out included (S14, AC-6, test 9, O10).
  3. The re-link sentinel `.distantPast` makes the server win for previously clean rows (S5
     branch 2, S9, AC-8, test 10).
  4. Fetches filter by `user_id`. `foreignOwner` aborts without advancing. The device-clock upper
     bound is dropped for server `updated_at`, and the other bounds are relative to
     `max(now, updatedAt)` (S6, S12, AC-7, test 12).
  5. Quiet achievement unlocks after pulls (S16, item 19, AC-16, O12, AchievementStore tests).
  6. The `syncedVocabulary` fixture with fixed uuids, plus the `syncedThenRemoteChanges` remote
     with scripted second-cycle changes (E2E 2).
  7. AC-4 reworded; second-page and second-batch failure tests added (tests 15/16).
  8. TRUNCATE, REFERENCES and TRIGGER revoked too, with `has_table_privilege` assertions (S10,
     items 26/27).
  9. A redundant `updated_at gte` filter (S6, item 11).
  10. The DB tie test seeds rows as owner with `session_replication_role = replica` (item 27).
  11. The E2E manual sync uses a fail-once remote (E2E 3).
  12. Adoption through dictionaries built once per apply (S8, test 18).

  Minor: text length is counted in Unicode scalars, and the trimmed text is sent. Rows the server
  rejects go into a session-scoped set (S7).
- **Round 2 (plan-reviewer).** All accepted:
  1. E2E 2 and E2E 4 wait for the launch cycle and for an enabled button before tapping.
     Scripted server changes are armed by `SyncStore.onCycleSucceeded` after the first successful
     cycle, not by counting fetch calls.
  2. Ids of skipped remote rows are persisted in `SyncState.heldIDs` and excluded from push until
     they are applied or re-pulled (item 6, AC-7, test 24).
  3. `knownFolderIDs()` is the validator input (item 5).
  4. Test 18 asserts the algorithm's shape instead of wall-clock time. An explicit AC-13
     log-content test was added to SyncStoreTests.

## Approval

2026-11-19 — approved by user (AskUserQuestion: Approve).
