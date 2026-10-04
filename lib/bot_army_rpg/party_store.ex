defmodule BotArmyRpg.PartyStore do
  @moduledoc """
  The party, kept in Postgres.

  A party is permanent — the user's adventuring group, earning XP alongside every bot
  that does real work. A GenServer's memory is not, and while this store held the party
  in a map, "permanent" meant "until the bot next started". The memberships live in
  `rpg_party_members` now; the process is kept as the serialization point the
  application already supervises, not as the place the party lives.

  Two rules it answers by, both paid for:

    * **A party that could not be read is a refusal.** A repo failure answers
      `{:error, :database_unavailable}`, never "no party yet". Reporting an identity's
      party as empty because the database was unreachable reports a reading nobody took
      as a fact.
    * **Nothing raises out of a call.** A raise inside `handle_call` terminates the store
      and leaves the caller waiting instead of refused (0.15.45: the progression feature
      was dead because a store killed itself). Every repo call is wrapped, and a write
      that fails leaves the party as it was.

  The party is its members, and the reply to a write is the party that write produced —
  read back from the row, not assembled from what the caller said.

  The party has no row of its own, so a party whose last companion left and a party that
  never existed report the same thing. That is a real limit of a members table, not a
  hidden one: the members are the party, and an "exists" flag would be a second, weaker
  answer to a question they already answer.
  """

  @behaviour BotArmyRpg.PartyStoreBehaviour

  use GenServer
  require Logger

  alias BotArmyRpg.PartyRepo

  @server __MODULE__
  @party_name "The Adventuring Party"
  @unavailable {:error, :database_unavailable}

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: @server)
  end

  @impl true
  def get_party(tenant_id, user_id) when is_binary(tenant_id) and is_binary(user_id) do
    GenServer.call(@server, {:get_party, tenant_id, user_id})
  end

  @impl true
  def add_member(tenant_id, user_id, member_data) when is_map(member_data) do
    GenServer.call(@server, {:add_member, tenant_id, user_id, member_data})
  end

  @impl true
  def remove_member(tenant_id, user_id, character_id) when is_binary(character_id) do
    GenServer.call(@server, {:remove_member, tenant_id, user_id, character_id})
  end

  # `character_id` is deliberately unguarded: `nil` is a request — clear the role — and it
  # is not the same request as naming a member.
  @impl true
  def set_narrator(tenant_id, user_id, character_id)
      when is_binary(tenant_id) and is_binary(user_id) do
    GenServer.call(@server, {:set_narrator, tenant_id, user_id, character_id})
  end

  @impl true
  def auto_populate(tenant_id, user_id) when is_binary(tenant_id) and is_binary(user_id) do
    GenServer.call(@server, {:auto_populate, tenant_id, user_id}, 15_000)
  end

  @impl true
  def list_parties(tenant_id) when is_binary(tenant_id) do
    GenServer.call(@server, {:list_parties, tenant_id})
  end

  # The party's table is reached through one module (`BotArmyRpg.PartyRepo`), and that
  # module is the option — so a test can hand this store a stand-in and decide the
  # party's rules without a database. A store that named the real one would only be
  # testable where Postgres is.
  @impl true
  def init(opts) do
    Logger.info("[PartyStore] Starting")
    {:ok, %{party_repo: Keyword.get(opts, :party_repo, BotArmyRpg.PartyRepo)}}
  end

  @impl true
  def handle_call({:get_party, tenant_id, user_id}, _from, state) do
    case members(state.party_repo, tenant_id, user_id) do
      {:ok, []} -> {:reply, {:error, :not_found}, state}
      {:ok, members} -> {:reply, {:ok, party(members)}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:add_member, tenant_id, user_id, member_data}, _from, state) do
    case members(state.party_repo, tenant_id, user_id) do
      {:ok, members} ->
        {:reply, add(state, tenant_id, user_id, member_data, members), state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:remove_member, tenant_id, user_id, character_id}, _from, state) do
    case members(state.party_repo, tenant_id, user_id) do
      {:ok, members} ->
        {:reply, remove(state, tenant_id, user_id, character_id, members), state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # The answer is the party read back after the rows moved, never the party the request
  # implied — and a member the party does not have is a refusal, not a quiet promotion of
  # nobody. See `narrate/4`.
  @impl true
  def handle_call({:set_narrator, tenant_id, user_id, character_id}, _from, state) do
    {:reply, narrate(state, tenant_id, user_id, character_id), state}
  end

  @impl true
  def handle_call({:auto_populate, tenant_id, user_id}, _from, state) do
    # One write path: recruiting is `insert/4`, once per known bot. A second insert here
    # would be a second place that knows how a member is written.
    #
    # This route is deliberately NOT registered (see `PartyHandler`): the ids below are a
    # guess that does not match the fleet's characters — the bots register `gtd_bot`,
    # `llm_bot`, while this list says `gtd`, `llm` — so a registered auto_populate would
    # recruit a parallel ghost of every companion. The fix is to take the ids from
    # `BotArmyLibraryRuntime.Registry.list_bots/1`, and until then nothing should be sent
    # here by a caller who expects the real companions.
    {added, failures} =
      Enum.reduce(known_bot_ids(), {0, []}, fn bot_id, {added, failures} ->
        case recruit(state.party_repo, tenant_id, user_id, bot_id) do
          {:ok, :already_member} -> {added, failures}
          {:ok, _member} -> {added + 1, failures}
          {:error, reason} -> {added, [reason | failures]}
        end
      end)

    case members(state.party_repo, tenant_id, user_id) do
      {:ok, members} ->
        Logger.info(
          "[PartyStore] Auto-populated #{added} companions for #{user_id}'s party " <>
            "(#{length(members)} total, #{length(failures)} could not be recruited)"
        )

        {:reply, {:ok, party(members)}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:list_parties, tenant_id}, _from, state) do
    case all_for_tenant(state.party_repo, tenant_id) do
      {:ok, rows} ->
        parties =
          rows
          |> Enum.group_by(& &1["user_id"])
          |> Enum.map(fn {user_id, members} -> Map.put(party(members), "user_id", user_id) end)

        {:reply, {:ok, parties}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @doc """
  The party an identity has before it has one: named, and empty.

  Public so the one place that has to say "no party yet" says it with the same name this
  store would have used, instead of spelling the party's name a second time in a handler
  (N+56: a domain rule is not re-implemented in a second place).
  """
  def blank_party do
    %{
      "name" => @party_name,
      "members" => [],
      "created_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  @doc """
  The party's narrator, or `nil`.

  One answer to "who narrates", read out of the party itself — the member whose role is
  `narrator`. A party has one or none, and `set_narrator/3` is the only thing that can
  change it, so this is a lookup and not a vote.

  `nil` means *no member holds the role*. It never means *the party could not be read*:
  that is already a refusal by the time a caller has a party to pass here.

  Public for the same reason as `blank_party/0`: two callers asking who narrates must not
  each spell the answer, and the window must not be the second place that decides what a
  narrator is.
  """
  def narrator(%{"members" => members}) when is_list(members) do
    Enum.find(members, &(&1["role"] == "narrator"))
  end

  def narrator(_party), do: nil

  # --- Private ---

  # A party is its members, and its `created_at` is the oldest membership — the moment
  # the party began. Stamping `now` here would make the same party's age different on
  # every read.
  defp party(members) do
    %{
      "name" => @party_name,
      "members" => members,
      "created_at" => members |> Enum.map(& &1["joined_at"]) |> Enum.min(fn -> nil end)
    }
  end

  defp members(party_repo, tenant_id, user_id) do
    safeguard("read the party", :user_id, fn -> {:ok, party_repo.members(tenant_id, user_id)} end)
  end

  # Adding a companion who is already in the party is neither an error nor a second
  # member: she is one of her, and the party is what it was.
  defp add(state, tenant_id, user_id, member_data, members) do
    if Enum.any?(members, &(&1["character_id"] == member_data["character_id"])) do
      {:ok, party(members)}
    else
      insert_new(state, tenant_id, user_id, member_data, members)
    end
  end

  defp insert_new(state, tenant_id, user_id, member_data, members) do
    case insert(state.party_repo, tenant_id, user_id, member_data) do
      {:ok, member} ->
        Logger.info("[PartyStore] #{member["name"]} joined #{user_id}'s party")
        {:ok, party(members ++ [member])}

      {:error, :already_member} ->
        reread_or_refuse(state, tenant_id, user_id)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp remove(_state, _tenant_id, _user_id, _character_id, []) do
    # Nothing to leave. A removal that changed nothing is not a removal.
    {:error, :not_found}
  end

  defp remove(state, tenant_id, user_id, character_id, members) do
    case delete(state.party_repo, tenant_id, user_id, character_id) do
      {:ok, _count} ->
        remaining = Enum.reject(members, &(&1["character_id"] == character_id))
        Logger.info("[PartyStore] Removed #{character_id} from #{user_id}'s party")
        {:ok, party(remaining)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Naming a narrator is a write whose answer is the party read back. A character who is
  # not in the party is refused by the repo — inside its transaction, so the refusal
  # cannot leave the party with the narrator it had before taken away. The store decides
  # nothing about membership here: it only speaks the repo's answer.
  defp narrate(state, tenant_id, user_id, character_id) do
    case set_role(state.party_repo, tenant_id, user_id, character_id) do
      {:ok, _counts} ->
        party_after_write(state, tenant_id, user_id)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # The party as the rows now say it. A write can leave no party behind — the members are
  # the party — and that is `:not_found`, the same answer a read with no rows gives.
  defp party_after_write(state, tenant_id, user_id) do
    case members(state.party_repo, tenant_id, user_id) do
      {:ok, []} -> {:error, :not_found}
      {:ok, members} -> {:ok, party(members)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp set_role(party_repo, tenant_id, user_id, character_id) do
    safeguard("name the party's narrator", :character_id, fn ->
      party_repo.set_narrator(tenant_id, user_id, character_id)
    end)
  end

  defp all_for_tenant(party_repo, tenant_id) do
    safeguard("list the tenant's parties", :tenant_id, fn ->
      {:ok, party_repo.all_for_tenant(tenant_id)}
    end)
  end

  defp insert(party_repo, tenant_id, user_id, member_data) do
    safeguard("write a member", :user_id, fn ->
      party_repo.insert(member_attrs(tenant_id, user_id, member_data)) |> shaped()
    end)
  end

  defp shaped({:ok, row}), do: {:ok, PartyRepo.to_member(row)}
  defp shaped({:error, %Ecto.Changeset{} = changeset}), do: changeset_refusal(changeset)
  defp shaped({:error, reason}), do: {:error, reason}

  defp changeset_refusal(changeset) do
    if unique_violation?(changeset) do
      {:error, :already_member}
    else
      # The field names, not the values: a refusal says which part of the request was
      # wrong without putting the request on the wire.
      {:error, {:invalid_member, Keyword.keys(changeset.errors)}}
    end
  end

  defp delete(party_repo, tenant_id, user_id, character_id) do
    safeguard("remove a member", :character_id, fn ->
      party_repo.delete(tenant_id, user_id, character_id)
    end)
  end

  # The unique index refused the insert, so the companion is already in the party —
  # unless the read that follows shows otherwise, in which case the refusal stands.
  defp reread_or_refuse(state, tenant_id, user_id) do
    case members(state.party_repo, tenant_id, user_id) do
      {:ok, members} -> {:reply, {:ok, party(members)}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  defp recruit(party_repo, tenant_id, user_id, bot_id) do
    with {:ok, members} <- members(party_repo, tenant_id, user_id) do
      if Enum.any?(members, &(&1["bot_id"] == bot_id)) do
        {:ok, :already_member}
      else
        recruit_new(party_repo, tenant_id, user_id, bot_id)
      end
    end
  end

  defp recruit_new(party_repo, tenant_id, user_id, bot_id) do
    case provision(bot_id, tenant_id) do
      {:ok, character} ->
        insert(party_repo, tenant_id, user_id, member_data(character, bot_id))

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp provision(bot_id, tenant_id) do
    safeguard("provision #{bot_id}", :id, fn ->
      BotArmyRpg.CharacterProvisioning.ensure_bot_character(bot_id, tenant_id)
    end)
  end

  defp member_attrs(tenant_id, user_id, member_data) do
    %{
      tenant_id: tenant_id,
      user_id: user_id,
      character_id: member_data["character_id"],
      bot_id: member_data["bot_id"],
      name: member_data["name"],
      class: member_data["class"],
      race: member_data["race"],
      role: member_data["role"] || "companion",
      joined_at: DateTime.utc_now()
    }
  end

  defp member_data(character, bot_id) do
    %{
      "character_id" => character["id"],
      "bot_id" => bot_id,
      "name" => character["name"],
      "class" => character["class"],
      "race" => character["race"]
    }
  end

  defp unique_violation?(changeset) do
    Enum.any?(changeset.errors, fn {_field, {_message, opts}} ->
      Keyword.get(opts, :constraint) == :unique
    end)
  end

  # Every repo call goes through here. A failure is the store's answer, not the store's
  # death: a raise out of a `handle_call` kills the process and the caller waits for a
  # reply that will never come.
  #
  # `which` names the column the call keyed on, and it is used for one thing: a value the
  # query could not cast is a **shape** failure, and it is answered as one. Reporting it as
  # `:database_unavailable` was a lie with a witness — a caller who sent `"user_id":
  # "abby"` was told the database was down, and the database was fine. A database that is
  # really unreachable still answers `:database_unavailable`.
  defp safeguard(what, which, fun) do
    fun.()
  rescue
    e in [Ecto.Query.CastError] ->
      log_failure(what, e)
      {:error, invalid_reason(which)}

    e ->
      log_failure(what, e)
      @unavailable
  catch
    :exit, reason ->
      # The reason's *shape*, never the whole thing: an exit reason from a call carries
      # the call's arguments, and the arguments are the party.
      Logger.error("[PartyStore] Could not #{what}: exited (#{inspect(shape(reason))})")
      @unavailable
  end

  defp log_failure(what, e) do
    Logger.error(
      "[PartyStore] Could not #{what}: #{inspect(e.__struct__)} - #{Exception.message(e)}"
    )
  end

  defp invalid_reason(:user_id), do: :invalid_user_id
  defp invalid_reason(:character_id), do: :invalid_character_id
  defp invalid_reason(:tenant_id), do: :invalid_tenant_id
  defp invalid_reason(_id), do: :invalid_id

  defp shape(reason) when is_tuple(reason), do: elem(reason, 0)
  defp shape(reason), do: reason

  defp known_bot_ids do
    [
      "gtd",
      "synapse",
      "llm",
      "fitness",
      "terrain",
      "chore",
      "job_applications",
      "discord",
      "claude_bridge",
      "database_backups",
      "sre"
    ]
  end
end
