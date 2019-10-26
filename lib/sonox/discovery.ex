defmodule Sonox.Discovery do
  @moduledoc """
  Module to run the discovery of the speaker inside the current network
  """
  use GenServer

  @playersearch ~S"""
  M-SEARCH * HTTP/1.1
  HOST: 239.255.255.250:1900
  MAN: "ssdp:discover"
  MX: 1
  ST: urn:schemas-upnp-org:device:ZonePlayer:1
  """
  @multicastaddr {239, 255, 255, 250}
  @multicastport 1900

  def start_link(_default) do
    GenServer.start_link(__MODULE__, %Sonox.DiscoverState{}, name: __MODULE__)
  end

  @doc """
  Initialize the GenServer and discover all the player in the local network
  """
  def init(%Sonox.DiscoverState{} = state) do
    ip_addr = get_ip_addr()

    {:ok, socket} =
      :gen_udp.open(0, [
        :binary,
        :inet,
        {:ip, ip_addr},
        {:active, true},
        {:multicast_if, ip_addr},
        {:multicast_ttl, 4},
        {:add_membership, {@multicastaddr, ip_addr}}
      ])

    # fire two udp discover packets immediatly
    :gen_udp.send(socket, @multicastaddr, @multicastport, @playersearch)
    :gen_udp.send(socket, @multicastaddr, @multicastport, @playersearch)
    {:ok, %Sonox.DiscoverState{state | socket: socket}}
  end

  def get_ip_addr do
    cond do
      System.get_env("LISTEN_ON_INTERFACE") != nil ->
        System.get_env("LISTEN_ON_INTERFACE")

      Application.get_env(:sonox, :listen_on_interface) != nil ->
        Application.get_env(:sonox, :listen_on_interface)

      true ->
        nil
    end
    |> get_ip_address()
  end

  defp get_ip_address(name \\ nil) do
    get_ifaddrs()
    |> filter_broadcast
    |> filter_by_name(name)
    |> get_address
  end

  defp get_address({_name, params} = _interface) do
    params
    |> List.keyfind(:addr, 0)
    |> elem(1)
  end

  defp filter_by_name(ifaddrs, name) do
    if is_nil(name) do
      ifaddrs
    else
      ifaddrs
      |> Enum.filter(fn {n, _params} ->
        n == name
      end)
    end
    |> List.first()
  end

  defp filter_broadcast(ifaddrs) do
    ifaddrs
    |> Enum.filter(fn {_name, params} ->
      if is_tuple(params[:addr]) && tuple_size(params[:addr]) == 4 &&
           Enum.member?(params[:flags], :broadcast) do
        true
      else
        false
      end
    end)
  end

  defp get_ifaddrs do
    case :inet.getifaddrs() do
      {:ok, ifaddrs} ->
        ifaddrs

      _ ->
        []
    end
  end

  def handle_info({:udp, _socket, ip, _fromport, packet}, state) do
    %Sonox.DiscoverState{players: players_list} = state

    this_player = parse_upnp_response(ip, packet)

    if this_player do
      {name, icon, config} = attributes(this_player)
      {_, zone_coordinator, _} = group_attributes(this_player)

      this_player = %Sonox.SonosDevice{
        this_player
        | name: name,
          icon: icon,
          config: config,
          coordinator_uuid: zone_coordinator
      }

      this_player =
        this_player
        |> Sonox.Player.audio(:volume)

      players_list = update_player_list(players_list, this_player)

      {:noreply,
       %Sonox.DiscoverState{
         state
         | players: update_player_list(players_list, this_player),
           player_count: Enum.count(players_list)
       }}
    else
      {:noreply, state}
    end
  end

  defp update_player_list(players, player) do
    if knownplayer?(players, player.uuid) do
      update_player(players, player)
    else
      [player | players]
    end
  end

  defp build(id, ip, coord_id, {name, icon, config}) do
    new_player = %Sonox.ZonePlayer{}

    %Sonox.ZonePlayer{
      new_player
      | id: id,
        name: name,
        coordinator_id: coord_id,
        info: %{new_player.info | ip: ip, icon: icon, config: config}
    }
  end

  def player_by_name(name) do
    GenServer.call(__MODULE__, {:player_by_name, name})
  end

  def list_player() do
    GenServer.call(__MODULE__, :list_players)
  end

  def handle_call(:list_players, _from, %Sonox.DiscoverState{players: players_list} = state) do
    res =
      players_list
      |> Enum.map(fn x -> x.name end)

    {:reply, res, state}
  end

  def handle_call(
        {:player_by_name, name},
        _from,
        %Sonox.DiscoverState{players: players_list} = state
      ) do
    res =
      Enum.find(players_list, nil, fn player ->
        player.name == name
      end)

    {:reply, res, state}
  end

  defp knownplayer?(players, uuid) do
    !Enum.empty?(players) &&
      Enum.find_index(players, fn player -> player.uuid == uuid end) != nil
  end

  defp update_player(players, player) do
    List.replace_at(players, Enum.find_index(players, fn n -> n.uuid == player.uuid end), player)
  end

  defp attributes(%Sonox.SonosDevice{} = player) do
    import SweetXml
    {:ok, res_body} = Sonox.SOAP.build(:device, "GetZoneAttributes") |> Sonox.SOAP.post(player)

    {xpath(res_body, ~x"//u:GetZoneAttributesResponse/CurrentZoneName/text()"s),
     xpath(res_body, ~x"//u:GetZoneAttributesResponse/CurrentIcon/text()"s),
     xpath(res_body, ~x"//u:GetZoneAttributesResponse/CurrentConfiguration/text()"i)}
  end

  defp group_attributes(%Sonox.SonosDevice{} = player) do
    import SweetXml

    {:ok, res_body} =
      Sonox.SOAP.build(:zone, "GetZoneGroupAttributes")
      |> Sonox.SOAP.post(player)

    zone_name =
      xpath(res_body, ~x"//u:GetZoneGroupAttributesResponse/CurrentZoneGroupName/text()"s)

    zone_id = xpath(res_body, ~x"//u:GetZoneGroupAttributesResponse/CurrentZoneGroupID/text()"s)

    zone_players_list =
      xpath(
        res_body,
        ~x"//u:GetZoneGroupAttributesResponse/CurrentZonePlayerUUIDsInGroup/text()"ls
      )

    case(zone_name) do
      # this zone is not in a gruop
      "" ->
        {nil, nil, []}

      _ ->
        [clean_zone, _] = String.split(zone_id, ":")
        {zone_name, clean_zone, zone_players_list}
    end
  end

  defp parse_upnp_response(ip, packet) do
    lines = String.split(packet, "\r\n")

    if is_sonos(lines) do
      %Sonox.SonosDevice{
        ip: :inet.ntoa(ip),
        version: get_device_version(lines),
        household: get_device_household(lines),
        model: get_device_model(lines),
        uuid: get_device_uuid(lines)
      }
    end
  end

  defp is_sonos(lines) do
    lines |> Enum.filter(fn line -> String.contains?(line, "Sonos") end) |> Enum.count() > 0
  end

  defp get_device_household(lines) do
    regex = ~r/X-RINCON-HOUSEHOLD: Sonos_(.*)/

    lines
    |> get_capture_groups(regex)
    |> List.first()
  end

  defp get_device_version(lines) do
    regex = ~r/SERVER: Linux UPnP\/\d\.\d Sonos\/(.*?) .*/

    lines
    |> get_capture_groups(regex)
    |> List.first()
  end

  defp get_device_model(lines) do
    regex = ~r/SERVER: Linux UPnP\/\d\.\d Sonos\/.*? \((.*)\)/

    lines
    |> get_capture_groups(regex)
    |> List.first()
  end

  defp get_device_uuid(lines) do
    regex = ~r/USN: uuid:(.*?)::.*/

    lines
    |> get_capture_groups(regex)
    |> List.first()
  end

  defp get_capture_groups(lines, regex) do
    lines
    |> Enum.filter(fn line -> Regex.match?(regex, line) end)
    |> Enum.map(fn line -> Regex.run(regex, line, capture: :all_but_first) end)
    |> List.flatten()
  end

  defp parse_upnp(ip, good_resp) do
    split_resp = String.split(good_resp, "\r\n")
    vers_model = Enum.fetch!(split_resp, 4)

    if String.contains?(vers_model, "Sonos") do
      ["SERVER:", "Linux", "UPnP/1.0", version, model_raw] = String.split(vers_model)
      model = String.lstrip(model_raw, ?() |> String.rstrip(?))
      "USN: uuid:" <> usn = Enum.fetch!(split_resp, 6)
      uuid = String.split(usn, "::") |> Enum.at(0)
      "X-RINCON-HOUSEHOLD: Sonos_" <> household = Enum.fetch!(split_resp, 7)

      %Sonox.SonosDevice{
        ip: :inet.ntoa(ip),
        version: version,
        model: model,
        uuid: uuid,
        household: household
      }
    end
  end

  def zone_group_state(%Sonox.SonosDevice{} = player) do
    import SweetXml

    {:ok, res} =
      Sonox.SOAP.build(:zone, "GetZoneGroupState", [])
      |> Sonox.SOAP.post(player)

    xpath(res, ~x"//ZoneGroupState/text()"s)
    |> xpath(~x"//ZoneGroups/ZoneGroup"l,
      coordinator_uuid: ~x"//./@Coordinator"s,
      members: [
        ~x"//./ZoneGroup/ZoneGroupMember"el,
        name: ~x"//./@ZoneName"s,
        uuid: ~x"//./@UUID"s,
        addr: ~x"//./@Location"s,
        config: ~x"//./@Configuration"i,
        icon: ~x"//./@Icon"s
      ]
    )
  end
end
