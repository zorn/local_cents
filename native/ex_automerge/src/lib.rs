use automerge::transaction::CommitOptions;
use automerge::AutoCommit;
use autosurgeon::{hydrate, reconcile, Hydrate, Reconcile};
use rustler::{Binary, Env, NewBinary, NifMap};

#[derive(Reconcile, Hydrate, Clone, Debug, NifMap)]
pub struct Expense {
    pub description: String,
    pub amount: i64,
}

#[derive(Reconcile, Hydrate, Clone, Debug)]
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
    reconcile(&mut doc, &BookDoc::empty(name)).map_err(to_badarg)?;
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

#[rustler::nif]
fn rename<'a>(
    env: Env<'a>,
    doc_bytes: Binary,
    name: String,
    time: i64,
) -> Result<Binary<'a>, rustler::Error> {
    let mut doc = AutoCommit::load(doc_bytes.as_slice()).map_err(to_badarg)?;
    let mut state: BookDoc = hydrate(&doc).map_err(to_badarg)?;
    state.name = name;
    reconcile(&mut doc, &state).map_err(to_badarg)?;
    commit_at(&mut doc, time);
    Ok(binary_from_bytes(env, &doc.save()))
}

#[rustler::nif]
fn add_expense<'a>(
    env: Env<'a>,
    doc_bytes: Binary,
    description: String,
    amount: i64,
    time: i64,
) -> Result<Binary<'a>, rustler::Error> {
    let mut doc = AutoCommit::load(doc_bytes.as_slice()).map_err(to_badarg)?;
    let mut state: BookDoc = hydrate(&doc).map_err(to_badarg)?;
    state.expenses.push(Expense {
        description,
        amount,
    });
    reconcile(&mut doc, &state).map_err(to_badarg)?;
    commit_at(&mut doc, time);
    Ok(binary_from_bytes(env, &doc.save()))
}

#[rustler::nif]
fn list_expenses(doc_bytes: Binary) -> Result<Vec<Expense>, rustler::Error> {
    let doc = AutoCommit::load(doc_bytes.as_slice()).map_err(to_badarg)?;
    let state: BookDoc = hydrate(&doc).map_err(to_badarg)?;
    Ok(state.expenses)
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
