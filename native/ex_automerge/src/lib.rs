use automerge::transaction::CommitOptions;
use automerge::AutoCommit;
use autosurgeon::{hydrate, Hydrate, Reconcile};
use rustler::{Binary, Env, NewBinary, NifMap};

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
#[derive(Reconcile, Hydrate, Clone, Debug, NifMap)]
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

// ---------------------------------------------------------------------------
// Regression test locking in how Automerge merges a concurrent edit-vs-delete
// of the same expense. Our conflict handling depends on this exact behavior, so
// the test fails loudly if a future `automerge`/`autosurgeon` bump changes it.
// It reuses the real `BookDoc` / `Expense` structs so it exercises our actual
// list-of-map-objects modeling, not a toy. Background and rationale:
// `docs/research/automerge-edit-vs-delete.md` (issues #213 / #219).
//
// Two properties are pinned:
//   1. When one actor edits an expense field and another deletes the expense
//      concurrently, the delete wins — the expense is gone from the live list
//      and from `hydrate` (the read path `decode/1` uses); the edit does not
//      resurrect it.
//   2. The dropped edit survives as an orphaned object, reachable via the
//      expense's `ObjId` (`get_all`) and in `get_changes()`, but NOT via
//      `iter()` (a root-anchored tree walk). This is what makes a merge-time
//      diff — not a post-merge `iter()` scan — the viable way to surface it.
// ---------------------------------------------------------------------------
#[cfg(test)]
mod automerge_merge_behavior {
    use super::{BookDoc, Category, Expense};
    use automerge::{ActorId, AutoCommit, ReadDoc, Value, ROOT};

    fn expense(description: &str) -> Expense {
        Expense {
            id: "exp-1".to_string(),
            date: "2026-08-08".to_string(),
            description: description.to_string(),
            cost: Some("12.34".to_string()),
            category_id: None,
        }
    }

    fn book_with(expenses: Vec<Expense>) -> BookDoc {
        BookDoc {
            name: "Test Book".to_string(),
            categories: Vec::<Category>::new(),
            expenses,
        }
    }

    // The common ancestor: a book with one expense, saved to bytes, exactly as
    // `new_document` + `reconcile` would produce it.
    fn ancestor_bytes() -> Vec<u8> {
        let mut doc = AutoCommit::new().with_actor(ActorId::from(b"actor-ancestor".to_vec()));
        autosurgeon::reconcile(&mut doc, book_with(vec![expense("original description")])).unwrap();
        doc.save()
    }

    #[test]
    fn edit_vs_delete_merge_lets_the_delete_win_but_keeps_the_orphaned_edit() {
        let ancestor = ancestor_bytes();

        // Edit side: change the expense's description in place.
        let mut edit_doc = AutoCommit::load(&ancestor)
            .unwrap()
            .with_actor(ActorId::from(b"actor-edit".to_vec()));
        autosurgeon::reconcile(
            &mut edit_doc,
            book_with(vec![expense("EDITED ON DEVICE B")]),
        )
        .unwrap();

        // Capture the expense object's ObjId *before* the merge, while it is still
        // reachable via the live list, so the ExId stays valid in `edit_doc` (the
        // doc that becomes the merged result).
        let expenses_list = edit_doc
            .get(ROOT, "expenses")
            .unwrap()
            .expect("expenses list present")
            .1;
        let (elem_value, expense_objid) = edit_doc
            .get(&expenses_list, 0)
            .unwrap()
            .expect("expense element present pre-merge");
        assert!(
            matches!(elem_value, Value::Object(_)),
            "expense is a map object"
        );

        // Delete side: remove the expense entirely.
        let mut delete_doc = AutoCommit::load(&ancestor)
            .unwrap()
            .with_actor(ActorId::from(b"actor-delete".to_vec()));
        autosurgeon::reconcile(&mut delete_doc, book_with(vec![])).unwrap();

        edit_doc.merge(&mut delete_doc).unwrap();

        // Property 1: the delete wins, in the live list and via hydrate.
        let merged_list = edit_doc.get(ROOT, "expenses").unwrap().unwrap().1;
        assert_eq!(
            edit_doc.length(&merged_list),
            0,
            "delete wins: expense gone from the live list"
        );
        let hydrated: BookDoc = autosurgeon::hydrate(&edit_doc).unwrap();
        assert_eq!(
            hydrated.expenses.len(),
            0,
            "delete wins: decode/1's hydrate path sees no expense"
        );

        // Property 2a: the dropped edit is still reachable via the orphan's ObjId.
        let via_get_all: Vec<String> = edit_doc
            .get_all(&expense_objid, "description")
            .unwrap()
            .into_iter()
            .filter_map(|(v, _)| v.to_scalar().and_then(|s| s.to_str().map(String::from)))
            .collect();
        assert_eq!(
            via_get_all,
            vec!["EDITED ON DEVICE B".to_string()],
            "get_all on the orphan ObjId still returns the dropped edit"
        );

        // Property 2b: iter() (a root-anchored tree walk) does NOT surface the orphan.
        let orphan_id = expense_objid.to_string();
        let orphan_in_iter = edit_doc
            .iter()
            .any(|item| item.obj.to_string() == orphan_id);
        assert!(
            !orphan_in_iter,
            "iter() is a root tree walk and must not surface the orphaned expense"
        );

        // Property 2c: the dropped edit's op survives in change history.
        let found_in_changes = edit_doc.get_changes(&[]).iter().any(|change| {
            change.decode().operations.iter().any(|op| {
                matches!(
                    op.primitive_value(),
                    Some(automerge::ScalarValue::Str(s)) if s.as_str() == "EDITED ON DEVICE B"
                )
            })
        });
        assert!(
            found_in_changes,
            "the dropped edit survives in change history (get_changes)"
        );
    }
}
