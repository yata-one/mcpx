///|
pub async fn list_tools(
  fetch : async (HttpRequest) -> HttpResponse,
  endpoint : Endpoint,
) -> Array[@protocol.McpToolInfo] raise McpHttpClientError {
  let request = @protocol.mcp_tools_list_request(
    id=1,
    client_name="mcpx",
    client_version="0.1.2",
  )
  let response = post_json(
    fetch,
    endpoint,
    build_headers(endpoint.headers, rpc_method="tools/list", rpc_name=None),
    request,
  )
  if response.status_code == 400 {
    if should_try_legacy_fallback(response) {
      return list_tools_legacy(fetch, endpoint)
    }
    raise jsonrpc_error(response)
  }
  let json = response_json(response)
  match @protocol.decode_mcp_tool_list_response(json, expected_id=1) {
    Ok(value) => value
    Err(_) => raise McpHttpClientError::Protocol("mcp protocol error")
  }
}

///|
pub async fn call_tool(
  fetch : async (HttpRequest) -> HttpResponse,
  endpoint : Endpoint,
  tool_name~ : String,
  arguments~ : Json,
) -> Json raise McpHttpClientError {
  let request = @protocol.mcp_tool_call_request(
    id=1,
    name=tool_name,
    arguments~,
    client_name="mcpx",
    client_version="0.1.2",
  )
  let response = post_json(
    fetch,
    endpoint,
    build_headers(
      endpoint.headers,
      rpc_method="tools/call",
      rpc_name=Some(tool_name),
    ),
    request,
  )
  if response.status_code == 400 {
    if should_try_legacy_fallback(response) {
      return call_tool_legacy(fetch, endpoint, tool_name~, arguments~)
    }
    raise jsonrpc_error(response)
  }
  let json = response_json(response)
  @protocol.decode_mcp_result(json, expected_id=1) catch {
    _ => raise McpHttpClientError::Protocol("mcp protocol error")
  }
}

///|
async fn list_tools_legacy(
  fetch : async (HttpRequest) -> HttpResponse,
  endpoint : Endpoint,
) -> Array[@protocol.McpToolInfo] raise McpHttpClientError {
  let session_id = Ref(None)
  let client = @protocol.mcp_client(
    client_name="mcpx",
    client_version="0.1.2",
    protocol_version=@protocol.MCP_PROTOCOL_VERSION_LEGACY,
  )
  initialize_legacy(fetch, endpoint, client, session_id)
  let list = client.tools_list_request()
  let list_response = send_json_legacy(
    fetch,
    endpoint,
    session_id,
    list.message,
  )
  let json = payload_json(list_response)
  client.accept_tools_list_response(list, json) catch {
    _ => raise McpHttpClientError::Protocol("mcp protocol error")
  }
}

///|
async fn call_tool_legacy(
  fetch : async (HttpRequest) -> HttpResponse,
  endpoint : Endpoint,
  tool_name~ : String,
  arguments~ : Json,
) -> Json raise McpHttpClientError {
  let session_id = Ref(None)
  let client = @protocol.mcp_client(
    client_name="mcpx",
    client_version="0.1.2",
    protocol_version=@protocol.MCP_PROTOCOL_VERSION_LEGACY,
  )
  initialize_legacy(fetch, endpoint, client, session_id)
  let call = client.tool_call_request(name=tool_name, arguments~)
  let call_response = send_json_legacy(
    fetch,
    endpoint,
    session_id,
    call.message,
  )
  let json = payload_json(call_response)
  client.accept_tool_call_response(call, json) catch {
    _ => raise McpHttpClientError::Protocol("mcp protocol error")
  }
}

///|
async fn initialize_legacy(
  fetch : async (HttpRequest) -> HttpResponse,
  endpoint : Endpoint,
  client : @protocol.McpClient,
  session_id : Ref[String?],
) -> Unit raise McpHttpClientError {
  let init = client.initialize_request()
  let init_response = send_json_legacy(
    fetch,
    endpoint,
    session_id,
    init.message,
  )
  let init_json = payload_json(init_response)
  ignore(
    client.accept_initialize_response(init, init_json) catch {
      _ => raise McpHttpClientError::Protocol("mcp protocol error")
    },
  )
  let initialized = client.initialized_notification()
  ignore(send_json_legacy(fetch, endpoint, session_id, initialized.message))
}

///|
async fn send_json_legacy(
  fetch : async (HttpRequest) -> HttpResponse,
  endpoint : Endpoint,
  session_id : Ref[String?],
  message : Json,
) -> @protocol.McpTransportPayload raise McpHttpClientError {
  let response = post_json(
    fetch,
    endpoint,
    build_headers_legacy(endpoint.headers, session_id.val),
    message,
  )
  update_session_id(session_id, response.headers)
  if response.status_code != 200 && response.status_code != 202 {
    raise McpHttpClientError::HttpStatus(response.status_code)
  }
  let payload = @protocol.decode_mcp_transport_payload(
    @protocol.mcp_transport_response(
      status_code=response.status_code,
      content_type=response.content_type,
      body=response.body,
    ),
  )
  match payload {
    Ok(value) => value
    Err(_) => raise McpHttpClientError::Protocol("mcp protocol error")
  }
}

///|
async fn post_json(
  fetch : async (HttpRequest) -> HttpResponse,
  endpoint : Endpoint,
  headers : Map[String, String],
  message : Json,
) -> HttpResponse raise McpHttpClientError {
  fetch({
    http_method: "POST",
    url: endpoint.url,
    headers,
    body: message.stringify(),
  }) catch {
    err => raise McpHttpClientError::Protocol(err.to_string())
  }
}

///|
fn response_json(response : HttpResponse) -> Json raise McpHttpClientError {
  if response.status_code != 200 && response.status_code != 202 {
    raise McpHttpClientError::HttpStatus(response.status_code)
  }
  let payload = @protocol.decode_mcp_transport_payload(
    @protocol.mcp_transport_response(
      status_code=response.status_code,
      content_type=response.content_type,
      body=response.body,
    ),
  )
  let payload = match payload {
    Ok(value) => value
    Err(_) => raise McpHttpClientError::Protocol("mcp protocol error")
  }
  payload_json(payload)
}

///|
fn payload_json(
  payload : @protocol.McpTransportPayload,
) -> Json raise McpHttpClientError {
  @protocol.expect_json_payload(payload) catch {
    _ => raise McpHttpClientError::Protocol("mcp protocol error")
  }
}

///|
fn build_headers_legacy(
  base_headers : Map[String, String],
  session_id : String?,
) -> Map[String, String] {
  let headers = base_headers.copy()
  headers["content-type"] = "application/json"
  headers["accept"] = "application/json, text/event-stream"
  match session_id {
    Some(value) => headers["Mcp-Session-Id"] = value
    None => ()
  }
  headers
}

///|
fn build_headers(
  base_headers : Map[String, String],
  rpc_method~ : String,
  rpc_name~ : String?,
) -> Map[String, String] {
  let headers = base_headers.copy()
  headers["content-type"] = "application/json"
  headers["accept"] = "application/json, text/event-stream"
  headers["MCP-Protocol-Version"] = @protocol.MCP_PROTOCOL_VERSION
  headers["Mcp-Method"] = rpc_method
  match rpc_name {
    Some(value) => headers["Mcp-Name"] = value
    None => ()
  }
  headers
}

///|
fn should_try_legacy_fallback(response : HttpResponse) -> Bool {
  if response.status_code != 400 {
    return false
  }
  if response.body.trim().is_empty() {
    return true
  }
  let json = @json.parse(response.body) catch { _ => return true }
  match jsonrpc_error_code(json) {
    Some(code) => !is_protocol_defined_error_code(code)
    None => true
  }
}

///|
fn jsonrpc_error(response : HttpResponse) -> McpHttpClientError {
  let json = @json.parse(response.body) catch {
    _ => return McpHttpClientError::HttpStatus(response.status_code)
  }
  match jsonrpc_error_detail(json) {
    Some((code, message)) =>
      McpHttpClientError::Protocol(
        "json-rpc error " + code.to_string() + ": " + message,
      )
    None => McpHttpClientError::HttpStatus(response.status_code)
  }
}

///|
fn jsonrpc_error_detail(json : Json) -> (Int, String)? {
  match json {
    Object(obj) =>
      match obj.get("error") {
        Some(Object(error)) => {
          let code = match error.get("code") {
            Some(Number(value, ..)) => Some(value.to_int())
            _ => None
          }
          let message = match error.get("message") {
            Some(String(value)) => Some(value)
            _ => None
          }
          match (code, message) {
            (Some(code), Some(message)) => Some((code, message))
            _ => None
          }
        }
        _ => None
      }
    _ => None
  }
}

///|
fn jsonrpc_error_code(json : Json) -> Int? {
  match json {
    Object(obj) =>
      match obj.get("error") {
        Some(Object(error)) =>
          match error.get("code") {
            Some(Number(value, ..)) => Some(value.to_int())
            _ => None
          }
        _ => None
      }
    _ => None
  }
}

///|
fn is_protocol_defined_error_code(code : Int) -> Bool {
  // Keep -32000-style implementation errors eligible for legacy session fallback.
  code == -32700 || // Parse error
  code == -32600 || // Invalid Request
  code == -32601 || // Method not found
  code == -32602 || // Invalid params
  code == -32603 || // Internal error
  code == -32004 || // UnsupportedProtocolVersion; not retry legacy stateful session approach
  code == -32001 // HeaderMismatch
}

///|
fn update_session_id(
  session_id : Ref[String?],
  headers : Map[String, String],
) -> Unit {
  match header(headers, "Mcp-Session-Id") {
    Some(value) => session_id.val = Some(value)
    None => ()
  }
}

///|
fn header(headers : Map[String, String], key : String) -> String? {
  match headers.get(key) {
    Some(value) => Some(value)
    None => headers.get(key.to_lower())
  }
}
