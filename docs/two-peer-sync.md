# Running the two-peer sync

LocalCents can run as **two BEAM peers** that reconcile a Book over a real WebSocket, the transport behind the offline-collaboration demo ([ADR 0025](0025-two-peer-sync-architecture.html)).

## The one-command launcher

`scripts/two-peer-demo.sh` brings the whole demo up: it seeds a fresh demo Book into peer A, forks it into peer B so both start from a common Automerge ancestor, boots peer B (the host) and peer A (the Tauri Mac app dialing in), opens the browser to peer B, and tears both instances down on exit. Each peer keeps its own `.lcbook` in a throwaway directory, so the demo never touches your real books.

```
scripts/two-peer-demo.sh
```

Open the Book in both windows, then use the Mac app's **Developer** menu to toggle offline and force a divergence. Quit the Mac app (or press Ctrl-C) to tear the demo down; a repeated run starts clean. Set `PEER_B_PORT` if 4001 is taken.

## Standing the peers up by hand

The rest of this page is the manual recipe the launcher wraps — the way to stand the two peers up yourself and watch an edit cross between them.

## The two peers

- **Peer A — the dialer.** In the product this is the Mac app's embedded BEAM. It owns its own document and `.lcbook`, and dials out to peer B to sync.
- **Peer B — the host.** A plain standalone Phoenix server on its own port with no Tauri shell. It owns its own second document and `.lcbook`, and hosts the sync Channel (`LocalCentsWeb.PeerSocket` / `LocalCentsWeb.Sync.Channel`). The browser is peer B's always-online LiveView client and holds no document of its own.

Each peer keeps its own local `.lcbook`, so this leaves ADR 0007's server-side storage question deferred.

## 1. Run peer B (the host)

Give it its own books directory and port:

```
LOCAL_CENTS_BOOKS_DIR=/tmp/localcents-peer-b PORT=4001 mix phx.server
```

`LOCAL_CENTS_BOOKS_DIR` is what keeps peer B's `.lcbook` files out of peer A's directory (see `LocalCents.Tracking.BookStore.default_dir/0`). Open <http://localhost:4001> to reach peer B's browser client.

## 2. Share a Book

Both peers reconcile one Book, and they must start from a common Automerge ancestor. Copy the origin's `.lcbook` into peer B's directory so the two share history and id — a byte copy is a genuine shared ancestor, which is what the launcher automates. Booting peer B does not create the directory — `default_dir/0` only makes it on the first store operation — so create it yourself before the copy:

```
mkdir -p /tmp/localcents-peer-b
cp "$HOME/Library/Application Support/LocalCents/books/<book-id>.lcbook" /tmp/localcents-peer-b/
```

Peer B enumerates its directory when the library loads, so refresh <http://localhost:4001> after the copy to see the Book.

## 3. Establish the link from peer A

Start peer A pointing at peer B's socket:

```
LOCAL_CENTS_SYNC_URL=ws://127.0.0.1:4001/peer/websocket \
LOCAL_CENTS_SYNC_BOOK_ID=<book-id> \
mix phx.server
```

`LOCAL_CENTS_SYNC_URL` is peer B's `LocalCentsWeb.PeerSocket` endpoint and `LOCAL_CENTS_SYNC_BOOK_ID` is the shared Book id. With neither variable set, an instance only *hosts* the Channel and dials no one — which is exactly peer B above. Peer A runs on the default port 4000; open <http://localhost:4000> for its browser client.

## 4. Watch it sync

Open the Book on both sides. Edit an expense's description on either peer while both are connected, and the change reaches the other. Only the changes a peer is missing cross the wire — the Automerge sync protocol, not a whole-document resend.

## How the pieces fit

- `LocalCentsWeb.PeerSocket` and `LocalCentsWeb.Sync.Channel` — the host side a peer dials into.
- `LocalCentsWeb.Sync.PeerClient` — the dialing side, started from the supervision tree when the sync environment variables are set.
- `LocalCentsWeb.Sync.Message` — the Base64 envelope both sides wrap a sync message in, since a Channel payload is JSON.
- The reconcile itself runs through the `LocalCents.Tracking` context, so neither transport module holds a document; the per-peer sync state lives in each Book's `BookServer` (ADR 0025).
