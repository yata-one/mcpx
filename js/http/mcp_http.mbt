///|
#external
pub type JsFetch

///|
extern "js" fn call_js_fetch(
  fetch : JsFetch,
  http_method : String,
  url : String,
  headers_json : String,
  body : String,
) -> @js_async.Promise[String] =
  #| (fetch, httpMethod, url, headersJson, body) => fetch(httpMethod, url, headersJson, body)

///|
/// A session handle returned by `connect`.
/// Contains the resolved URL, headers, and the MCP session ID.
pub struct JsSession {
  server : String
  url : String
  headers : Map[String, String]
  session_id : String?
} derive(Debug)

///|
/// Connect to an MCP server via HTTP transport.
/// Performs the initialize → initialized handshake and returns a `JsSession`.
pub fn connect(
  fetch : JsFetch,
  url~ : String,
  headers? : Map[String, String] = Map([]),
) -> @js_async.Promise[String] {
  @js_async.Promise::from_async(() => {
    let adapter = js_fetch_adapter(fetch)
    let client = @protocol.mcp_client(
      client_name="mcpx",
      client_version="0.1.0",
    )
    let session_id = Ref(None)
    let endpoint = @core_http.http_endpoint(url~, headers~)
    do_http_initialize(adapter, endpoint, client, session_id)
    let sid = session_id.val
    let sess = { server: url, url, headers, session_id: sid }
    let sess_json = session_to_json(sess)
    let obj : Map[String, Json] = match sess_json {
      Object(o) => o
      _ => Map([])
    }
    obj["status"] = Json::string("ok")
    Json::object(obj).stringify()
  })
}

///|
/// List available tools on a connected session.
pub fn list_tools(
  fetch : JsFetch,
  session_json : String,
) -> @js_async.Promise[String] {
  @js_async.Promise::from_async(() => {
    let sess = parse_session(session_json)
    let adapter = js_fetch_adapter(fetch)
    let client = @protocol.mcp_client(
      client_name="mcpx",
      client_version="0.1.0",
    )
    let session_id = Ref(sess.session_id)
    let endpoint = @core_http.http_endpoint(url=sess.url, headers=sess.headers)
    do_http_initialize(adapter, endpoint, client, session_id)
    let list = client.tools_list_request()
    let list_response = do_send_json(
      adapter,
      endpoint,
      session_id,
      list.message,
    )
    let json = expect_payload_json(list_response)
    let tools = client.accept_tools_list_response(list, json) catch {
      _ => return error_json("mcp protocol error")
    }
    let arr = tools.map(tool_info_json)
    Json::object({ "status": Json::string("ok"), "tools": Json::array(arr) }).stringify()
  })
}

///|
/// Call a tool on a connected session.
pub fn call_tool(
  fetch : JsFetch,
  session_json : String,
  tool_name : String,
  arguments_json : String,
) -> @js_async.Promise[String] {
  @js_async.Promise::from_async(() => {
    let sess = parse_session(session_json)
    let arguments = @json.parse(arguments_json) catch { _ => Json::object({}) }
    let adapter = js_fetch_adapter(fetch)
    let client = @protocol.mcp_client(
      client_name="mcpx",
      client_version="0.1.0",
    )
    let session_id = Ref(sess.session_id)
    let endpoint = @core_http.http_endpoint(url=sess.url, headers=sess.headers)
    do_http_initialize(adapter, endpoint, client, session_id)
    let call = client.tool_call_request(name=tool_name, arguments~)
    let call_response = do_send_json(
      adapter,
      endpoint,
      session_id,
      call.message,
    )
    let json = expect_payload_json(call_response)
    let result = client.accept_tool_call_response(call, json) catch {
      _ => return error_json("mcp protocol error")
    }
    Json::object({ "status": Json::string("ok"), "result": result }).stringify()
  })
}

///|
/// Disconnect from a session.
/// For HTTP transport this is a no-op (stateless connections).
/// Returns the session JSON unchanged for API consistency.
pub fn disconnect(session_json : String) -> @js_async.Promise[String] {
  @js_async.Promise::from_async(() => {
    let _sess = parse_session(session_json)
    Json::object({ "status": Json::string("ok") }).stringify()
  })
}

// ---------------------------------------------------------------------------
// HTTP transport helpers (mirrors core/http/client.mbt but uses JsSession)
// ---------------------------------------------------------------------------

///|
async fn do_http_initialize(
  fetch : async (@core_http.HttpRequest) -> @core_http.HttpResponse,
  endpoint : @core_http.Endpoint,
  client : @protocol.McpClient,
  session_id : Ref[String?],
) -> Unit {
  let init = client.initialize_request()
  let init_response = do_send_json(fetch, endpoint, session_id, init.message)
  let init_json = expect_payload_json(init_response)
  ignore(try? client.accept_initialize_response(init, init_json))
  let initialized = client.initialized_notification()
  ignore(do_send_json(fetch, endpoint, session_id, initialized.message))
}

///|
async fn do_send_json(
  fetch : async (@core_http.HttpRequest) -> @core_http.HttpResponse,
  endpoint : @core_http.Endpoint,
  session_id : Ref[String?],
  message : Json,
) -> @protocol.McpTransportPayload {
  let request = @core_http.http_request(
    http_method="POST",
    url=endpoint.url,
    headers=build_headers(endpoint.headers, session_id.val),
    body=message.stringify(),
  )
  let response = fetch(request) catch {
    _ => return @protocol.McpTransportPayload::AcceptedNoContent
  }
  update_session_id(session_id, response.headers)
  let transport_response = @protocol.mcp_transport_response(
    status_code=response.status_code,
    content_type=response.content_type,
    body=response.body,
  )
  match @protocol.decode_mcp_transport_payload(transport_response) {
    Ok(value) => value
    Err(_) => @protocol.McpTransportPayload::AcceptedNoContent
  }
}

///|
fn expect_payload_json(payload : @protocol.McpTransportPayload) -> Json {
  match payload {
    @protocol.McpTransportPayload::JsonPayload(json) => json
    @protocol.McpTransportPayload::AcceptedNoContent => Json::object({})
  }
}

// ---------------------------------------------------------------------------
// Session JSON serialization
// ---------------------------------------------------------------------------

///|
fn session_to_json(sess : JsSession) -> Json {
  let obj : Map[String, Json] = Map([])
  obj["server"] = Json::string(sess.server)
  obj["url"] = Json::string(sess.url)
  obj["headers"] = string_map_to_json(sess.headers)
  match sess.session_id {
    Some(sid) => obj["sessionId"] = Json::string(sid)
    None => ()
  }
  Json::object(obj)
}

///|
fn parse_session(json_str : String) -> JsSession {
  let json = @json.parse(json_str) catch {
    _ => return { server: "", url: "", headers: Map([]), session_id: None }
  }
  let obj = match json {
    Object(o) => o
    _ => return { server: "", url: "", headers: Map([]), session_id: None }
  }
  let server = match obj.get("server") {
    Some(String(v)) => v
    _ => ""
  }
  let url = match obj.get("url") {
    Some(String(v)) => v
    _ => ""
  }
  let headers = match obj.get("headers") {
    Some(Object(values)) => json_string_map(values)
    _ => Map([])
  }
  let session_id = match obj.get("sessionId") {
    Some(String(v)) => Some(v)
    _ => None
  }
  { server, url, headers, session_id }
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

///|
fn js_fetch_adapter(
  fetch : JsFetch,
) -> async (@core_http.HttpRequest) -> @core_http.HttpResponse {
  request => {
    let result_json = call_js_fetch(
      fetch,
      request.http_method,
      request.url,
      string_map_to_json(request.headers).stringify(),
      request.body,
    ).wait()
    decode_js_http_response(result_json)
  }
}

///|
fn decode_js_http_response(text : String) -> @core_http.HttpResponse {
  let json = @json.parse(text) catch {
    _ => return @core_http.http_response(status_code=599, body=text)
  }
  let obj = match json {
    Object(obj) => obj
    _ => return @core_http.http_response(status_code=599, body=text)
  }
  let status_code = int_field(obj, "statusCode").unwrap_or(599)
  let content_type = string_field(obj, "contentType")
  let body = string_field(obj, "body").unwrap_or("")
  let headers = match obj.get("headers") {
    Some(Object(values)) => json_string_map(values)
    _ => Map([])
  }
  @core_http.http_response(status_code~, content_type~, headers~, body~)
}

///|
fn build_headers(
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
fn update_session_id(
  session_id : Ref[String?],
  headers : Map[String, String],
) -> Unit {
  match header_value(headers, "Mcp-Session-Id") {
    Some(value) => session_id.val = Some(value)
    None => ()
  }
}

///|
fn header_value(headers : Map[String, String], key : String) -> String? {
  match headers.get(key) {
    Some(value) => Some(value)
    None => headers.get(key.to_lower())
  }
}

///|
fn tool_info_json(tool : @protocol.McpToolInfo) -> Json {
  let obj : Map[String, Json] = Map([])
  obj["name"] = Json::string(tool.name)
  match tool.description {
    Some(description) => obj["description"] = Json::string(description)
    None => ()
  }
  obj["inputSchema"] = tool.input_schema
  Json::object(obj)
}

///|
fn error_json(message : String) -> String {
  Json::object({
    "status": Json::string("error"),
    "error": Json::string(message),
  }).stringify()
}

///|
fn int_field(obj : Map[String, Json], key : String) -> Int? {
  match obj.get(key) {
    Some(Number(value, ..)) if value.trunc() == value => Some(value.to_int())
    _ => None
  }
}

///|
fn string_field(obj : Map[String, Json], key : String) -> String? {
  match obj.get(key) {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
fn json_string_map(obj : Map[String, Json]) -> Map[String, String] {
  let out : Map[String, String] = Map([])
  for key, value in obj {
    match value {
      String(text) => out[key] = text
      _ => ()
    }
  }
  out
}

///|
fn string_map_to_json(values : Map[String, String]) -> Json {
  let obj : Map[String, Json] = Map([])
  for key, value in values {
    obj[key] = Json::string(value)
  }
  Json::object(obj)
}
