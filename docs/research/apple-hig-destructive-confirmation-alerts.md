# Apple HIG Guidance for Destructive-Action Confirmation Alerts

> Research note feeding [issue #66](https://github.com/zorn/local_cents/issues/66) — grounding the copy and button titles for the "delete category" confirmation dialog.
> Every non-obvious claim below is linked to a primary, first-party Apple source: the current [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/) ("Alerts" and "Buttons" component pages), and — for the historic material the issue specifically asked about — Apple's own published book, *Macintosh Human Interface Guidelines* (© 1992 Apple Computer, Inc.; Addison-Wesley), read from the scanned PDF hosted at [vintageapple.org](https://vintageapple.org/inside_r/pdf/Human_Interface_Guidelines_1992.pdf). Page numbers cited below are the book's printed page numbers. **No secondary sources, UX blogs, or SEO listicles were used as authorities** — the vintageapple.org copy is used only as a faithful scan of Apple's own first-party text.

## Context for LocalCents

Deleting a user-created **Category** (a single-field entity) does not destroy the affected expenses; per issue #66 it un-files them to "Uncategorized." So the destructive consequence is narrow: the Category itself is gone, and its expenses lose that association. This is a *deliberately chosen* destructive action (the user clicked something like "Delete" to get here), which — as shown below — matters to how Apple says the confirmation should behave.

---

## 1. Alert message / title wording

**Current HIG (Alerts).** Apple wants the title to carry the substance:

- "Write a title that clearly and succinctly describes the situation." You should "describe what happened, the context in which it happened, and why," and avoid empty titles "like 'Error' or 'Error 329347 occurred'" as well as titles longer than two lines. — [Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts)
- Tone: "In all alert copy, be direct, and use a neutral, approachable tone," and "avoid being oblique or accusatory, or masking the severity of the issue." — [Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts)
- The body ("informative text") is optional: "Include informative text only if it adds value," and if present "keep it as short as possible, using complete sentences, sentence-style capitalization, and appropriate punctuation." — [Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts)
- Capitalization/punctuation of the title depends on grammar: "If the title is a complete sentence, use sentence-style capitalization and appropriate ending punctuation. If the title is a sentence fragment, use title-style capitalization, and don't add ending punctuation." — [Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts). (A question — e.g. "Delete the 'Groceries' category?" — is a complete sentence, so it takes sentence-style caps and a question mark.)
- Don't spend body text narrating the buttons: "Avoid explaining alert buttons. If your alert text and button titles are clear, you don't need to explain what the buttons do." — [Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts)

**Naming the specific object / stating the consequence.** Apple does not literally command "name the object," but its two governing rules — *be "complete and specific"* about "what happened, the context … and why," and make button titles "understandable out of context" (§2) — jointly imply naming the object and stating the consequence in the copy. The classic book is more explicit that the surrounding wording must make the outcome clear (see §4).

**On the title being a question.** Apple's own alert examples across platforms are routinely phrased as questions ("Delete this photo?"), and the fragment-vs-sentence rule above explicitly anticipates a title that is "a complete sentence" with "ending punctuation," which covers the question form. The HIG does not *mandate* the question form; it mandates that the title be specific and situation-describing.

## 2. Action button titles

**Current HIG.** Apple is emphatic that buttons should be verbs describing the result, not generic acknowledgements:

- "Create succinct, logical button titles. Aim for a one- or two-word title that describes the result of selecting the button. Prefer verbs and verb phrases that relate directly to the alert text — for example, 'View All,' 'Reply,' or 'Ignore.'" — [Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts)
- Generic "OK" is discouraged for anything but pure information: "In informational alerts only, you can use 'OK' for acceptance, avoiding 'Yes' and 'No.'" and "Avoid using OK as the default button title unless the alert is purely informational." — [Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts)
- The rationale is explicitly about out-of-context legibility: "The meaning of 'OK' can be unclear even in alerts that ask people to confirm … does 'OK' mean 'OK, I want to complete the action' or 'OK, I now understand the negative results …'? A specific button title like 'Erase,' 'Convert,' 'Clear,' or 'Delete' helps people understand the action they're taking." — [Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts)
- Cancel is a fixed word: "Always use 'Cancel' to title a button that cancels the alert's action." — [Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts)
- Capitalization: "use title-style capitalization and no ending punctuation." — [Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts)

The general [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons) page reinforces the verb-first rule: "Using title-style capitalization, consider starting the label with a verb to help convey the button's action — for example … 'Add to Cart.'" and "Ensure that each button clearly communicates its purpose."

**Ordering / default.** "Place buttons where people expect. In general, place the button people are most likely to choose on the trailing side in a row … Always place the default button on the trailing side of a row or at the top of a stack. Cancel buttons are typically on the leading side of a row or at the bottom of a stack." — [Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts)

## 3. Destructive actions specifically

**Current HIG — the destructive button should not be the default, and gets a distinct (red) role.**

- From [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons): "Don't assign the primary role to a button that performs a destructive action, even if that action is the most likely choice. Because of its visual prominence, people sometimes choose a primary button without reading it first. Help people avoid losing content by assigning the primary role to nondestructive buttons." And on styling: "a primary button uses an app's accent color, whereas a destructive button uses the system red color."
- From [Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts): "If there's a destructive action, include a Cancel button to give people a clear, safe way to avoid the action."

**The important nuance — a *deliberately chosen* destructive action is treated differently.** Apple carves out the exact situation LocalCents is in (the user clicked "Delete," then a confirmation appears):

> "Use the destructive style to identify a button that performs a destructive action people didn't deliberately choose. For example, when people deliberately choose a destructive action — such as Empty Trash — the resulting alert doesn't apply the destructive style to the Empty Trash button because the button performs the person's original intent. In this scenario, the convenience of pressing Return to confirm the deliberately chosen Empty Trash action outweighs the benefit of reaffirming that the button is destructive. In contrast, people appreciate an alert that draws their attention to a button that can perform a destructive action they didn't originally intend." — [Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts)

So Apple's own guidance offers two defensible patterns for a delete-confirmation:
- **(a) Deliberate-intent / Empty Trash pattern** — the confirm button carries the person's original intent, so it may be the default (Return-confirmable) and need *not* wear the destructive red style.
- **(b) Extra-caution pattern** — treat Delete as destructive: red role, *not* the default, Cancel is the safe escape. This is the safer reading when the action is easy to trigger accidentally.

## 4. Historic guidance — *Macintosh Human Interface Guidelines* (Apple, 1992)

The classic book already contains, essentially verbatim in spirit, every rule the modern HIG states — the guidance has been remarkably stable for 30+ years.

**Verb-named buttons over Yes/No/OK.**
- "Whenever possible, name a button with a verb that describes the action that it performs. Button names should be limited to one word whenever possible. You should never use more than three words for a button name. Use the caps/lowercase style of capitalization for button names." (Controls, p. 206.)
- "Names such as Save, Quit, and Erase Disk allow users to identify and click the correct button quickly. These words are often more clear and precise than names such as OK, Yes, and No. If the action can't be condensed into a word or two, OK and Cancel or Yes and No may serve the purpose. If you use these generic words, be sure to phrase the wording in the dialog box so that the action the button initiates is clear." (Controls, p. 206.)
- On the Save-changes alert: "The buttons read Save, Don't Save, and Cancel. Using these verbs reinforces the identity of each possible action to the user. In other words, Don't Save provides much more context for the user than No does." (Menus, ~p. 102.)

**Do not make a dangerous action the default button.**
- "The default button should be the button that represents the action that the user is most likely to perform if that action isn't potentially dangerous." (Controls, p. 205.)
- "Don't use a default button if the most likely action is dangerous — for example, if it causes a loss of user data. When there is no default button, pressing Return or Enter has no effect; the user must explicitly click a button. This guideline protects users from accidentally damaging their work by pressing Return or Enter. You can consider using a safe default button, such as Cancel." (Controls, p. 205.)

**Always provide Cancel; button placement.**
- "In addition to the action button or buttons, it's a good idea to include a Cancel button. This button returns the computer to the state it was in before the dialog box appeared. It means 'forget I mentioned it.' Always map the keyboard equivalent Command-period and the Esc (Escape) key to the Cancel button." (Controls, p. 205.)
- "Place the action button in the lower-right corner with the Cancel button to its left. The default button is not necessarily the button in the lower-right corner; it should be the one for the action that the user is most likely to want to perform." (Dialog Boxes, p. 196.)
- On the destructive save-changes case: "In order to prevent accidental clicks of the wrong button, you should always keep safe buttons apart from buttons that could cause data loss." (Menus, ~p. 102.)

**Caution alerts for potentially dangerous actions.**
- "Caution alert boxes warn the user in advance of a potentially dangerous action. This kind of feedback provides a safety net for users. Caution alert boxes always contain two buttons, an OK or Continue button and a Cancel button … The OK or Continue button should be the default button, unless the user has to perform some other task in order to prevent the loss of data." (Dialog Boxes, p. 195.)
- Underlying principle ("Forgiveness"): "Always warn people before they initiate a task that will cause irretrievable data loss."

**What changed, and what didn't.** The verb-based-button rule, the "don't default a dangerous action," the "always offer Cancel," and the safe-placement rules are essentially unchanged since 1992. The modern refinement is the *deliberate-intent carve-out* (Empty Trash) in §3 — the 1992 book already hinted at it ("OK or Continue button should be the default … unless …"), and today's HIG makes it explicit and ties it to the red destructive style. Note also that deleting a LocalCents Category is **not** "irretrievable data loss" of expense data (expenses survive, just un-filed), so it sits *below* the classic "caution alert / irretrievable data loss" bar — an argument for a calmer confirmation rather than a maximally alarming one.

## Reconciliation with the LocalCents house voice (`docs/ui-language.md`)

No conflict — Apple's guidance and the house voice point the same way:

- The house rule "Use **'Delete'** for permanent removal of an entity" (`docs/ui-language.md`) is exactly the specific verb Apple recommends over "OK"/"Yes" (§2). The confirm button should read **Delete**.
- The house distinction between **Delete** (destroy the entity) and **Remove** (detach without destroying) maps cleanly onto this dialog: we **Delete** the *Category*, and the effect on expenses is that they are *un-filed* / removed from that category — consistent with the house note that "removing a Category from an Expense … the Category itself still exists." Use "Delete" for the button (the Category is destroyed) and reserve "remove"-style language for describing the expense side-effect in the body if needed.
- `Cancel` is unaddressed by the house doc but is fixed by Apple ("Always use 'Cancel'"); adopt it verbatim.

One thing to flag rather than silently decide: `docs/ui-language.md` has no stated policy on **whether destructive confirmations should default to the safe button**. Apple gives us two sanctioned options (§3). I recommend the safer one below, but this is a house-voice decision worth recording (an addition to `docs/ui-language.md` or an ADR), not something to bury in a component.

## Recommendation for the delete-category dialog

Because deleting a Category is *deliberately chosen* but also *easy to trigger* and its blast radius (un-filing expenses) is not obvious, lean to the cautious side of Apple's two patterns: verb button with the destructive (red) role, **Cancel as the safe escape, and no button defaulted to Delete**.

**Proposed copy:**

- **Title (a specific question, sentence-style caps, question mark — §1):**
  > Delete the "Groceries" category?
- **Body (states the consequence specifically, short, complete sentence — §1):**
  > The 12 expenses filed under it will move to Uncategorized. The category itself can't be recovered.
  (Omit the count, or say "Any expenses filed under it," if the number isn't cheaply available. If a category has zero expenses, drop the first sentence.)
- **Buttons (verb-based, Cancel fixed, destructive role, Cancel leading/left · Delete trailing/right — §2, §3):**
  > `Cancel` `Delete`
  - `Delete` carries the **destructive role** (system red).
  - **Do not** make `Delete` the default / Return-confirmable button; either make `Cancel` the safe default or set no default (per 1992 Controls p. 205 and current Buttons guidance).
  - Map `Esc` / Command-period to `Cancel`.

**Alternative phrasings (all HIG-compliant):**

1. **Fragment title + object as sentence-fragment** (title-style caps, no punctuation): title `Delete "Groceries"`, body "The 12 expenses filed under this category will move to Uncategorized." Buttons unchanged. Use if we prefer terse, label-like titles.
2. **Empty-Trash / deliberate-intent pattern** (Apple's §3 carve-out): same copy, but treat `Delete` as the user's confirmed intent — allow it to be the default (Return-confirmable) and drop the red destructive styling. Choose this only if we decide the un-filing is low-stakes enough that convenience beats the extra guardrail; record that decision in the house voice.
