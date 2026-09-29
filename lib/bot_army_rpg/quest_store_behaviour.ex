defmodule BotArmyRpg.QuestStoreBehaviour do
  @moduledoc """
  Behaviour contract for quest storage.

  `list_active/1` and `list_all/1` are separate callbacks on purpose: "what am I doing" and
  "what have I done" are different questions, and the handler asks for one or the other.
  """

  @callback create(character_id :: String.t(), quest_data :: map()) ::
              {:ok, map()} | {:error, term()}
  @callback get(character_id :: String.t(), quest_id :: String.t()) ::
              {:ok, map()} | {:error, term()}
  @callback list_active(character_id :: String.t()) :: {:ok, list(map())}
  @callback list_all(character_id :: String.t()) :: {:ok, list(map())}
  @callback update(character_id :: String.t(), quest_id :: String.t(), updates :: map()) ::
              {:ok, map()} | {:error, term()}
end
