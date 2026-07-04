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

#[rustler::nif]
fn new_document<'a>(env: Env<'a>, name: String) -> Binary<'a> {
    let mut doc = AutoCommit::new();
    reconcile(&mut doc, &BookDoc::empty(name)).expect("reconcile empty BookDoc");
    binary_from_bytes(env, &doc.save())
}

#[rustler::nif]
fn document_name(doc_bytes: Binary) -> Result<String, rustler::Error> {
    let doc = AutoCommit::load(doc_bytes.as_slice()).map_err(to_badarg)?;
    let state: BookDoc = hydrate(&doc).map_err(to_badarg)?;
    Ok(state.name)
}

#[rustler::nif]
fn rename<'a>(env: Env<'a>, doc_bytes: Binary, name: String) -> Result<Binary<'a>, rustler::Error> {
    let mut doc = AutoCommit::load(doc_bytes.as_slice()).map_err(to_badarg)?;
    let mut state: BookDoc = hydrate(&doc).map_err(to_badarg)?;
    state.name = name;
    reconcile(&mut doc, &state).map_err(to_badarg)?;
    Ok(binary_from_bytes(env, &doc.save()))
}

#[rustler::nif]
fn add_expense<'a>(
    env: Env<'a>,
    doc_bytes: Binary,
    description: String,
    amount: i64,
) -> Result<Binary<'a>, rustler::Error> {
    let mut doc = AutoCommit::load(doc_bytes.as_slice()).map_err(to_badarg)?;
    let mut state: BookDoc = hydrate(&doc).map_err(to_badarg)?;
    state.expenses.push(Expense {
        description,
        amount,
    });
    reconcile(&mut doc, &state).map_err(to_badarg)?;
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
