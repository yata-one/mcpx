///|
async test "core http: list tools starts with 2026 stateless tools/list" {
  let seen : Array[HttpRequest] = []
  let tools = list_tools(
    req => {
      seen.push(req)
      http_response(
        status_code=200,
        content_type=Some("application/json"),
        body=(
          #|{"jsonrpc":"2.0","id":1,"result":{"tools":[{"name":"search","description":"Search","inputSchema":{"type":"object"}}]}}
        ),
      )
    },
    http_endpoint(url="https://mcp.example/mcp"),
  )
  inspect(tools.length(), content="1")
  inspect(tools[0].name, content="search")
  inspect(seen.length(), content="1")
  inspect(rpc_method(seen[0].body), content="tools/list")
  inspect(header(seen[0].headers, "MCP-Protocol-Version"), content="2026-07-28")
  inspect(header(seen[0].headers, "Mcp-Method"), content="tools/list")
  inspect(header(seen[0].headers, "Mcp-Name"), content="")
  inspect(seen[0].body.contains("\"initialize\""), content="false")
  inspect(
    seen[0].body.contains(
      "\"io.modelcontextprotocol/protocolVersion\":\"2026-07-28\"",
    ),
    content="true",
  )
  inspect(
    seen[0].body.contains("\"io.modelcontextprotocol/clientInfo\""),
    content="true",
  )
  inspect(
    seen[0].body.contains("\"io.modelcontextprotocol/clientCapabilities\""),
    content="true",
  )
}

///|
async test "core http: call tool starts with 2026 stateless tools/call" {
  let seen : Array[HttpRequest] = []
  let result = call_tool(
    req => {
      seen.push(req)
      http_response(
        status_code=200,
        content_type=Some("application/json"),
        body=(
          #|{"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"ok"}]}}
        ),
      )
    },
    http_endpoint(url="https://mcp.example/mcp"),
    tool_name="search",
    arguments=Json::object({ "q": Json::string("moonbit") }),
  )
  inspect(
    result.stringify(),
    content=(
      #|{"content":[{"type":"text","text":"ok"}]}
    ),
  )
  inspect(seen.length(), content="1")
  inspect(rpc_method(seen[0].body), content="tools/call")
  inspect(header(seen[0].headers, "MCP-Protocol-Version"), content="2026-07-28")
  inspect(header(seen[0].headers, "Mcp-Method"), content="tools/call")
  inspect(header(seen[0].headers, "Mcp-Name"), content="search")
  inspect(seen[0].body.contains("\"initialize\""), content="false")
  inspect(
    seen[0].body.contains(
      "\"io.modelcontextprotocol/protocolVersion\":\"2026-07-28\"",
    ),
    content="true",
  )
  inspect(seen[0].body.contains("\"name\":\"search\""), content="true")
}

///|
async test "core http legacy fallback: protocol-defined 400 json-rpc errors do not fallback" {
  let codes = [-32700, -32600, -32601, -32602, -32603, -32004, -32001]
  for code in codes {
    let seen : Array[String] = []
    let result : Result[Array[@protocol.McpToolInfo], McpHttpClientError] = try? list_tools(
      req => {
        seen.push(rpc_method(req.body))
        http_response(
          status_code=400,
          content_type=Some("application/json"),
          body=(
              #|{"jsonrpc":"2.0","id":1,"error":{"code":
            ) +
            code.to_string() +
            (
              #|,"message":"defined"}}
            ),
        )
      },
      http_endpoint(url="https://mcp.example/mcp"),
    )
    @debug.debug_inspect(
      result,
      content="Err(Protocol(\"json-rpc error " +
        code.to_string() +
        ": defined\"))",
    )
    inspect(seen.join(","), content="tools/list")
  }
}

///|
async test "core http legacy fallback: session-required 400 falls back to legacy list flow" {
  let seen : Array[String] = []
  let sessions : Array[String] = []
  let tools = list_tools(
    req => {
      let rpc = rpc_method(req.body)
      seen.push(rpc)
      sessions.push(header(req.headers, "Mcp-Session-Id"))
      if rpc == "tools/list" && seen.length() == 1 {
        http_response(
          status_code=400,
          content_type=Some("application/json"),
          body=(
            #|{"jsonrpc":"2.0","id":1,"error":{"code":-32000,"message":"Bad Request: No valid session ID provided"}}
          ),
        )
      } else if rpc == "initialize" {
        http_response(
          status_code=200,
          content_type=Some("application/json"),
          headers={ "Mcp-Session-Id": "sid123" },
          body=(
            #|{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","capabilities":{},"serverInfo":{"name":"mock","version":"1"}}}
          ),
        )
      } else if rpc == "notifications/initialized" {
        http_response(status_code=202, content_type=None, body="")
      } else {
        http_response(
          status_code=200,
          content_type=Some("application/json"),
          body=(
            #|{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"search","description":"Search","inputSchema":{"type":"object"}}]}}
          ),
        )
      }
    },
    http_endpoint(url="https://mcp.example/mcp"),
  )
  inspect(tools.length(), content="1")
  inspect(
    seen.join(","),
    content="tools/list,initialize,notifications/initialized,tools/list",
  )
  inspect(sessions.join(","), content=",,sid123,sid123")
}

///|
async test "core http legacy fallback: empty or invalid 400 body falls back to legacy call flow" {
  let bodies = ["", "not json"]
  for body in bodies {
    let seen : Array[String] = []
    let result = call_tool(
      req => {
        let rpc = rpc_method(req.body)
        seen.push(rpc)
        if rpc == "tools/call" && seen.length() == 1 {
          http_response(status_code=400, content_type=Some("text/plain"), body~)
        } else if rpc == "initialize" {
          http_response(
            status_code=200,
            content_type=Some("application/json"),
            headers={ "Mcp-Session-Id": "sid-call" },
            body=(
              #|{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","capabilities":{},"serverInfo":{"name":"mock","version":"1"}}}
            ),
          )
        } else if rpc == "notifications/initialized" {
          http_response(status_code=202, content_type=None, body="")
        } else {
          http_response(
            status_code=200,
            content_type=Some("application/json"),
            body=(
              #|{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"ok"}]}}
            ),
          )
        }
      },
      http_endpoint(url="https://mcp.example/mcp"),
      tool_name="search",
      arguments=Json::object({ "q": Json::string("moonbit") }),
    )
    inspect(
      result.stringify(),
      content="{\"content\":[{\"type\":\"text\",\"text\":\"ok\"}]}",
    )
    inspect(
      seen.join(","),
      content="tools/call,initialize,notifications/initialized,tools/call",
    )
  }
}

///|
fn rpc_method(body : String) -> String {
  let parsed = @json.parse(body) catch { _ => return "" }
  match parsed {
    Object(obj) =>
      match obj.get("method") {
        Some(String(value)) => value
        _ => ""
      }
    _ => ""
  }
}

///|
fn header(headers : Map[String, String], key : String) -> String {
  match headers.get(key) {
    Some(value) => value
    None =>
      match headers.get(key.to_lower()) {
        Some(value) => value
        None => ""
      }
  }
}
