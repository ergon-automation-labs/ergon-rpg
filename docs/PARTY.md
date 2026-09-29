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
| `role` | row | `companion` today; the vocabulary for anything else |
| `joined_at` | row | when the party gained her; the store always stamps it |
| `level`, `stats` | **live** | they change. A copy in the party is a second answer that goes stale quietly. `PartyHandler.enrich_member/2` asks `CharacterStore` when it answers |

There is deliberately no foreign key to `rpg_characters`: a membership records who plays
a companion, and a character that cannot be read must not make the party unreadable.

## The seam

```
rpg.party.{get,add,remove}   (NATS, registered)
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

## Routes

| Subject | Registered | Notes |
|---------|-----------|-------|
| `rpg.party.get` | yes | needs `user_id` (and `tenant_id`) |
| `rpg.party.add` | yes | recruits a bot companion (provisions her character if needed) |
| `rpg.party.remove` | yes | by `character_id` |
| `rpg.party.auto_populate` | **no, on purpose** | its `known_bot_ids/0` list (`gtd`, `llm`, …) does not match the fleet's registered ids (`gtd_bot`, `llm_bot`), so a registered auto_populate would recruit a parallel ghost of every companion. The fix is to take the ids from the registry; until then nothing should be sent here |

The "no party yet" message used to name `rpg.party.auto_populate` — a route nobody
answers. It names `rpg.party.add` now, and a test pins that name against
`BotArmyRpg.NATS.Consumer.subjects/0` so the message cannot drift away from the routes
again.

## Tests

| File | Tag | What it proves |
|------|-----|----------------|
| `test/bot_army_rpg/party_store_test.exs` | `:core` | every rule above, on every `mix test`, through `BotArmyRpg.Test.FakePartyRepo` (ETS + the real changeset + the unique rule) |
| `test/bot_army_rpg/schemas/party_member_test.exs` | `:schemas` | the membership's own shape: uuids, required fields, role, the declared constraint |
| `test/bot_army_rpg/party_store_db_test.exs` | `:stores` + `:integration` | real SQL, the real unique index, durability across a restart, and a dropped table being a refusal |
| `test/bot_army_rpg/handlers/party_handler_test.exs` | `:handlers` | the wire: the blank party's message names a registered route |

The DB test is excluded by default. It refuses to run against a database whose name does
not end in `_test` (`BotArmyRpg.Test.PostgresHelper`), because its setup drops the
schema:

```sh
BOT_ARMY_RPG_DB_HOST=<host> BOT_ARMY_RPG_DB_PORT=<port> \
  mix test --include integration test/bot_army_rpg/party_store_db_test.exs
```

## Known limits

- **An empty party and no party report the same members.** The party *is* its members, so
  a party whose last companion left is indistinguishable from one that never existed.
  A durable `exists` flag would have to be a second table.
- **Levels and stats are not in the party**, so a party read while `CharacterStore` is
  unavailable shows the member's stored name and no level.
- **`rpg.session.gather_context` still carries no roster.** Banter for other bots needs
  the party to appear in that payload; that is Road B, and it must not break
  `fetch_party/2`'s `{:error, :not_found}` → `{:ok, %{}}` mapping.
