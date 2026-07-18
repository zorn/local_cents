defmodule LocalCents.DemoSeeding do
  @moduledoc """
  Generates the first-run demo library — two editable Books a new user can explore
  or throw away.

  When LocalCents launches into an *empty* library, `LocalCentsWeb.LibraryLive`
  calls `create_books/1` to populate it with **Family Expenses** and **Business
  Expenses** — realistic Books spanning the trailing twelve months, so the app has
  something to look at (and the Category × Month Review has a canvas). There is no
  persisted "already seeded" flag: an empty library is the whole trigger, so
  deleting every Book and relaunching seeds again. That is a deliberate simplicity
  trade — the demos are starter content, not content the app insists on keeping.

  This module is a *consumer* of `LocalCents.Tracking`: it drives the same public
  API a user's clicks would (`create_book`, `add_category`, `add_expense`,
  `assign_category`), so the seeded data always matches the current schema and
  exercises real code paths rather than writing documents by hand. Its own
  top-level `Boundary` depends only on `LocalCents.Tracking` and exports nothing —
  it is an orchestrator, not a domain context (see
  [Module Boundaries](module-boundaries.html)).

  ## What the data looks like

  The content is produced by a small, deterministic template generator (no
  randomness — variation is derived from the month index), driven by an injectable
  reference `now`:

    * **Settled history** — every month from eleven months back through the current
      month carries categorized, priced expenses. Some categories recur monthly
      (Groceries, Housing); others are deliberately sporadic (Vacation, Tax
      Preparation), so the Review matrix shows real zeros and spikes rather than
      flat rows.
    * **A recent inbox** — a handful of *uncategorized* and *nil-cost* expenses in
      the current month, reading as freshly captured but not yet tidied, and
      exercising the Review's Uncategorized row and per-cell "needs amount" count.

  The Business Book expresses the app's old `client:*` tag idea with per-client
  categories (see [ADR 0005](0005-categories-not-tags.html)).

  Seeding runs synchronously and is **best-effort**: the calling LiveView wraps it
  so a failure degrades to a normal (possibly empty) library rather than crashing
  the window. Each Book is closed once seeded, so no `BookServer` lingers for a
  window the user never opened.
  """

  use Boundary, top_level?: true, deps: [LocalCents.Tracking]

  alias LocalCents.Tracking

  @doc """
  Creates the two demo Books, fully populated, and closes each when done.

  `now` is the reference time: it stamps every change (so each Book's `updated_at`
  is `now`) and anchors the trailing twelve-month window and the "current month"
  the inbox lands in. It defaults to the current time and is injectable so tests
  are deterministic.

  Returns `:ok` once both Books are seeded. Raising is left to the caller to guard
  (`LibraryLive` seeds best-effort) — this function does not itself trap errors.
  """
  @spec create_books(now :: DateTime.t()) :: :ok
  def create_books(now \\ DateTime.utc_now()) do
    today = DateTime.to_date(now)

    seed_book("Family Expenses", family_categories(), family_inbox(), now, today)
    seed_book("Business Expenses", business_categories(), business_inbox(), now, today)

    :ok
  end

  # Seeds one Book: create it, add its categories, fill the settled history filed
  # under those categories, then drop the recent (uncategorized) inbox on top. The
  # Book is closed in an `after` so no `BookServer` lingers even if seeding raises
  # partway (the caller seeds best-effort and will surface the error).
  defp seed_book(name, category_specs, inbox, now, today) do
    {:ok, book} = Tracking.create_book(name, now)

    try do
      category_ids =
        Map.new(category_specs, fn {category_name, _offsets, _pool} ->
          {:ok, category} = Tracking.add_category(book.id, %{name: category_name}, now)
          {category_name, category.id}
        end)

      for {category_name, offsets, pool} <- category_specs do
        seed_category(book.id, category_ids[category_name], offsets, pool, now, today)
      end

      seed_inbox(book.id, inbox, now, today)
    after
      Tracking.close_book(book.id)
    end
  end

  # Places one expense per entry in `offsets`, cycling through `pool` by position,
  # and files each under `category_id`.
  defp seed_category(book_id, category_id, offsets, pool, now, today) do
    offsets
    |> Enum.with_index()
    |> Enum.each(fn {offset, index} ->
      {description, cost} = Enum.at(pool, rem(index, length(pool)))
      date = seeded_date(today, offset, index)

      {:ok, expense} =
        Tracking.add_expense(book_id, %{date: date, description: description, cost: cost}, now)

      {:ok, _} = Tracking.assign_category(book_id, expense.id, category_id, now)
    end)
  end

  # Adds the current-month inbox: recently-captured expenses left Uncategorized,
  # some with no cost yet. Dated `today` so they read as just-entered.
  defp seed_inbox(book_id, inbox, now, today) do
    Enum.each(inbox, fn {description, cost} ->
      {:ok, _} = Tracking.add_expense(book_id, inbox_attrs(description, cost, today), now)
    end)
  end

  # A nil cost is left off entirely (the expense is genuinely unpriced), rather than
  # passed as nil — the changeset treats an absent and a nil cost the same, but this
  # keeps the intent explicit.
  defp inbox_attrs(description, nil, today), do: %{date: today, description: description}

  defp inbox_attrs(description, cost, today),
    do: %{date: today, description: description, cost: cost}

  # A stable day-of-month for a seeded expense, kept within 1..28 so it is valid in
  # every month. Varies by month offset and placement index so a category's rows
  # don't all land on the same day.
  defp seeded_date(today, offset, index) do
    day = rem(offset * 3 + index * 7, 28) + 1
    today |> month_start() |> shift_months(-offset) |> put_day(day)
  end

  defp month_start(%Date{year: year, month: month}), do: Date.new!(year, month, 1)

  # Shifts a first-of-month date by `amount` calendar months (negative = earlier).
  defp shift_months(%Date{year: year, month: month}, amount) do
    total = year * 12 + (month - 1) + amount
    Date.new!(div(total, 12), rem(total, 12) + 1, 1)
  end

  defp put_day(%Date{} = date, day), do: %Date{date | day: day}

  # --- Content ---------------------------------------------------------------
  #
  # Per-category placement recipes: which month offsets to seed and the line-item
  # pool to draw descriptions and costs from. Monthly staples cover all 12 offsets;
  # sporadic categories name specific offsets (e.g. Vacation clusters into one).

  @all_months Enum.to_list(0..11)
  @every_other [0, 2, 4, 6, 8, 10]

  defp family_categories do
    [
      {"Groceries", @all_months,
       [{"Costco", "184.50"}, {"Whole Foods", "96.20"}, {"Trader Joe's", "72.40"}]},
      {"Housing", @all_months, [{"Mortgage payment", "2150.00"}]},
      {"Utilities", @all_months,
       [{"Electric bill", "128.00"}, {"Water & sewer", "64.00"}, {"Internet", "80.00"}]},
      {"Transportation", @all_months, [{"Gas fill-up", "52.00"}, {"Parking", "18.00"}]},
      {"Dining Out", @every_other,
       [{"Pizza night", "38.00"}, {"Brunch", "54.00"}, {"Taco Tuesday", "29.50"}]},
      {"Entertainment", @every_other,
       [{"Streaming bundle", "31.00"}, {"Movie tickets", "44.00"}, {"Concert", "120.00"}]},
      {"Kids", @every_other,
       [
         {"Soccer registration", "90.00"},
         {"School supplies", "47.00"},
         {"Piano lessons", "110.00"}
       ]},
      {"Pet", @every_other,
       [{"Dog food", "62.00"}, {"Grooming", "55.00"}, {"Vet checkup", "140.00"}]},
      {"Healthcare", [1, 4, 9],
       [{"Pharmacy", "35.00"}, {"Copay", "40.00"}, {"Dentist", "180.00"}]},
      {"Clothing", [2, 7, 11],
       [{"Kids' shoes", "58.00"}, {"Winter coats", "160.00"}, {"Jeans", "72.00"}]},
      {"Car Maintenance", [3, 8], [{"Oil change", "68.00"}, {"New tires", "540.00"}]},
      # A tight-window spike: three expenses all in one summer month.
      {"Vacation", [5, 5, 5],
       [{"Beach rental", "1250.00"}, {"Flights", "880.00"}, {"Rental car", "310.00"}]}
    ]
  end

  defp family_inbox do
    [
      {"Farmers market", "38.50"},
      {"Amazon order", nil},
      {"Pharmacy pickup", "24.00"},
      {"Reimburse babysitter", nil}
    ]
  end

  defp business_categories do
    [
      {"Software & Subscriptions", @all_months,
       [
         {"GitHub", "21.00"},
         {"Figma", "15.00"},
         {"Fly.io hosting", "34.00"},
         {"Adobe CC", "59.99"}
       ]},
      {"Coworking Space", @all_months, [{"Indy Hall membership", "195.00"}]},
      {"Client: Meridian Health", @every_other,
       [{"Meridian — design assets", "140.00"}, {"Meridian — staging server", "45.00"}]},
      {"Client: Acme Corp", [0, 1, 2, 3, 4, 5],
       [{"Acme — API credits", "88.00"}, {"Acme — usability testing", "250.00"}]},
      {"Client: Blue Fox Studio", [6, 7, 8, 9],
       [{"Blue Fox — stock photos", "39.00"}, {"Blue Fox — font license", "99.00"}]},
      {"Office Supplies", @every_other,
       [{"Printer paper & ink", "62.00"}, {"Notebooks", "24.00"}, {"Desk organizer", "41.00"}]},
      {"Business Admin", [0, 3, 6, 9],
       [
         {"LLC registration fee", "125.00"},
         {"Business bank fees", "15.00"},
         {"Accounting software", "30.00"}
       ]},
      {"Hardware & Equipment", [2, 7],
       [{"27\" monitor", "329.00"}, {"Mechanical keyboard", "129.00"}]},
      # Annual spike near tax season.
      {"Tax Preparation", [3], [{"CPA — annual return", "650.00"}]}
    ]
  end

  defp business_inbox do
    [
      {"Client lunch — new lead", "62.00"},
      {"Domain renewal", nil},
      {"Conference ticket", "349.00"},
      {"USB-C hub", nil}
    ]
  end
end
