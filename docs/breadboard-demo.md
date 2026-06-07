# Breadboard Demo

Breadboarding a user interface is a brainstorming process first described in [Shape Up](https://basecamp.com/shapeup/1.3-chapter-04#breadboarding).

The basic idea is, before one starts to layout interface elements on a page, you should first conceptualize the job to be done by capturing:

- **Places** -- things you can navigate to: screens, dialogs, menus that pop up.
- **Affordances** -- things the user can act on: buttons, fields, and interface copy. Reading copy is an act that gives the user information for subsequent actions.
- **Connection lines** -- show how the affordances take the user from place to place.

## Tooling: D2

[D2](https://d2lang.com) is a diagram-as-code language that renders well to the breadboard style. It supports nested nodes (places containing affordances) and labeled directed edges (connections).

Install via Homebrew:

```sh
brew install d2
```

Render to SVG (clean) or with `--sketch` for a hand-drawn whiteboard feel:

```sh
d2 invoice-breadboard.d2 images/invoice-breadboard.svg
d2 --sketch invoice-breadboard.d2 images/invoice-breadboard-sketch.svg
```

## Example: Invoice Flow

The source file [`invoice-breadboard.d2`](invoice-breadboard.d2) breadboards a simple invoicing flow — the domain used as the example in Shape Up itself.

The five places in the flow:

| Place | Role |
|---|---|
| Invoices | Dashboard list of all invoices |
| New Invoice | Draft form: client, dates, line items |
| Invoice Preview | Read-only render before sending |
| Sent! | Confirmation screen after email fires |
| Client Portal | Public page the client receives via link |

### Clean render

![Invoice breadboard, clean](images/invoice-breadboard.svg)

### Sketch render

![Invoice breadboard, sketch](images/invoice-breadboard-sketch.svg)

## D2 source structure

A breadboard in D2 maps naturally to its container + nested node model:

```d2
direction: right

# Place (container node)
new_invoice: "New Invoice" {
  # Affordances (leaf nodes)
  client: "Client"
  preview_btn: "[ Preview ]"
  cancel: "Cancel"
}

# Connections: affordance -> place
new_invoice.preview_btn -> preview
new_invoice.cancel -> invoices
```

Places become D2 containers. Affordances become leaf nodes inside them. Connection lines are directed edges from a specific affordance (`container.leaf`) to the target place.
