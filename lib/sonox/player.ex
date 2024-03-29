defmodule Sonox.Player do
  @moduledoc """
  General functionality of a sonos player
  """
  require Logger
  import SweetXml
  alias Sonox.SOAP
  alias Sonox.SonosDevice

  def set_name(%SonosDevice{} = device, new_name) do
    {:ok, _} =
      SOAP.build(:device, "SetZoneAttributes", [
        ["DesiredZoneName", new_name],
        ["DesiredIcon", device.icon],
        ["DesiredConfiguration", device.config]
      ])
      |> SOAP.post(device)
  end

  def control(%SonosDevice{} = device, action) do
    act_str =
      case(action) do
        :play -> "Play"
        :pause -> "Pause"
        :stop -> "Stop"
        :prev -> "Previous"
        :next -> "Next"
      end

    SOAP.build(:av, act_str, [["InstanceID", 0], ["Speed", 1]])
    |> SOAP.post(device)
  end

  def transport_info(%SonosDevice{} = device) do
    SOAP.build(:av, "GetTransportInfo", [["InstanceID", 0]])
    |> SOAP.post(device)
  end

  def position_info(%SonosDevice{} = device) do
    SOAP.build(:av, "GetPositionInfo", [["InstanceID", 0]])
    |> SOAP.post(device)
  end

  def group(%SonosDevice{} = device, :leave) do
    SOAP.build(:av, "BecomeCoordinatorOfStandaloneGroup", [["InstanceID", 0]])
    |> SOAP.post(device)
  end

  def group(%SonosDevice{} = device, :join, coordinator_name) do
    coordinator = Sonox.Discovery.player_by_name(coordinator_name)

    args = [
      ["InstanceID", 0],
      ["CurrentURI", "x-rincon:" <> coordinator.usnID],
      ["CurrentURIMetaData", ""]
    ]

    SOAP.build(:av, "SetAVTransportURI", args)
    |> SOAP.post(device)
  end

  def audio(%SonosDevice{} = device, :volume, level) when level > 0 and level < 100 do
    args = [["InstanceID", 0], ["Channel", "Master"], ["DesiredVolume", level]]

    SOAP.build(:renderer, "SetVolume", args)
    |> SOAP.post(device)

    device
    |> audio(:volume)
  end

  def audio(%SonosDevice{} = device, :volume) do
    args = [["InstanceID", 0], ["Channel", "Master"]]

    {:ok, response} = SOAP.build(:renderer, "GetVolume", args)
    |> SOAP.post(device)

    volume = response
    |> xpath(~x"//CurrentVolume/text()"s)
    |> String.to_integer()

    %{device | volume: volume}
  end

  # defp refresh_zones({:ok, response_body}) do
  #   Sonox.Discovery.discover()
  #   {:ok, response_body}
  # end

  # defp refresh_zones({:error, err_msg}) do
  #   {:error, err_msg}
  # end

  def group(%SonosDevice{} = player) do
    player
    |> Sonox.Discovery.zone_group_state()
    |> Enum.filter(fn x ->
      get_in(x, [:members]) |> Enum.find_value(fn x -> x.uuid == player.uuid end)
    end)
  end

  def is_group_member(%SonosDevice{} = player) do
    player
    |> group()
    |> List.first()
    |> get_in([:members])
    |> Enum.count() > 1
  end

end
