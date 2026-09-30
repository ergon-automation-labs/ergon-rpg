# The party

A party is the companions an identity has recruited. It belongs to `bot_army_rpg` — the
bot that already owns sessions, characters and campaigns — and it lives in one table,
`rpg_party_members`, one row per membership.

Before 0.15.46 the party was held in the `PartyStore` process's own state. It answered
every question a party answers, and lost all of it on restart: the store's own name for
what it held was "the user's permanent adventuring group". A party that is permanent has
to be somewhere that survives the process that drew it.

## What is stored, and what is live

| Field | Where | Why |
|-------|-------|-----|
| `tenant_id`, `user_id` | row | whose party this membership is in |
| `character_id` | row | the companion, as a uuid |
| `bot_id` | row | which bot plays her |
| `name`, `class`, `race` | row | a party must be able to name a companion whose character cannot be read right now |
| `role` | row | `companion`, or the one `narrator` a party may have (0.15.48). A role is a designation, not a voice |
| `joined_at` | row | when the party gained her; the store always stamps it |
| `level`, `stats` | **live** | they change. A copy in the party is a second answer that goes stale quietly. `PartyHandler.enrich_member/2` asks `CharacterStore` when it answers |

There is deliberately no foreign key to `rpg_characters`: a membership records who plays
a companion, and a character that cannot be read must not make the party unreadable.

## The seam

```
rpg.party.{get,add,remove,set_narrator}   (NATS, registered)
        │
   PartyHandler              the wire's vocabulary; enriches a member with live level/stats
        │
   PartyStore                the rules; holds nothing but its seam (a GenServer, so calls serialize)
        │
   PartyRepo                 the ONE place that knows the table, the columns and the member shape
        │
   rpg_party_members         Postgres
```

`PartyStore` takes its `PartyRepo` as an option (`party_repo:`, defaulting to the real
one), which is what makes the rules testable without a database — and what makes the
`[verification]`-style live probes read the real table through the real facade.

## The rules

- **A party that could not be read is a refusal**, `{:error, :database_unavailable}` —
  never "no party yet". Reporting an empty party because the database was unreachable
  reports a reading nobody took. A store that raised out of a `handle_call` would be
  worse still: the caller would wait for a reply that never comes.
- **A write that failed leaves the party as it was**, and says so.
- **`get_party` on an identity with no rows is `{:error, :not_found}`**, which the
  handler turns into the blank party plus the message naming `rpg.party.add`.
- **Adding the same companion twice is one of her.** The read decides it; the unique
  index (`rpg_party_members_tenant_id_user_id_character_id_index`) is the backstop, and
  a unique violation is read as `:already_member` rather than as junk.
- **A bad changeset is refused by field name** —
  `{:error, {:invalid_member, [:character_id]}}` — never by echoing the request.
- **The party's age is its oldest membership.** `created_at` is the minimum `joined_at`,
  not `now`; stamping `now` would make the same party's age different on every read.
- **`joined_at` is stamped by the store.** A caller cannot backdate a join.
- **A refusal from `remove` is `:not_found`** — a removal that changed nothing is not a
  removal.
- **A party has one narrator or none**, and the role is held by a *member* — never by a
  caller, never by a turn. Naming one demotes whoever held it; `character_id: null`
  clears it; a character the party does not have is `:not_a_member` and moves no row. The
  demotion and the promotion are one transaction, because a party that briefly held two
  narrators is a state the rule says cannot exist.

## Routes

| Subject | Registered | Notes |
|---------|-----------|-------|
| `rpg.party.get` | yes | needs `user_id` (and `tenant_id`) |
| `rpg.party.add` | yes | recruits a bot companion (provisions her character if needed) |
| `rpg.party.remove` | yes | by `character_id` |
| `rpg.party.set_narrator` | yes | by `character_id`; an explicit `null` clears the role, an absent key is `:missing_character_id` |
| `rpg.party.auto_populate` | **no, on purpose** | its `known_bot_ids/0` list (`gtd`, `llm`, …) does not match the fleet's registered ids (`gtd_bot`, `llm_bot`), so a registered auto_populate would recruit a parallel ghost of every companion. The fix is to take the ids from the registry; until then nothing should be sent here |

The "no party yet" message used to name `rpg.party.auto_populate` — a route nobody
answers. It names `rpg.party.add` now, and a test pins that name against
`BotArmyRpg.NATS.Consumer.subjects/0` so the message cannot drift away from the routes
again.

## Tests

| File | Tag | What it proves |
|------|-----|----------------|
| `test/bot_army_rpg/party_store_test.exs` | `:core` | every rule above, on every `mix test`, through `BotArmyRpg.Test.FakePartyRepo` (ETS + the real changeset + the unique rule) |
| `test/bot_army_rpg/schemas/party_member_test.exs` | `:schemas` | the membership's own shape: uuids, required fields, the role vocabulary, the declared constraint |
| `test/bot_army_rpg/party_store_db_test.exs` | `:stores` + `:integration` | real SQL, the real unique index, durability across a restart, the demote/promote transaction read off the rows, and a dropped table being a refusal |
| `test/bot_army_rpg/handlers/party_handler_test.exs` | `:handlers` | the wire: the blank party's message names a registered route, and `null` vs an absent key are different requests |

The DB test is excluded by default. It refuses to run against a database whose name does
not end in `_test` (`BotArmyRpg.Test.PostgresHelper`), because its setup drops the
schema:

```sh
# The database is not reachable from a laptop directly; tunnel to the node's
# Postgres NodePort first, then point the suite at the tunnel:
ssh -f -N -L 15432:127.0.0.1:30003 mini

BOT_ARMY_RPG_DB_NAME=bot_army_rpg_test BOT_ARMY_RPG_DB_HOST=127.0.0.1 \
  BOT_ARMY_RPG_DB_PORT=15432 \
  mix test --include integration test/bot_army_rpg/party_store_db_test.exs
```

`config/test.exs` sets `pool_size: 2` for this: the migration runner holds a lock
connection while it migrates, and a single-connection pool deadlocks it.

## The party in the narrative context

`rpg.session.gather_context` carries the party too. The bots that flavor a reply out of
that read — `fitness.chat`, the phone's window — are exactly the ones that never knew to
ask for a roster, so it is not opt-in the way the carry history is. The key has three
answers, and they are not interchangeable:

| `"party"` | What happened | What a caller may say |
|-----------|---------------|-----------------------|
| a map with `members` | the store answered: this identity has companions | who walks with her |
| `%{}` | the store answered: this identity has none | nobody does — yet |
| `nil` | the roster was not read (refusal, dead store, raise) | nothing — it is unreported |

`nil` is not an empty party. An unreadable roster never takes the window down: the window
is the read, and the party is something it carries. The read goes through `fetch_party/2`
— the same function the bot-centric adventure context uses — so there is one idea of what
a party is and one mapping of its refusals, including the `nil`-user case below.

## The narrator is a role, held by one member

The window can already render a companion's turn (`GMHandler.apply_resolution/8` writes
the narrated action with her `bot_id` as the fact's `source`). What it could not render is
*whose story it is* — who narrates the scene the party walks through.

That is a role, not a turn. `rpg.party.set_narrator` names one member, and
`BotArmyRpg.PartyStore.narrator/1` reads the answer out of the party the caller already
has: the member whose `role` is `narrator`. The rule that keeps it singular lives in one
transaction in `PartyRepo.set_narrator/3`; a new narrator demotes the one before her.

Two things this deliberately does **not** do:

- **It does not write prose in the narrator's name.** `GM.Narrator` still narrates for the
  table and still signs its facts `source: "gm"`. Attributing the theme's voice to a bot
  that never spoke would be a fabrication, and the window would have no way to tell.
- **It does not publish a narration request nobody answers.** No bot in the fleet
  subscribes to any `rpg.*` subject yet, so a request event today would be a dead end that
  looks like a wire. That wiring — the narrator's bot answering her own turn, including the
  honest "she did not answer this turn" when it does not — is the next slice, and it needs
  the bot-side subscriber to exist first.

Until then the role is what it honestly is: data the party carries, so the window can
badge who narrates. A party with no narrator is a normal party — `narrator/1` returns
`nil`, which means *no member holds the role*, never *the party could not be read*.

## The companion's turn in the window

The window reads turns from **scene facts** and from nothing else (`gather_context` →
`scene_facts` → the phone's reverse). So a companion is in the conversation exactly when
something writes a fact in her name — which is why the narration *is* the turn: a bot's
action is narrated by `GM.Narrator` and that prose is written as one fact,
`category: "narration"`.

| The fact's `source` | Who spoke |
|--------------------|-----------|
| the character's `bot_id` (e.g. `gtd_bot`) | the bot that plays her: `GMHandler.apply_resolution/8` attributes the narrated action |
| `operator` | her, from the phone (`party_window.ex`) |
| `gm` | the theme's narrator voice, for a character no bot plays |

Two things stood in the way of the first row until 0.15.47:

- The fact was sent with a key named `"fact"`, and the store reads `"content"`, which is
  required. Every bot turn was refused by the changeset and dropped in silence — the
  operator's own turns worked only because that path passes the wire payload through
  with the right key. The mechanical line it wrote instead was not a turn either, and its
  interpolation conjugated by appending `"ed"` ("The Bard inspireed the party").
- `record_turn/4` built its result with a map-update (`%{turn_state | "turn_history" =>
  …}`), which raises `KeyError` when the session never had a round started — that is,
  the first turn ever taken in a fresh session crashed the handler instead of replying.
  It uses `Map.put/3` now.

The turn the table reads and the narration the caller is told are compared in
`test/bot_army_rpg/handlers/gm_handler_test.exs`, so they cannot drift apart.

## Known limits

- **An empty party and no party report the same members.** The party *is* its members, so
  a party whose last companion left is indistinguishable from one that never existed.
  A durable `exists` flag would have to be a second table.
- **Levels and stats are not in the party**, so a party read while `CharacterStore` is
  unavailable shows the member's stored name and no level.
- **A companion with no user has no party to report.** The party's key is
  `{tenant_id, user_id}` and the live `gtd_bot` character carries `user_id: nil`; both
  context reads report `%{}` for those instead of asking the store a question it has no
  key for. Asking anyway raised, and that raise took the Consumer process down.
- **`rpg.scene.narrate` still returns and publishes without writing.** Its prose reaches
  the caller on `events.rpg.scene.narrated` and the reply, and no fact — so a scene the GM
  narrates for the table is not a turn. The narrator *role* exists now (0.15.48) and the
  party carries it; making the role narrate is the next slice, and it needs a bot-side
  subscriber to the narration request before publishing that request is worth anything.
