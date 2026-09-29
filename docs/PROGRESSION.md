# Progression: XP, levels, and companions

How characters level up, who earns what, and where the knobs are.

## Who earns XP

XP comes from **real-world events**, not from roleplay. `BotArmyRpg.ProgressionSubscriber`
consumes four subjects:

| Subject | XP |
|---|---|
| `events.gtd.task.completed` | by difficulty: advanced 300 / intermediate 150 / beginner 75 |
| `events.gtd.task.created` | by intensity: high 200 / moderate 100 / low 50 |
| `events.fitness.workout.logged` | by intensity |
| `events.learning.lesson.completed` | by difficulty |

The character that earns the XP is the one belonging to the event's own user
(`user_id`), not the caller.

**Sessions and travel award no XP today.** There is no `rpg.session.*` subject in the
subscriber, so nothing that happens in a tavern session moves a character's level.

## The curve

One curve, used by every award path — `BotArmyRpg.CharacterStore.apply_xp/4`:

    xp_to_next(level) = level * 500

An award grants **at most one level**; the remainder carries into the new level's
progress. On level-up the character's primary ability is boosted. The same curve serves
both award kinds (`award_to/4`):

- a **user** character, found by `user_id`
- a **bot** character, found by `bot_id` (`award_xp_to_bot/3`)

## Companions: level up while you are away

The Persona rule: the people you travel with keep growing even when they stayed home,
just not as fast.

`BotArmyRpg.Progression.Companions.award_away/4` runs after the participant's own award.
Every **other** character in the tenant earns a reduced share:

    share = trunc(xp * rate)      rate default 0.5

- **The rate** is `:away_xp_rate` in the application env, validated into `[0, 1)`.
  Anything unusable falls back to `0.5` and logs. `rate < 1` is deliberate: it is what
  stops away XP from ever out-levelling the character who was actually there.
- **Away members earn XP only, never loot.** Loot is for being present.
- **The participant is never awarded away XP** (excluded by `id`).
- **Away failure is isolated.** A `rescue` and a `catch :exit` return `[]`, so a broken
  companion can never affect the participant's own award, and an unavailable store
  cannot take the caller down.
- **The event** `rpg.progression.away` carries `"away" => true` plus `leveled_up`,
  `old_level`, `xp_earned`, so a reader can tell an away award from a present one.
- **Injectable seams**: `:rate`, `:store` and `:publish` are all options, which is why
  this module is testable without a database or a broker.

Open questions, deliberately not decided here:

- **The away set is the whole tenant**, because the event carries no session. A
  session- or campaign-scoped set would need a session on the wire first.
- **Away XP is not persisted as loot or as a separate ledger**, and there is no durable
  `rpg_party_members` table.

## Store write discipline (why awards used to do nothing)

`CharacterStore` handlers must **never call this module's own client functions**.
`get_by_user_id/2`, `update/3` and friends are `GenServer.call` to the very process
running the handler; OTP detects the self-call and the store **exits**. That is what
every real XP event did before 0.15.45: `rpg.character.award_xp` answered
`"error":":handler_crashed"` in 0.09 s and no XP was ever written.

Handlers now read state and write through private helpers:

- `find_by_user_id/3`, `find_by_bot_id/3` — state lookups (no process call)
- `persist_update/2` — the single write path (`Repo.transaction` + `Repo.update`)
- `award_to/4` — the single award body (curve, boost, persist, state)

A database outage on the write path is a **refusal** (`{:error, :database_unavailable}`),
not a dead store. The store's state is updated to exactly what was written, so a reply
never describes a write that did not happen.

## Tests

- `test/bot_army_rpg/character_store_test.exs` (`:stores`) — the three dispatch refusals
  (each asserting the store is **still alive** afterwards) and the pure curve.
- `test/bot_army_rpg/progression/companions_test.exs` (`:core`) — the share, the rate
  validation, target selection, the participant-never-awarded rule, store failure
  isolation, and the away notification.

Every award in the companions test names its store explicitly. Several other test modules
put `:character_store` into the application env in `setup` and **delete** it on exit,
which removes the key `config/test.exs` set — a test that reads the ambient default then
resolves the real, unstarted store and passes or fails by module order.
