defmodule Sonox.DiscoverState do
  @moduledoc """
  Save the discovery state for the player
  """
  defstruct  socket: nil, players: [], player_count: 0
  @type t :: %__MODULE__{socket: pid, players: list, player_count: integer}
end
