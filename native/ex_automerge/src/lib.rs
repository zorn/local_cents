use std::collections::BTreeSet;
use std::sync::Mutex;

use automerge::sync::{Message as SyncMessage, State as SyncState, SyncDoc};
use automerge::transaction::CommitOptions;
use automerge::{AutoCommit, Change, ChangeHash, ObjId, ObjType, ReadDoc, Value, ROOT};
use autosurgeon::{hydrate, Hydrate, Reconcile};
use rustler::{Binary, Env, NewBinary, NifMap, Resource, ResourceArc};

// Every carrier struct below (`Expense`, `Category`, `BookDoc`) derives the same
// four traits, which together let a plain Rust struct cross both the Automerge and
// the Elixir boundaries with no hand-written glue:
//
//   * `Reconcile` / `Hydrate` (autosurgeon) — the CRDT codec. `Reconcile` teaches
//     autosurgeon how to *write* the struct into an Automerge document (the write
//     half of `reconcile/3`); `Hydrate` how to *read* it back out (`decode/1`).
//   * `NifMap` (rustler) — bridges the struct to/from an Elixir map at the NIF
//     boundary, so Elixir sees `%{id: ..., name: ...}` and Rust sees the struct,
//     with field names becoming atom keys.
//   * `Clone` / `Debug` — ordinary Rust conveniences (copying state, test output).

// One expense as stored in a Book's Automerge document.
//
// `id` is an Elixir-generated UUID and is marked `#[key]` so `autosurgeon`
// reconciles the expenses list **by identity, not by position**. That is what
// makes edits and deletes merge cleanly across devices: deleting a middle expense
// removes exactly that element's object (rather than rewriting every following
// slot), and a concurrent edit to a different expense survives the merge. Without
// the key, autosurgeon cannot tell "inserted at the front" from "changed the first
// item" and rewrites objects in place, corrupting concurrent edits (see ADR 0015).
//
// `date` is an ISO-8601 calendar date string (e.g. "2026-07-11"); `cost` is an
// optional decimal string (e.g. "12.34"), `None`/absent when unknown — never
// defaulted to "0" (see ADRs 0008 and 0010). `category_id` is the stable `id` of
// the Category this expense is filed under, `None`/absent when Uncategorized (see
// ADR 0005). Referencing the Category by id (not by embedding it) is what lets a
// rename leave expenses untouched and a delete un-file them by nulling this field.
// All domain rules live in Elixir's `BookDocument`; this struct is a dumb data
// carrier.
#[derive(Reconcile, Hydrate, Clone, Debug, PartialEq, NifMap)]
pub struct Expense {
    #[key]
    pub id: String,
    pub date: String,
    pub description: String,
    pub cost: Option<String>,
    pub category_id: Option<String>,
}

// One category as stored in a Book's Automerge document: a stable `id` and a
// user-facing `name` (see ADR 0005). Like `Expense`, `id` is marked `#[key]` so
// autosurgeon reconciles the categories list **by identity, not by position** —
// deleting a middle category removes exactly that element and a concurrent rename
// of a different one survives the merge (same reasoning as ADR 0015). Expenses
// point at a category by this `id`, so a rename never has to touch them.
#[derive(Reconcile, Hydrate, Clone, Debug, NifMap)]
pub struct Category {
    #[key]
    pub id: String,
    pub name: String,
}

// The full decoded contents of a Book document: its name plus its categories and
// expenses. This is the plain data the Elixir side (`ExAutomerge.decode/1` /
// `ExAutomerge.reconcile/3`) exchanges with the functional core — Rust owns no domain
// logic, only the CRDT encoding (see ADR 0014).
#[derive(Reconcile, Hydrate, Clone, Debug, NifMap)]
struct BookDoc {
    name: String,
    categories: Vec<Category>,
    expenses: Vec<Expense>,
}

impl BookDoc {
    fn empty(name: String) -> Self {
        Self {
            name,
            categories: Vec::new(),
            expenses: Vec::new(),
        }
    }
}

fn binary_from_bytes<'a>(env: Env<'a>, bytes: &[u8]) -> Binary<'a> {
    let mut new_bin = NewBinary::new(env, bytes.len());
    new_bin.as_mut_slice().copy_from_slice(bytes);
    Binary::from(new_bin)
}

fn to_badarg<E>(_: E) -> rustler::Error {
    rustler::Error::BadArg
}

// Seals the pending operations into a change stamped with `time` (unix seconds),
// so the document's change history carries a "last updated" the Elixir side can
// read back. Automerge's core never defaults this value, so we always supply it;
// the clock is owned by Elixir (see `LocalCents.Tracking`). A no-op reconcile
// produces no operations, so `commit_with` adds no change and the timestamp does
// not advance — which is what we want.
fn commit_at(doc: &mut AutoCommit, time: i64) {
    doc.commit_with(CommitOptions::default().with_time(time));
}

#[rustler::nif]
fn new_document<'a>(env: Env<'a>, name: String, time: i64) -> Result<Binary<'a>, rustler::Error> {
    let mut doc = AutoCommit::new();
    autosurgeon::reconcile(&mut doc, BookDoc::empty(name)).map_err(to_badarg)?;
    commit_at(&mut doc, time);
    Ok(binary_from_bytes(env, &doc.save()))
}

#[rustler::nif]
fn document_name(doc_bytes: Binary) -> Result<String, rustler::Error> {
    let doc = AutoCommit::load(doc_bytes.as_slice()).map_err(to_badarg)?;
    let state: BookDoc = hydrate(&doc).map_err(to_badarg)?;
    Ok(state.name)
}

// Returns the unix-seconds timestamp of the most recent change in the document's
// history, or `None` (nil in Elixir) when no change carries a usable time.
//
// The value is derived from change metadata rather than a stored field so it
// reflects the *latest edit* after a CRDT merge, not the latest local write (see
// ADR 0012). We take the max across all changes and drop any `0`/unset stamps.
#[rustler::nif]
fn document_updated_at(doc_bytes: Binary) -> Result<Option<i64>, rustler::Error> {
    let mut doc = AutoCommit::load(doc_bytes.as_slice()).map_err(to_badarg)?;

    let latest = doc
        .get_changes(&[])
        .iter()
        .map(|change| change.timestamp())
        .filter(|&time| time > 0)
        .max();

    Ok(latest)
}

// Decodes a document's bytes into its plain domain contents (name + expenses) for
// the functional core to work on. This is the read half of the codec (see
// ADR 0014); it never mutates.
#[rustler::nif]
fn decode(doc_bytes: Binary) -> Result<BookDoc, rustler::Error> {
    let doc = AutoCommit::load(doc_bytes.as_slice()).map_err(to_badarg)?;
    let state: BookDoc = hydrate(&doc).map_err(to_badarg)?;
    Ok(state)
}

// Reconciles a whole new document state onto the prior bytes and returns the
// updated bytes. This is the single mutation path (write half of the codec,
// ADR 0014): the Elixir functional core computes `new_state` in domain terms — add,
// edit, delete an expense, or rename the Book — and hands it here to be reconciled
// onto the existing CRDT history.
//
// Loading the prior document first preserves the change history (so merges and
// `updated_at` keep working); `autosurgeon::reconcile` diffs the hydrated state
// against `new_state` and records only the minimal operations. `time` (unix
// seconds) stamps the resulting change. The document is never mutated in place — a
// new binary is returned.
#[rustler::nif]
fn reconcile<'a>(
    env: Env<'a>,
    prior_bytes: Binary,
    new_state: BookDoc,
    time: i64,
) -> Result<Binary<'a>, rustler::Error> {
    let mut doc = AutoCommit::load(prior_bytes.as_slice()).map_err(to_badarg)?;
    autosurgeon::reconcile(&mut doc, &new_state).map_err(to_badarg)?;
    commit_at(&mut doc, time);
    Ok(binary_from_bytes(env, &doc.save()))
}

// The scalar expense fields a concurrent edit can conflict on. `id` is excluded: it
// is the `#[key]`, so two writes to it describe two different expenses, not a
// conflict on one. A fixed list, rather than the object's live keys, so the summary
// reports the same fields even if the expense schema changes.
const EXPENSE_SCALAR_FIELDS: [&str; 4] = ["description", "date", "cost", "category_id"];

// The Elixir `t:conflict_value/0`: one value a field held after a merge, with its
// writing actor and change time. See that typedoc for the contract.
#[derive(NifMap)]
struct ConflictValue {
    value: Option<String>,
    device: String,
    time: Option<i64>,
}

// The Elixir `t:field_conflict/0`: a scalar conflict Automerge auto-resolved, as a kept
// value plus its losing alternatives. See that typedoc for the contract.
#[derive(NifMap)]
struct FieldConflict {
    expense_id: String,
    field: String,
    kept: ConflictValue,
    alternatives: Vec<ConflictValue>,
}

// The Elixir `t:edit_delete_conflict/0`: an expense present on one pre-merge side but
// dropped by a concurrent delete (see the #219 spike). Detection is the merge-time id
// diff, so it never depends on the orphaned edit staying reachable in the merged bytes.
#[derive(NifMap)]
struct EditDeleteConflict {
    expense_id: String,
    expense: Expense,
    device: String,
    time: Option<i64>,
}

// The Elixir `t:conflict_summary/0`: the two conflict groups `merge` returns beside the
// merged bytes. See that typedoc for the contract.
#[derive(NifMap)]
struct ConflictSummary {
    field_conflicts: Vec<FieldConflict>,
    edit_delete_conflicts: Vec<EditDeleteConflict>,
}

// One change's stamp of its ops: `device` (hex actor id) wrote the ops with counters
// `start_op ..< start_op + op_count`, all at `time`.
struct ChangeStamp {
    device: String,
    start_op: u64,
    op_count: u64,
    time: i64,
}

// Maps an operation's `(device, counter)` back to the wall-clock stamp of the change
// that carried it. Built once per document from its change history. This is how a
// conflicting value earns its provenance without the summary having to walk Automerge's
// op set field by field.
struct ProvenanceIndex {
    changes: Vec<ChangeStamp>,
}

impl ProvenanceIndex {
    fn build(doc: &mut AutoCommit) -> Self {
        let changes = doc
            .get_changes(&[])
            .iter()
            .map(|change| ChangeStamp {
                device: change.actor_id().to_hex_string(),
                start_op: change.start_op().get(),
                op_count: change.len() as u64,
                time: change.timestamp(),
            })
            .collect();

        Self { changes }
    }

    // The stamp of the change that wrote op `counter` by `device`, or `None` when the
    // change carries no usable (non-zero) time — matching `document_updated_at`'s rule
    // that a `0` stamp is "unset".
    fn time_of(&self, device: &str, counter: u64) -> Option<i64> {
        self.changes.iter().find_map(|change| {
            let in_change = change.device == device
                && change.start_op <= counter
                && counter < change.start_op + change.op_count;

            (in_change && change.time > 0).then_some(change.time)
        })
    }
}

// Splits an object id into the provenance a `ConflictValue` needs: the writing actor
// (hex) and the operation counter that identifies the write within that actor's stream.
// `ROOT` has no such provenance and never tags a scalar value, so it reads as empty.
fn value_provenance(id: &ObjId) -> (String, u64) {
    match id {
        ObjId::Id(counter, actor, _) => (actor.to_hex_string(), *counter),
        ObjId::Root => (String::new(), 0),
    }
}

// The live expenses of `doc` as `(expense id, object id)` pairs, in list order. The
// object id is what lets the conflict walk read a specific expense's fields with
// `get`/`get_all`, independent of how the list is ordered or how it merges.
fn expense_objects(doc: &AutoCommit) -> Result<Vec<(String, ObjId)>, rustler::Error> {
    let mut objects = Vec::new();

    let Some((Value::Object(ObjType::List), list)) =
        doc.get(ROOT, "expenses").map_err(to_badarg)?
    else {
        return Ok(objects);
    };

    for index in 0..doc.length(&list) {
        let Some((Value::Object(_), expense)) = doc.get(&list, index).map_err(to_badarg)? else {
            continue;
        };

        if let Some((value, _)) = doc.get(&expense, "id").map_err(to_badarg)? {
            if let Some(id) = value.to_str() {
                objects.push((id.to_string(), expense));
            }
        }
    }

    Ok(objects)
}

// Reads one scalar field of one expense and, if more than one concurrent value
// survives, returns the conflict: the winner (`get`, chosen by op id) as `kept` and the
// remaining values from `get_all` as `alternatives`. Returns `None` for the common case
// of a single value.
fn field_conflict(
    doc: &AutoCommit,
    provenance: &ProvenanceIndex,
    expense_id: &str,
    expense: &ObjId,
    field: &str,
) -> Result<Option<FieldConflict>, rustler::Error> {
    let all = doc.get_all(expense, field).map_err(to_badarg)?;

    if all.len() < 2 {
        return Ok(None);
    }

    let winner = doc.get(expense, field).map_err(to_badarg)?;
    let winner_id = winner.map(|(_, id)| id.to_bytes());

    let mut kept = None;
    let mut alternatives = Vec::new();

    for (value, id) in all {
        let (device, counter) = value_provenance(&id);
        let time = provenance.time_of(&device, counter);

        let conflict_value = ConflictValue {
            value: value.to_str().map(str::to_string),
            device,
            time,
        };

        if Some(id.to_bytes()) == winner_id {
            kept = Some(conflict_value);
        } else {
            alternatives.push(conflict_value);
        }
    }

    // `get_all` returned two or more values, so the winner is always among them.
    let kept = kept.ok_or(rustler::Error::BadArg)?;

    Ok(Some(FieldConflict {
        expense_id: expense_id.to_string(),
        field: field.to_string(),
        kept,
        alternatives,
    }))
}

// The most recent write to any scalar field of `expense` on the side that still holds
// it: its `(device, time)` provenance. Used to describe a dropped edit — the "who last
// touched this and when" the delete discarded. When no field write carries a usable
// time, `device` falls back to the actor that created the expense and `time` to `None`,
// so the device is always a real actor id.
fn latest_write(
    doc: &AutoCommit,
    provenance: &ProvenanceIndex,
    expense: &ObjId,
) -> Result<(String, Option<i64>), rustler::Error> {
    let mut latest: Option<(String, i64)> = None;

    for field in EXPENSE_SCALAR_FIELDS {
        let Some((_, id)) = doc.get(expense, field).map_err(to_badarg)? else {
            continue;
        };

        let (device, counter) = value_provenance(&id);

        if let Some(time) = provenance.time_of(&device, counter) {
            if latest.as_ref().is_none_or(|(_, best)| time > *best) {
                latest = Some((device, time));
            }
        }
    }

    match latest {
        Some((device, time)) => Ok((device, Some(time))),
        None => Ok((value_provenance(expense).0, None)),
    }
}

// Rebuilds the document as it stood at the fork point this side shares with the other
// participants in the merge — the common ancestor. The other side's changes are the ones
// the merged history carries that this side never had (`merged_changes` minus `side`). The
// deps of those changes that land back in this side's history are the heads at the last
// state both sides shared, so forking there yields every edit the deleter had already seen.
// When the two share no history (no such dep), the frontier is empty and the ancestor is a
// bare document — a conservative fallback that surfaces every drop rather than assume one
// was a plain delete.
fn fork_point(
    side: &mut AutoCommit,
    merged_changes: &[Change],
) -> Result<AutoCommit, rustler::Error> {
    let side_hashes: BTreeSet<ChangeHash> =
        side.get_changes(&[]).iter().map(Change::hash).collect();

    let other_hashes: BTreeSet<ChangeHash> = merged_changes
        .iter()
        .map(Change::hash)
        .filter(|hash| !side_hashes.contains(hash))
        .collect();

    let mut fork_heads: BTreeSet<ChangeHash> = BTreeSet::new();
    for change in merged_changes {
        if other_hashes.contains(&change.hash()) {
            for dep in change.deps() {
                if !other_hashes.contains(dep) {
                    fork_heads.insert(*dep);
                }
            }
        }
    }

    let fork_heads: Vec<ChangeHash> = fork_heads.into_iter().collect();
    side.fork_at(&fork_heads).map_err(to_badarg)
}

// The dropped edits contributed by one pre-merge side: expenses it still holds that are
// absent from the merged result (`merged_ids`), meaning the other side deleted them and
// the delete won. A drop counts as an edit-vs-delete conflict only when this side edited
// the expense concurrently with the delete — its fields differ from the shared ancestor
// (`fork_point`). An expense the delete dropped that this side left untouched since the
// fork is a plain one-sided delete and reconciles silently. Loads its own document so the
// side stays pristine — the merged doc has already collapsed these expenses away.
fn dropped_edits(
    side_bytes: &[u8],
    merged_ids: &BTreeSet<String>,
    merged_changes: &[Change],
) -> Result<Vec<EditDeleteConflict>, rustler::Error> {
    let mut doc = AutoCommit::load(side_bytes).map_err(to_badarg)?;
    let provenance = ProvenanceIndex::build(&mut doc);
    let state: BookDoc = hydrate(&doc).map_err(to_badarg)?;

    // The expenses this side still holds that the merge dropped. When none dropped there
    // is nothing to weigh, and reconstructing the fork point would be wasted — a linear
    // descendant leaves an empty frontier that forks to a bare, unhydratable document.
    let dropped: Vec<(String, ObjId)> = expense_objects(&doc)?
        .into_iter()
        .filter(|(id, _)| !merged_ids.contains(id))
        .collect();

    if dropped.is_empty() {
        return Ok(Vec::new());
    }

    let ancestor = fork_point(&mut doc, merged_changes)?;
    let ancestor_state: BookDoc = hydrate(&ancestor).map_err(to_badarg)?;

    let mut conflicts = Vec::new();

    for (expense_id, expense) in dropped {
        let Some(hydrated) = state.expenses.iter().find(|e| e.id == expense_id) else {
            continue;
        };

        // Untouched since the fork: the other side simply deleted it, nothing was lost.
        if let Some(ancestor_expense) = ancestor_state.expenses.iter().find(|e| e.id == expense_id)
        {
            if ancestor_expense == hydrated {
                continue;
            }
        }

        let (device, time) = latest_write(&doc, &provenance, &expense)?;

        conflicts.push(EditDeleteConflict {
            expense_id,
            expense: hydrated.clone(),
            device,
            time,
        });
    }

    Ok(conflicts)
}

// Reads the conflict summary out of a `merged` document given the pristine pre-merge
// `sides` it was built from. Shared by `merge` (two divergent siblings) and
// `conflict_summary` (a peer's prior document and the result of folding a sync message
// into it): the scalar-field conflicts come from the register the merged document
// already carries, so they read from `merged` alone, while an edit-vs-delete comes from
// an expense a `side` still holds that a concurrent delete dropped from the result. Each
// side is loaded separately from the merged target so its pristine state stays readable
// for the id diff (the #219 seam) and for provenance.
fn summarize_conflicts(
    merged: &mut AutoCommit,
    sides: &[&[u8]],
) -> Result<ConflictSummary, rustler::Error> {
    let provenance = ProvenanceIndex::build(merged);
    let merged_changes = merged.get_changes(&[]);

    let merged_objects = expense_objects(merged)?;
    let merged_ids: BTreeSet<String> = merged_objects.iter().map(|(id, _)| id.clone()).collect();

    // Scalar-field conflicts Automerge auto-resolved.
    let mut field_conflicts = Vec::new();
    for (expense_id, expense) in &merged_objects {
        for field in EXPENSE_SCALAR_FIELDS {
            if let Some(conflict) = field_conflict(merged, &provenance, expense_id, expense, field)?
            {
                field_conflicts.push(conflict);
            }
        }
    }

    // Edit-vs-delete: an expense a side still holds but gone from the merged result — the
    // other side deleted it and the delete won. `dropped_edits` surfaces one only when the
    // holding side edited it concurrently with the delete, not on a plain one-sided delete.
    let mut edit_delete_conflicts = Vec::new();
    for side in sides {
        edit_delete_conflicts.extend(dropped_edits(side, &merged_ids, &merged_changes)?);
    }

    Ok(ConflictSummary {
        field_conflicts,
        edit_delete_conflicts,
    })
}

// Merges two documents and reports what conflicted. Returns the combined bytes plus a
// plain-data `ConflictSummary` (see the type docs): the scalar-field conflicts Automerge
// auto-resolved, and the expenses a concurrent delete dropped an edit from. Both pristine
// pre-merge sides feed the summary so an edit-vs-delete is caught whichever side deleted.
#[rustler::nif]
fn merge<'a>(
    env: Env<'a>,
    left_bytes: Binary,
    right_bytes: Binary,
) -> Result<(Binary<'a>, ConflictSummary), rustler::Error> {
    let mut merged = AutoCommit::load(left_bytes.as_slice()).map_err(to_badarg)?;
    let mut right = AutoCommit::load(right_bytes.as_slice()).map_err(to_badarg)?;
    merged.merge(&mut right).map_err(to_badarg)?;

    let summary = summarize_conflicts(
        &mut merged,
        &[left_bytes.as_slice(), right_bytes.as_slice()],
    )?;

    Ok((binary_from_bytes(env, &merged.save()), summary))
}

// Reports what conflicted when a sync message was folded into a peer's document, given
// that document before (`prior_bytes`) and after (`merged_bytes`) the fold. The
// delta-based sync transport returns only the merged bytes, so this reads the summary
// back out of the before/after pair. Only the receiving peer's own prior side is
// available, so it surfaces the edits that peer would lose; the reciprocal drop is
// surfaced on the other peer when it folds in this peer's delete.
#[rustler::nif]
fn conflict_summary(
    prior_bytes: Binary,
    merged_bytes: Binary,
) -> Result<ConflictSummary, rustler::Error> {
    let mut merged = AutoCommit::load(merged_bytes.as_slice()).map_err(to_badarg)?;
    summarize_conflicts(&mut merged, &[prior_bytes.as_slice()])
}

// The per-peer sync state for the delta-based transport (ADR 0025), held across NIF
// calls as a Rustler resource rather than crossing the boundary as opaque bytes:
// `sync::State::encode` deliberately persists only the cross-session `shared_heads`
// and drops the in-session progress (which changes are in flight, what has already
// been sent), so round-tripping it through bytes between messages would make each
// peer re-send forever and the exchange would never settle. The resource lives for
// one connection; Elixir holds an opaque handle and mutates it in place through these
// NIFs. A reconcile is a loop of `generate_sync_message` / `receive_sync_message` on
// each side until both `generate` calls yield no message.
//
// The `Mutex` gives the interior mutability the sync API needs (`&mut State`); NIF
// calls on one handle are serialized by the owning process in practice, so the lock
// is uncontended but keeps the resource `Sync`.
struct SyncStateResource(Mutex<SyncState>);

#[rustler::resource_impl]
impl Resource for SyncStateResource {}

// Returns a fresh, empty per-peer sync state as an opaque handle. A peer creates one
// of these for each remote peer it reconciles with.
#[rustler::nif]
fn new_sync_state() -> ResourceArc<SyncStateResource> {
    ResourceArc::new(SyncStateResource(Mutex::new(SyncState::new())))
}

// Asks the document for the next sync message to send the peer that `state` tracks,
// returning the message (`None`/nil when there is nothing to send) and advancing the
// state handle in place. The message carries only the changes the remote is missing.
//
// `generate_sync_message` mutates only the sync state, not the document, but
// `AutoCommit::sync()` needs `&mut self` to close any pending transaction first —
// loading from saved bytes leaves none pending, so the document bytes are unchanged
// and are not returned.
#[rustler::nif]
fn generate_sync_message<'a>(
    env: Env<'a>,
    doc_bytes: Binary,
    state: ResourceArc<SyncStateResource>,
) -> Result<Option<Binary<'a>>, rustler::Error> {
    let mut doc = AutoCommit::load(doc_bytes.as_slice()).map_err(to_badarg)?;
    let mut state = state.0.lock().map_err(to_badarg)?;

    let message = doc.sync().generate_sync_message(&mut state);

    Ok(message.map(|message| binary_from_bytes(env, &message.encode())))
}

// Applies an inbound sync message to the document, folding in the changes it carries,
// and returns the updated document bytes. The `state` handle is advanced in place.
#[rustler::nif]
fn receive_sync_message<'a>(
    env: Env<'a>,
    doc_bytes: Binary,
    state: ResourceArc<SyncStateResource>,
    message_bytes: Binary,
) -> Result<Binary<'a>, rustler::Error> {
    let mut doc = AutoCommit::load(doc_bytes.as_slice()).map_err(to_badarg)?;
    let mut state = state.0.lock().map_err(to_badarg)?;
    let message = SyncMessage::decode(message_bytes.as_slice()).map_err(to_badarg)?;

    doc.sync()
        .receive_sync_message(&mut state, message)
        .map_err(to_badarg)?;

    Ok(binary_from_bytes(env, &doc.save()))
}

rustler::init!("Elixir.LocalCents.Tracking.ExAutomerge");
