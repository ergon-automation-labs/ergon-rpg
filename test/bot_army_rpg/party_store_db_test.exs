defmodule BotArmyRpg.PartyStoreDbTest do
  @moduledoc """
  The party in real Postgres.

  Everything the default suite decides with a stand-in, against the database the bot
  actually uses — plus the three things only a database can prove:

    * the unique index refuses a second membership,
    * a member is still there after the process that wrote her is gone, and
    * a table that is not there is a refusal (`:database_unavailable`), never an empty
      party. That is the failure this store is most likely to meet in the field, and it
      is the one a stand-in cannot produce honestly.

  Tagged `:integration` (excluded by default): it needs Postgres. It refuses to run
  against a database whose name does not end in `_test`, because its setup drops the
  schema — the guard lives in `BotArmyRpg.Test.PostgresHelper`.

  Point it at a database with:

      BOT_ARMY_RPG_DB_HOST=<host> BOT_ARMY_RPG_DB_PORT=<port> \\
        mix test --include integration test/bot_army_rpg/party_store_db_test.exs
  """

  use ExUnit.Case, async: false

  @moduletag :stores
  @moduletag :integration

  alias BotArmyRpg.PartyRepo
  alias BotArmyRpg.PartyStore
  alias BotArmyRpg.Repo
  alias BotArmyRpg.Test.PostgresHelper
  alias Ecto.Adapters.SQL.Sandbox
  alias RpgBot.Release

  @tenant "00000000-0000-0000-0000-000000000099"
  @user "00000000-0000-0000-0000-0000000000aa"

  @characters %{
    "gtd_bot" => "11111111-1111-1111-1111-111111111111",
    "llm_bot" => "22222222-2222-2222-2222-222222222222"
  }

  setup do
    start_supervised!(Repo)
    # `:auto` rather than a sandbox transaction: the store is another process, and this
    # file resets the schema per test instead of pretending each test is isolated.
    :ok = Sandbox.mode(Repo, :auto)
    PostgresHelper.reset_schema!(Repo)
    assert :ok = Release.migrate()
    :ok
  end

  defp member(bot_id, overrides \\ %{}) do
    Map.merge(
      %{
        "character_id" => Map.fetch!(@characters, bot_id),
        "bot_id" => bot_id,
        "name" => "The #{bot_id}",
        "class" => "Companion",
        "race" => "Construct"
      },
      overrides
    )
  end

  defp attrs(bot_id) do
    %{
      tenant_id: @tenant,
      user_id: @user,
      character_id: Map.fetch!(@characters, bot_id),
      bot_id: bot_id,
      name: "The #{bot_id}",
      class: "Companion",
      race: "Construct",
      role: "companion",
      joined_at: DateTime.utc_now()
    }
  end

  test "the table the store reads is the one the migration builds" do
    assert {:ok, %{rows: rows}} =
             Repo.query(
               "SELECT column_name FROM information_schema.columns " <>
                 "WHERE table_name = 'rpg_party_members'"
             )

    columns = List.flatten(rows)

    for column <- ~w(id tenant_id user_id character_id bot_id name class race role) do
      assert column in columns, "rpg_party_members is missing #{column}"
    end

    assert "joined_at" in columns
    assert "inserted_at" in columns
    assert "updated_at" in columns
  end

  test "a companion recruited through the store is in the table" do
    start_supervised!(PartyStore)

    assert {:ok, party} = PartyStore.add_member(@tenant, @user, member("gtd_bot"))

    assert [joined] = party["members"]
    assert joined["bot_id"] == "gtd_bot"
    assert joined["name"] == "The gtd_bot"
    assert joined["role"] == "companion"
    assert is_binary(joined["joined_at"])

    assert {:ok, reread} = PartyStore.get_party(@tenant, @user)
    assert reread["members"] == party["members"]
    assert reread["created_at"] == joined["joined_at"]
  end

  test "a party outlives the process that wrote it" do
    start_supervised!(PartyStore)
    {:ok, _} = PartyStore.add_member(@tenant, @user, member("gtd_bot"))
    stop_supervised!(PartyStore)

    start_supervised!(PartyStore)

    assert {:ok, party} = PartyStore.get_party(@tenant, @user)
    assert [%{"bot_id" => "gtd_bot", "name" => "The gtd_bot"}] = party["members"]
  end

  test "the unique index refuses a second membership of the same companion" do
    assert {:ok, _} = PartyRepo.insert(attrs("gtd_bot"))

    assert {:error, %Ecto.Changeset{} = refused} = PartyRepo.insert(attrs("gtd_bot"))
    refute refused.valid?

    # The store reads the database's refusal as a unique violation rather than as junk.
    assert Enum.any?(refused.errors, fn {_field, {_message, opts}} ->
             Keyword.get(opts, :constraint) == :unique
           end)
  end

  test "a character id that is not a uuid is refused before a query is built" do
    start_supervised!(PartyStore)

    assert {:error, {:invalid_member, [:character_id]}} =
             PartyStore.add_member(
               @tenant,
               @user,
               member("gtd_bot", %{"character_id" => "gtd_bot"})
             )
  end

  test "a table that is not there is a refusal, not an empty party" do
    start_supervised!(PartyStore)
    Repo.query!("DROP TABLE rpg_party_members")
    pid = Process.whereis(PartyStore)

    assert {:error, :database_unavailable} = PartyStore.get_party(@tenant, @user)
    assert Process.whereis(PartyStore) == pid
  end
end
