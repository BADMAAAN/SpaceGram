# SpaceGram History storage V2 (V1 compatible)

This standalone module reserves **1009** (`1000 + 9`) as a SpaceGram-local,
application-specific Postbox ordered collection. It is not an upstream allocation.
Keep this reservation unique when rebasing or adding collections. The literal
avoids importing TelegramCore's application-specific collection helper.

Collection **1010** is a separate bounded received-message inbox (at most 1,000
snapshots, 256 KiB each). It records current text/entities/media metadata from
Postbox writes without an open chat. These are not edit revisions. MediaBox
availability observers restore pending resource associations from it on launch.
Clearing the archive also clears this inbox. Incoming messages do not evict the
saved edit/delete collection. Both collections are isolated by account Postbox.

Each account owns its Postbox and archive. One entry identifies one message:
16 bytes, packed `PeerId.toInt64()` (8), message namespace (4), message id (4),
all signed two's-complement, big-endian. Account and thread are excluded.
Example `(0x0102030405060708, -1, 42)`:
`0102030405060708ffffffff0000002a`.

`CodableEntry.data` contains UTF-8 JSON encoded by Foundation, with required
`version: 1` or `2`, `key`, `revisions`, `events`, and `nextRevision`, plus optional
`threadId`. Use this store's decoder, not `CodableEntry.get`, which expects
Postbox's own encoding. Optional fields may be absent; required fields must be
present. Unknown JSON fields are ignored. Unknown schema versions and enum
values fail explicitly; future incompatible changes need a version migration.
Identifiers stay Int64/Int32 throughout Swift decoding (no Double conversion).

Revisions contain caller-supplied OLD snapshots, including server edit time,
text, UTF-16 entities, author, original timestamp, optional forward/reply/thread
metadata, and descriptive media metadata. Metadata dictionaries contain only
strings: use stable named fields and decimal strings for identifiers/timestamps.
Media dimensions are pixels, duration seconds and size bytes. Resource/file
identifiers must be descriptive, not credentials or downloadable payloads.
This Postbox module stores no binary bytes. V2 events optionally reference
independent Media Archive assets; retention can evict them without changing the
text record. See ../MEDIA_ARCHIVE_AUDIT.md.

Events preserve the supplied type/source/reason without inferring server or
local intent. `revisionNumber` is an optional reference that can outlive an
evicted revision. A future caller can append a snapshot and a delete event in
one Postbox transaction. These helpers do not install hooks or mutate Telegram
history. Callers handle thrown errors; throwing does not roll back earlier
operations in a Postbox transaction.

Record limits (unchanged from V1): 1,000 archived messages, newest 20 revisions and 100 events per
message, and 262,144 bytes of JSON per record. Upsert trims oldest array entries,
then evicts additional oldest revisions and events to fit the byte cap, keeping
at least the newest revision and event when present. If those still exceed the
cap, the write fails before mutation (no silent text truncation).
Successful writes move the record to the front and evict the collection tail
on insertion. Maximum record payload total is approximately 250 MiB, excluding
Postbox overhead. This bounds logical archive contents, not database file size.
Revision numbering starts at 1 and stays increasing across trimming; removing
a record resets its numbering if later recreated. Upsert replaces the record;
use append helpers for read-modify-write semantics.

Archive reads return the complete bounded list in last-write order because
Transaction exposes a full-list API. Corrupt entries fail reads explicitly;
remove-by-key and clear remain available without decoding.

The browser may use read-only `listRecords(transaction:)` to decode each entry
independently. It returns valid records in stored order and an `unreadableCount`
for explicit partial-read reporting, without repairing or removing failed entries.
`load(transaction:key:)` remains the throwing single-record read API. The
existing strict `readArchive` error contract is unchanged. V1 records are read
without mutation and upgraded to V2 on their next successful upsert. Optional
`mediaCaptureId` and `mediaAssetIds` decode as nil when absent; future versions
are rejected. The new `mediaArchive` reason describes capture, not deletion.
Media links are attached only after successful copying, matched by a unique
capture token to avoid attaching stale jobs to recreated records.

Bazel target: `//SpaceGram/HistoryStorage:SpaceGramHistoryStorage`. Foundation is
an SDK import; Postbox is the sole Bazel dependency. No TelegramCore dependency,
app wiring, UI or hooks are included in this storage module.
