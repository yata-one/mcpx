///|
extern "js" fn make_mock_connect_fetch() -> JsFetch =
  #| () => {
  #|   let n = 0;
  #|   return (_method, url, _headersJson, body) => new Promise((resolve) => {
  #|     n += 1;
  #|     if (n === 1) resolve(JSON.stringify({ statusCode: 200, contentType: "application/json", headers: { "Mcp-Session-Id": "sess-1" }, body: JSON.stringify({ jsonrpc: "2.0", id: 1, result: { protocolVersion: "2025-03-26", capabilities: {}, serverInfo: { name: "mock", version: "1" } } }) }));
  #|     else if (n === 2) resolve(JSON.stringify({ statusCode: 202, contentType: null, headers: {}, body: "{}" }));
  #|     else resolve(JSON.stringify({ statusCode: 200, contentType: "application/json", headers: {}, body: JSON.stringify({ jsonrpc: "2.0", id: 2, result: { tools: [{ name: "search", description: "Search", inputSchema: { type: "object" } }] } }) }));
  #|   });
  #| }

///|
extern "js" fn make_mock_list_tools_fetch() -> JsFetch =
  #| () => {
  #|   let n = 0;
  #|   return (_method, url, _headersJson, body) => new Promise((resolve) => {
  #|     n += 1;
  #|     if (n === 1) resolve(JSON.stringify({ statusCode: 200, contentType: "application/json", headers: {}, body: JSON.stringify({ jsonrpc: "2.0", id: 1, result: { protocolVersion: "2025-03-26", capabilities: {}, serverInfo: { name: "mock", version: "1" } } }) }));
  #|     else if (n === 2) resolve(JSON.stringify({ statusCode: 202, contentType: null, headers: {}, body: "{}" }));
  #|     else if (n === 3) resolve(JSON.stringify({ statusCode: 200, contentType: "application/json", headers: {}, body: JSON.stringify({ jsonrpc: "2.0", id: 2, result: { tools: [{ name: "search", description: "Search", inputSchema: { type: "object" } }] } }) }));
  #|     else resolve(JSON.stringify({ statusCode: 200, contentType: "application/json", headers: {}, body: JSON.stringify({ jsonrpc: "2.0", id: 3, result: { tools: [] } }) }));
  #|   });
  #| }

///|
extern "js" fn make_mock_call_tool_fetch() -> JsFetch =
  #| () => {
  #|   let n = 0;
  #|   return (_method, url, _headersJson, body) => new Promise((resolve) => {
  #|     n += 1;
  #|     if (n === 1) resolve(JSON.stringify({ statusCode: 200, contentType: "application/json", headers: {}, body: JSON.stringify({ jsonrpc: "2.0", id: 1, result: { protocolVersion: "2025-03-26", capabilities: {}, serverInfo: { name: "mock", version: "1" } } }) }));
  #|     else if (n === 2) resolve(JSON.stringify({ statusCode: 202, contentType: null, headers: {}, body: "{}" }));
  #|     else if (n === 3) resolve(JSON.stringify({ statusCode: 200, contentType: "application/json", headers: {}, body: JSON.stringify({ jsonrpc: "2.0", id: 2, result: { content: [{ type: "text", text: "hello world" }] } }) }));
  #|     else resolve(JSON.stringify({ statusCode: 200, contentType: "application/json", headers: {}, body: JSON.stringify({ jsonrpc: "2.0", id: 3, result: {} }) }));
  #|   });
  #| }

///|
fn json_field_str(json : Json, key : String) -> String? {
  match json {
    Object(obj) =>
      match obj.get(key) {
        Some(String(s)) => Some(s)
        _ => None
      }
    _ => None
  }
}

///|
fn json_field_array(json : Json, key : String) -> Array[Json]? {
  match json {
    Object(obj) =>
      match obj.get(key) {
        Some(Array(arr)) => Some(arr)
        _ => None
      }
    _ => None
  }
}

///|
fn json_field_object(json : Json, key : String) -> Map[String, Json]? {
  match json {
    Object(obj) =>
      match obj.get(key) {
        Some(Object(o)) => Some(o)
        _ => None
      }
    _ => None
  }
}

///|
async test "js connect returns session JSON with url and sessionId" {
  let session_str = connect(
    make_mock_connect_fetch(),
    url="https://mcp.example/mcp",
  ).wait()
  let json = @json.parse(session_str) catch { _ => Json::null() }
  inspect(
    json_field_str(json, "status"),
    content=(
      #|Some(ok)
    ),
  )
  inspect(
    json_field_str(json, "url"),
    content=(
      #|Some(https://mcp.example/mcp)
    ),
  )
  inspect(
    json_field_str(json, "sessionId"),
    content=(
      #|Some(sess-1)
    ),
  )
}

///|
async test "js list_tools returns tools array" {
  let session_str = connect(
    make_mock_list_tools_fetch(),
    url="https://mcp.example/mcp",
  ).wait()
  let result_str = list_tools(make_mock_list_tools_fetch(), session_str).wait()
  let json = @json.parse(result_str) catch { _ => Json::null() }
  inspect(
    json_field_str(json, "status"),
    content=(
      #|Some(ok)
    ),
  )
  match json_field_array(json, "tools") {
    Some(arr) => inspect(arr.length(), content="1")
    None => inspect(None, content="Some([])")
  }
}

///|
async test "js call_tool returns result" {
  let session_str = connect(
    make_mock_call_tool_fetch(),
    url="https://mcp.example/mcp",
  ).wait()
  let result_str = call_tool(
    make_mock_call_tool_fetch(),
    session_str,
    "search",
    "{}",
  ).wait()
  let json = @json.parse(result_str) catch { _ => Json::null() }
  inspect(
    json_field_str(json, "status"),
    content=(
      #|Some(ok)
    ),
  )
  match json_field_object(json, "result") {
    Some(_) => () // result is an object, good
    None => inspect(None, content="Some({})")
  }
}

///|
async test "js disconnect returns ok" {
  let session_str = connect(
    make_mock_connect_fetch(),
    url="https://mcp.example/mcp",
  ).wait()
  let result_str = disconnect(session_str).wait()
  let json = @json.parse(result_str) catch { _ => Json::null() }
  inspect(
    json_field_str(json, "status"),
    content=(
      #|Some(ok)
    ),
  )
}
