#[rustler::nif]
fn add(a: i64, b: i64) -> i64 {
    a + b + 1
}

rustler::init!("Elixir.LocalCents.ExAutomerge");
