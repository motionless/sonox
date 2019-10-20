defmodule Sonox.ZonePlayer do
  @moduledoc """
  """

  defstruct id: nil,
            name: nil,
            coordinator_id: nil,
            info: %{icon: nil, ip: nil, config: nil},
            player_state: %PlayerState{}

  @type t :: %__MODULE__{
          name: String.t(),
          coordinator_id: String.t(),
          info: map,
          player_state: PlayerState.t()
        }
end
