defmodule Sonox.SOAP do
  require EEx
  import SweetXml

  @moduledoc """
  Functions for generating and sending Sonos SOAP requests via HTTP
  """

  defmodule SOAPReq do
    @moduledoc """
    Struct that represents the contents of a Sonos XML SOAP request
    Typically only requires method and params
    Build using build() function, it will automatically fill in namespace based on specific service
    """

    defstruct path: nil, method: nil, namespace: nil, header: nil, params: []

    @type t :: %__MODULE__{
            path: String.t(),
            method: String.t(),
            namespace: String.t(),
            header: String.t(),
            params: list(list)
          }
  end

  @doc """
  Generates a SOAP XML for the Sonos API based on SOAPReq Struct
  """
  EEx.function_from_file(:def, :gen, Path.expand("./lib/sonox/templates/request.xml.eex"), [
    :soap_req_struct
  ])

  @doc """
  Build a SOAPReq Struct, to be passed to post function
  """
  def build(service_atom, method, params \\ [], event \\ false) do
    serv = Sonox.Service.get(service_atom)

    req_path =
      case(event) do
        false -> serv.control
        true -> serv.event
      end

    %SOAPReq{method: method, namespace: serv.type, path: req_path, params: params}
  end

  @doc """
  Generates XML request body and sends via HTTP post to specified %SonosDevice{}
  Returns response body as XML, or error based on codes
  """
  def post(%SOAPReq{} = req, %Sonox.SonosDevice{} = player) do
    req_headers = gen_headers(req)
    req_body = gen(req)
    uri = "http://#{player.ip}:1400#{req.path}"
    res = HTTPoison.post!(uri, req_body, req_headers)

    case(res) do
      %HTTPoison.Response{status_code: 200, body: res_body} ->
        {:ok, res_body}

      %HTTPoison.Response{status_code: 500, body: res_err} ->
        case(req.namespace) do
          "urn:schemas-upnp-org:service:ContentDirectory:1" ->
            {:error, parse_soap_error(res_err, true)}

          _ ->
            {:error, parse_soap_error(res_err)}
        end
    end
  end

  defp gen_headers(soap_req) do
    %{
      "Content-Type" => "text/xml; charset=\"utf-8\"",
      "SOAPACTION" => "\"#{soap_req.namespace}##{soap_req.method}\""
    }
  end

  @soap_errors %{
    400 => "Bad Request",
    401 => "Invalid Action",
    402 => "Invalid Args",
    404 => "Invalid Var",
    412 => "Precondition Failed",
    501 => "Action Failed",
    600 => "Argument Value Invalid",
    601 => "Argument Value Out of Range",
    602 => "Optional Action Not Implemented",
    603 => "Out Of Memory",
    604 => "Human Intervention Required",
    605 => "String Argument Too Long",
    606 => "Action Not Authorized",
    607 => "Signature Failure",
    608 => "Signature Missing",
    609 => "Not Encrypted",
    610 => "Invalid Sequence",
    611 => "Invalid Control URL",
    612 => "No Such Session",
    701 => "Transition not available",
    702 => "No contents",
    703 => "Read error",
    704 => "Format not supported for playback",
    705 => "Transport is locked",
    706 => "Write error",
    707 => "Media is protected or not writeable",
    708 => "Format not supported for recording",
    709 => "Media is full",
    710 => "Seek mode not supported",
    711 => "Illegal seek target",
    712 => "Play mode not supported",
    713 => "Record quality not supported",
    714 => "Illegal MIME-Type",
    715 => "Content BUSY",
    716 => "Resource Not found",
    717 => "Play speed not supported",
    718 => "Invalid InstanceID",
    719 => "Destination resource access denied",
    720 => "Cannot process the request",
    737 => "No DNS Server",
    738 => "Bad Domain Name",
    739 => "Server Error",
    :content_dir_req => %{
      701 => "No such object",
      702 => "Invalid CurrentTagValue",
      703 => "Invalid NewTagValue",
      704 => "Required tag",
      705 => "Read only tag",
      706 => "Parameter Mismatch",
      708 => "Unsupported or invalid search criteria",
      709 => "Unsupported or invalid sort criteria",
      710 => "No such container",
      711 => "Restricted object",
      712 => "Bad metadata",
      713 => "Restricted parent object",
      714 => "No such source resource",
      715 => "Resource access denied",
      716 => "Transfer busy",
      717 => "No such file transfer",
      718 => "No such destination resource"
    }
  }

  def parse_soap_error(err_body, content_dir_req \\ false) do
    # https://github.com/SoCo/SoCo/blob/master/soco/services.py
    # For error codes, see table 2.7.16 in
    # http://upnp.org/specs/av/UPnP-av-ContentDirectory-v1-Service.pdf
    # http://upnp.org/specs/av/UPnP-av-AVTransport-v1-Service.pdf
    error_message =
      if content_dir_req do
        @soap_errors[:content_dir_req][xpath(err_body, ~x"//UPnPError/errorCode/text()"i)]
      else
        @soap_errors[xpath(err_body, ~x"//UPnPError/errorCode/text()"i)]
      end
    if is_nil(error_message) do
      "Unknown Error"
    else
      error_message
    end
  end

end
