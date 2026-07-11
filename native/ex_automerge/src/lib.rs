use automerge::transaction::CommitOptions;
use automerge::AutoCommit;
use autosurgeon::{hydrate, Hydrate, Reconcile};
use rustler::{Binary, Env, NewBinary, NifMap};

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
// defaulted to "0" (see ADRs 0008 and 0010). All domain rules live in Elixir's
// `BookDocument`; this struct is a dumb data carrier.
#[derive(Reconcile, Hydrate, Clone, Debug, NifMap)]
pub struct Expense {
    #[key]
    pub id: String,
    pub date: String,
    pub description: String,
    pub cost: Option<String>,
}

// The full decoded contents of a Book document: its name plus its expenses. This
// is the plain data the Elixir side (`ExAutomerge.decode/1` /
// `ExAutomerge.reconcile/3`) exchanges with the functional core — Rust owns no domain
// logic, only the CRDT encoding (see ADR 0014).
#[derive(Reconcile, Hydrate, Clone, Debug, NifMap)]
struct BookDoc {
    name: String,
    expenses: Vec<Expense>,
}

impl BookDoc {
    fn empty(name: String) -> Self {
        Self {
            name,
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
    autosurgeon::reconcile(&mut doc, &BookDoc::empty(name)).map_err(to_badarg)?;
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

#[rustler::nif]
fn merge<'a>(
    env: Env<'a>,
    left_bytes: Binary,
    right_bytes: Binary,
) -> Result<Binary<'a>, rustler::Error> {
    let mut left = AutoCommit::load(left_bytes.as_slice()).map_err(to_badarg)?;
    let mut right = AutoCommit::load(right_bytes.as_slice()).map_err(to_badarg)?;
    left.merge(&mut right).map_err(to_badarg)?;
    Ok(binary_from_bytes(env, &left.save()))
}

rustler::init!("Elixir.LocalCents.Tracking.ExAutomerge");
