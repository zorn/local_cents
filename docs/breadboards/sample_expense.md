# Sample Expenses

While we draw various UI mockups we will need some sample expenses to work with. The document we have in the current mockup is "Family Expenses" so here are some expenses that one might find in a typical family household, 2 adults and 2 kids (one boy and one girl).

| Date | Description | Cost | Tags | Notes |
|---|---|---|---|---|
| 2026-06-01 | Whole Foods grocery run | $127.43 | groceries, food | |
| 2026-06-01 | Electric bill | $142.67 | utilities | |
| 2026-06-01 | Netflix subscription | $22.99 | entertainment, subscriptions | |
| 2026-06-01 | Dog food (Blue Buffalo) | $52.99 | pets | |
| 2026-06-01 | Internet bill | $79.99 | utilities, subscriptions | |
| 2026-05-30 | Dinner at Olive Garden | $67.50 | dining | Family birthday dinner for grandma |
| 2026-05-29 | School supplies at Target | $34.21 | kids, school | End of year project supplies |
| 2026-05-28 | Summer soccer registration | $85.00 | kids, sports, activities | Jake's U10 league, runs June–August |
| 2026-06-02 | Gas fill-up | $58.34 | auto | |
| 2026-06-02 | Amazon order | $43.17 | household | Paper towels, dish soap, misc |
| 2026-06-03 | Piano lessons | $60.00 | kids, activities, music | Emma's monthly lesson fee |
| 2026-06-03 | Target run | $89.43 | household, clothing | |
| 2026-06-04 | Starbucks | $8.75 | dining, coffee | |
| 2026-05-31 | Pediatrician copay | $30.00 | health, medical | Jake's annual checkup |
| 2026-06-05 | Birthday gift for classmate | $25.00 | kids, gifts | Gift card for Emma's friend Maya |

## Quick Add Examples

We will offer a single line input field that allow the user to type in quick descriptions and we will figure it out and make the best expense we can. 

Some sample quick add entries we should support:

| Input | Description | Cost | Date | Notes |
|---|---|---|---|---|
| `bagel 3.50` | bagel | $3.50 | today | |
| `coffee 4.75` | coffee | $4.75 | today | |
| `gas $58` | gas | $58.00 | today | |
| `lunch with client 23.50` | lunch with client | $23.50 | today | |
| `groceries 127` | groceries | $127.00 | today | |
| `dentist` | dentist | _(none — draft)_ | today | Missing cost, flagged incomplete |
| `$12 pizza` | pizza | $12.00 | today | Amount-first format |
| `netflix 22.99 yesterday` | netflix | $22.99 | yesterday | Relative date hint |

**Design notes:**

- Amount can appear before or after the description
- Dollar sign is optional
- If no amount is found, the expense is saved as a draft (incomplete)
- Relative date words ("yesterday", "today") can optionally shift the date
- Tags are not expected in quick add — the user can enrich them in the full edit view after capture

## Sample Tagging

For the business demo we could show tags like `client:foo` and `client:bar`.
