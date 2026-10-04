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

### The identity, and a value that is not an id

- **`user_id` is resolved, never taken raw.** Every party route runs the request through
  `BotArmyRpg.Identity.resolve_user_id/2`, the same call `rpg.session.*` and
  `rpg.character.list` make, so `"user_id": "abby"` is the same stable id here as it is in
  the window this party belongs to. A name the identity store cannot normalize is
  `:invalid_user_id`.
- **A value the query could not cast is a shape refusal, not an outage.** The query
  compares against `uuid` columns, so a value that is not an id used to raise
  `Ecto.Query.CastError` inside the store and came back to the caller as
  `:database_unavailable` — a lie with a witness, because the database was fine and the
  caller had no way to tell. It is now answered by the column the call keyed on:
  `:invalid_user_id`, `:invalid_character_id`, or `:invalid_tenant_id`. A database that is
  really unreachable still answers `:database_unavailable`.
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
| `rpg.party.set_narrator` | yes | by `character_id`; an explicit `null` clears the role, an absent key is `:missing_character_id` || `rpg.party.auto_populate` | **no, on purpose** | its `known_bot_ids/0` list (`gtd`, `llm`, …) does not match the fleet's registered ids (`gtd_bot`, `llm_bot`), so a registered auto_populate would recruit a parallel ghost of every companion. The fix is to take the ids from the registry; until then nothing should be sent here |

The "no party yet" message used to name `rpg.party.auto_populate` — a route nobody
answers. It names `rpg.party.add` now, and a test pins that name against
`BotArmyRpg.NATS.Consumer.subjects/0` so the message cannot drift away from the routes
again.

## Tests

| File | Tag | What it proves |
|------|-----|----------------|
| `test/bot_army_rpg/party_store_test.exs` | `:core` | every rule above, on every `mix test`, through `BotArmyRpg.Test.FakePartyRepo` (ETS + the real changeset + the unique rule + the uuid cast, so a shape refusal is provable without a database) |
| `test/bot_army_rpg/schemas/party_member_test.exs` | `:schemas` | the membership's own shape: uuids, required fields, the role vocabulary, the declared constraint |
| `test/bot_army_rpg/party_store_db_test.exs` | `:stores` + `:integration` | real SQL, the real unique index, durability across a restart, the demote/promote transaction read off the rows, and a dropped table being a refusal |
| `test/bot_army_rpg/handlers/party_handler_test.exs` | `:handlers` | the wire: the blank party's message names a registered route, and `null` vs an absent key are different requests |
| `test/bot_army_rpg/party_read_test.exs` | `:core` | what a party read answers: no user never reaches the store, `:not_found` is an empty party rather than a refusal, a refusing store is carried to the caller, a name is keyed the way the routes key it, and who narrates is read from the party rather than invented |
| `test/bot_army_rpg/party_narration_test.exs` | `:core` | the ask's payload and subject (published through the `:nats_publisher` seam and asserted on the event), the two kinds (`turn` vs `chat`), and the note an ask writes: its content (with the kind in it), its signing, the asked `bot_id` read back out of it, an old note with no kind in it, and the round's cursor (`last_asked/2`) |
| `test/bot_army_rpg/party_rotation_test.exs` | `:core` | the round itself: the first ask, the round moving on, a cursor naming somebody who left, the author walked past, a table of one author, and an empty table |
| `test/bot_army_rpg/party_chat_test.exs` | `:core` | the rule about lines: which facts are worth an answer, that the window's members are the table, that the round continues off the chat notes and not a turn's, that a table of one author answers `:own_words`, that a window with nobody in it answers `:no_members` and a window or history that cannot be read is `:unreadable` (not an empty table), and what a chat ask puts on the wire |
| `test/bot_army_rpg/handlers/gm_handler_test.exs` | `:handlers` | the wire of a turn: the GM's prose is signed `gm`; a party with a narrator is asked, the note names her and no GM fact is written; an ask that cannot be published leaves the GM narrating; a failing party read leaves the GM narrating |
| `test/bot_army_rpg/handlers/scene_fact_handler_test.exs` | `:handlers` | the wire of a line: it is stored and the window's clock moves; a line in a window is handed to the member whose turn it is and noted; a window nobody was put in, a note the machinery wrote, and an ask the bus would not take all leave the line stored and asked of nobody |
| `test/bot_army_rpg/handlers/session_context_handler_test.exs` | `:handlers` | the window's read: turns are story (a note is not a turn), and `"narration"` reports the newest ask as pending, answered, or nothing at all |

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

The window can already render a turn (`GMHandler.apply_resolution/8` writes the narrated
action as a fact). What it could not render is *whose story it is* — who narrates the scene
the party walks through.

That is a role, not a turn. `rpg.party.set_narrator` names one member, and
`BotArmyRpg.PartyStore.narrator/1` reads the answer out of the party the caller already
has: the member whose `role` is `narrator`. The rule that keeps it singular lives in one
transaction in `PartyRepo.set_narrator/3`; a new narrator demotes the one before her.

The role decides who narrates a turn. With a narrator, the turn's words are **hers**: rpg
asks her and writes none of them itself (see *The ask* below). With no narrator the GM
narrates, exactly as it always has.

What the role never does is **write prose in the narrator's name**. `GM.Narrator` narrates
for the table and signs what it writes `source: "gm"`. It did not always: until 0.15.49
`apply_resolution/8` signed the acting character's `bot_id`, which put the theme's voice in
a bot's mouth. A member's name belongs on words the member wrote, and the only writer of
those words is the member's own bot.

A party with no narrator is a normal party — `narrator/1` returns `nil`, which means *no
member holds the role*, never *the party could not be read*.

## The ask

Two things ask a member for words, on the same event and the same subject:

- a **resolved turn** — `GMHandler.apply_resolution/8` publishes the ask and writes no fact
  for the turn. A turn is a narration, so it goes to the party's **narrator**;
- a **line in the window's chat** — `SceneFactHandler.handle_add/1` hands it to the member
  whose turn it is **at that window's table**, after storing it (see *The chat ask*).

The payload names the member being asked and carries what the ask consists of, because
there is nowhere else for it to be: with a narrator the GM's prose is not written, and a
line in the chat is not a turn at all.

| Key | What it is |
|-----|-----------|
| `kind` | which ask this is: `"turn"` or `"chat"` |
| `bot_id`, `character_id` | who is asked — the narrator's member record (**turns**), the member whose turn it is (**chat**) |
| `session_id` | which table |
| `scene_description` | the scene the table is in (**turns**; a chat ask does not carry it — the bot reads the window itself) |
| `round` | the session's current round, or `nil` if no round was started (**turns** only) |
| `actor`, `action`, `resolution` | the turn itself: who acted, what they did, how it resolved (**turns** only) |
| `content`, `speaker` | the line and who said it — the writer's `source` (**chat** only) |

### The two kinds

The field was added after the subject existed, and it is what the far end branches on:
what a narrator is asked to write for a resolved attack is not what she is asked to write
for a line somebody typed at her. So the same event carries two kinds of material rather
than two subjects carrying one kind each — a bot subscribes once, and the words it writes
land in the same window either way.

Because the field came second, a reader that finds **no** `kind` is reading an older rpg
and must treat the ask as a turn; that is what keeps a rolling deploy of rpg and the
companion from dropping a turn's narration. A kind that is present and unreadable is not a
turn and not a chat: the honest answer is to write nothing.

The ask is **published once and never awaited**. rpg cannot know whether she answers — she
may be down, busy, or writing something longer than any timeout rpg could justify — so the
resolve reply reports the turn as having no narration yet (`"narration" => nil`) plus
`"narrator" => <bot_id>`, and never a sentence she did not write. Her answer is her own
`rpg.scene.fact.add`, signed with her own name; that fact *is* the turn in the window,
because scene facts are the only thing the window reads as a turn.

Three failure rules hold this together:

- **A party read that fails or raises leaves the GM narrating.** A store that is down must
  not take the table's words away, so the unread party is `nil` (the GM narrates) and the
  failure is logged by its kind alone — a dead call's reason carries its arguments, and
  those arguments are the party's key.
- **The ask leaves a note on the window.** A turn handed to somebody has no words yet, and
  a window that only reads facts cannot tell that from a turn nobody ever narrated. So the
  ask is written down as a note (`category: "narration_asked"`, `source: "system"`, content
  `[narration_asked] <kind> <bot_id>`), and `gather_context` reports a `"narration"` field
  read off the newest note — see *The words that have not arrived yet*. The kind is what
  tells the lanes apart: the chat's round is read off the **chat** notes only, so a turn ask
  cannot move it. The note is not a turn: it is signed `system`, so
  `SceneFactStore.story?/1` keeps it out of the carry and out of the window's own turns.
  **One owner** writes it — `PartyNarration.note_the_ask/4` — because both lanes owe the same
  note for the same pending reading; and the ask itself calls it
  (`PartyNarration.publish/4`), so a caller cannot publish an ask the table never sees. An
  ask the bus did not take leaves no note, because nobody was asked.
- **A bus that will not take the ask leaves the GM narrating.** If the publish fails, then
  nothing reached her, so the GM narrates — the same rule as an unreadable party.

### The subject on the wire

The ask is an rpg event, and rpg's `NATS.Publisher.derive_subject/1` maps it explicitly to
**`events.rpg.narration.your_turn`** — the `events.` name every rpg event is published
under, which is what an `events.*` subscriber already knows from
`events.reflection.captured`. The whitelist entry is not decoration: without it the
`events.rpg.#{event_name}` fallback would publish on `events.rpg.rpg.narration.your_turn`.
A bot that answers therefore subscribes to `events.rpg.narration.your_turn`; the name
`rpg.narration.your_turn` elsewhere in this document is the *event*, one lookup away.

`bot_army_companion` is the fleet's subscriber. It decodes the envelope with the fleet
decoder, answers only an ask whose `bot_id` is its own, narrates from the window's log, and
writes the turn as its own `rpg.scene.fact.add` signed with its own `bot_id` — the signer is
the generator. It branches on `kind`, so the same bot answers a turn and a line in the chat
without being subscribed twice: a turn is *told* (two or three paragraphs of narration), a
line is *answered in her own voice* (a sentence or two), and the ask's own material decides
which instruction she is given. Its rules live in `BotArmyCompanion.PartyNarrator`.

## The chat ask

A window's chat is scene facts, so the window used to be one-way: a line typed into it
resolved no action, asked nobody, and sat there unanswered. `BotArmyRpg.PartyChat` is the
rule that closes it — when a line lands in a window, it is handed to the member whose turn
it is at that table (`kind: "chat"`, the line, and who said it).

Neither the surface nor the ask's subject changed. The window already reads an ask with no
words yet from the note, so the same pending line and the same answered line a turn
produces are what a chat ask produces.

Who is asked, and who is not:

| Fact | Asked? | Why |
|---|---|---|
| a line somebody said | yes, the member whose turn it is at this table | the point of the change |
| the answering member's own words | no | a line is already its author's answer; asking them to answer it is the loop. The round walks past the author |
| the GM's prose (`source: "gm"`) | no | rpg already narrated it; a second answer to one turn is a second answer |
| a note the machinery wrote (`source: "system"`) | no | `SceneFactStore.story?/1` is the one thing that says what is story, and bookkeeping is not something anybody said |
| nothing said (blank or missing `content`) | no | an empty line is not a line |

### Who answers: the round

A turn is the narrator's, so a turn's ask goes to the party's narrator. A line in the chat
is not a narration, so it goes **round the table** instead: the member after the one the
chat asked last answers. No single member is the only voice in the conversation, and no line
goes unanswered because the narrator happens to be the one who typed it.

The rule is `BotArmyRpg.PartyRotation.pick/3` — a pure round over a list:

- the **cursor** is the newest `"narration_asked"` note of kind `"chat"` in the window
  (`PartyNarration.last_asked/2`). Reading it off the window's own facts, rather than off a
  counter or a column, is what makes the round survive a restart and makes it fair:
  counting asks and taking the remainder mis-fairs as soon as the author is skipped
  (`B, B, C` instead of `B, C`);
- a **turn** ask never moves the round, because only the chat notes are read for it;
- a note written before the kind was recorded cannot say which lane asked, so it is read as
  a **turn**. At worst a round starts one member early, once;
- the line's **author is walked past**, and only a table where *everyone* is the author
  answers `:own_words`;
- a cursor naming somebody no longer at the table starts the round over rather than picking
  a stranger;
- a member who is not a name at all is not somebody the table can ask and is left out.

### Whose table a window's chat is answered by

The table is the **window's** members — a session's `character_ids`, which is who the screen
put in the scene — ordered by character id so that the same window reads the same order
every time. A party member who was never put in this window is not at this table, and
handing them a line would put words in the mouth of somebody the window does not show. It
also needs no party read at all, which is one less way for the ask to fail.

A window with nobody in it therefore answers nobody (`:no_members`): the line is stored,
read back, and who to put in the window is the screen's answer, not rpg's. A window or a
history that cannot be read asks nobody too, and that is `:unreadable` rather than
`:no_members`, because a store that is down is not a table with nobody at it — and starting
the round over on an unread history would hand the line to somebody the table already
answered as.

The **write** a line lands under still names the party identity, which is what makes it
findable at all: a party is keyed by `{tenant_id, user_id}`, and the identity the window
writes under is the name an operator uses for herself — which is not a UUID. The routes
normalize it (`Identity.resolve_user_id/2`) before they key the store, so the reads in
`PartyRead` normalize too (one owner: `Identity.normalize_user_id/1`): without it a party
would be looked for under a name no row is stored under, and a table with a narrator would
answer nobody for no visible reason. `PartyRead.narrator/2` is the one read that asks who
narrates, so a resolved turn and a line in the chat cannot get two different answers to the
same question.

The ask cannot fail the line: the line is already stored and the caller is being told so by
the time it is attempted, so an ask that did not go out is a member nobody asked — the
window then says their words are not there yet, which is true — and never a lost line. Every
outcome is reported by its kind (`{:asked, member}`, `:no_members`, `:own_words`,
`:not_a_turn`, `:no_window`, `:unreadable`, `{:error, reason}`) and logged.

## The words that have not arrived yet

The window's turns are facts, so `rpg.session.gather_context` reports what it knows about
the newest ask as a structured field, not as a line the reader has to recognise:

| `context["narration"]` | What it means |
|---|---|
| `nil` | nothing was asked in what was read (the newest `fact_limit` facts hold no note) |
| `%{"asked_of" => bot_id, "pending" => true}` | she was asked for the newest turn, and nothing has been written since |
| `%{"asked_of" => bot_id, "pending" => false}` | she was asked, and a fact signed with her name is newer than the note |

Two rules make the third row honest. "She answered" is a fact **newer** than the note whose
`source` is the asked `bot_id` — a bot's turn is written by the bot, so the signer is the
generator. And the field is derived from the *newest* note of the same bounded read as the
turns, so it makes no claim about an ask older than the newest `fact_limit` facts.

What a table does with `pending: true` is the table's business: the phone draws
`(she says nothing)` — a sentence about the window, never words in her mouth. The key is
always present (`nil` is an answer: nothing is pending), because a *failed* read returns no
context at all.

## The companion's turn in the window

The window reads turns from **scene facts** and from nothing else (`gather_context` →
`scene_facts` → the phone's reverse). So a companion is in the conversation exactly when
something writes a fact in her name — which is why the narration *is* the turn: the prose
is written as one fact, `category: "narration"`, by `GM.Narrator` (with no narrator) or by
the narrator's own bot (with one — see *The ask*).

## Whose name is on the words

The signer is the generator. The window draws `source` as the speaker (`party_window.ex` →
`who/1`), so the field says who wrote the prose, never who the prose is about:

| The fact's `source` | Who spoke |
|--------------------|-----------|
| `gm` | the theme's narrator voice: `GMHandler.apply_resolution/8`, whether or not a bot plays the character — `GM.Narrator` asks the LLM as the Game Master and a template answers when the LLM is away, and both are the GM |
| `operator` | her, from the phone (`party_window.ex`) |
| a character's `bot_id` (e.g. `gtd_bot`) | that bot, *when the bot writes the turn itself* — rpg asks the narrator to (see *The ask*); until a bot in the fleet answers, no fact has been written this way |
| `system` | the machinery: not story, and excluded from the carry (`story?/1`) |

Signing the GM's prose `gm` does not lose the actor: the prompt and the fallback both name
her, and `TurnManager.record_turn/4` records her turn in the session metadata. The
alternative — keeping `source: bot_id` and reading it as *the turn belongs to her* — was
rejected because the screen has one field for this and draws it as a speaker, so the two
readings cannot both be true, and the fabricated one is the one the table would have shown.

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
  narrates for the table is not a turn.
- **A party that names a narrator has turns with no words until a bot answers.** The ask
  ships (0.15.50), the note and the `"narration"` reading with it (0.15.51), and
  `bot_army_companion` is the subscriber. A narrator whose bot is down, or a party whose
  narrator is a bot that does not answer, still leaves the window with `pending: true` —
  the honest absence, and what the window's `(she says nothing)` is for.
