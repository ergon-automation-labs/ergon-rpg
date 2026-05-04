defmodule BotArmyRpg.DiceRoller do
  @moduledoc """
  Pure module for rolling dice using standard RPG notation.

  Supports:
    - "d20"           -> 1d20
    - "2d6"           -> 2 six-sided dice
    - "1d20+5"        -> roll + modifier
    - "2d6+1d8+3"    -> multiple dice groups with modifiers
    - "1d20-2"       -> negative modifier

  No GenServer, no DB, no NATS. Pure functions.
  """

  @dice_pattern ~r/(\d*)d(\d+)/
  @modifier_pattern ~r/([+-]\d+)(?!.*d)/

  @spec roll(notation :: String.t()) :: {:ok, map()} | {:error, term()}
  def roll(notation) when is_binary(notation) do
    with {:ok, dice_groups, modifier} <- parse(notation) do
      rolls =
        Enum.map(dice_groups, fn %{count: count, sides: sides} ->
          individual = Enum.map(1..count, fn _ -> :rand.uniform(sides) end)
          subtotal = Enum.sum(individual)

          %{
            "count" => count,
            "sides" => sides,
            "rolls" => individual,
            "subtotal" => subtotal
          }
        end)

      dice_total = Enum.map(rolls, & &1["subtotal"]) |> Enum.sum()
      total = dice_total + modifier

      {:ok,
       %{
         "notation" => notation,
         "total" => total,
         "rolls" => rolls,
         "modifier" => modifier
       }}
    end
  end

  def roll(_), do: {:error, :invalid_notation}

  @spec parse(notation :: String.t()) :: {:ok, list(map()), integer()} | {:error, term()}
  def parse(notation) when is_binary(notation) do
    normalized = String.replace(notation, ~r/\s/, "")

    if String.length(normalized) == 0 do
      {:error, :empty_notation}
    else
      dice_matches = Regex.scan(@dice_pattern, normalized, capture: :all)

      dice_groups =
        Enum.map(dice_matches, fn [_full, count_str, sides_str] ->
          count = if count_str == "", do: 1, else: String.to_integer(count_str)
          sides = String.to_integer(sides_str)

          if sides < 1, do: {:error, :invalid_sides}, else: %{count: count, sides: sides}
        end)

      errors = Enum.filter(dice_groups, &match?({:error, _}, &1))

      if dice_matches == [] do
        {:error, :no_dice_found}
      else
        if errors != [] do
          {:error, :invalid_notation}
        else
          modifier = parse_modifier(normalized)
          {:ok, dice_groups, modifier}
        end
      end
    end
  end

  def parse(_), do: {:error, :invalid_notation}

  defp parse_modifier(notation) do
    case Regex.run(@modifier_pattern, notation, capture: :all_but_first) do
      [mod_str] -> String.to_integer(mod_str)
      [] -> 0
      nil -> 0
    end
  end
end
