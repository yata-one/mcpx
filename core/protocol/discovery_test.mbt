///|
test "discovery: builds request and decodes result plus response metadata" {
  let context = mcp_request_context(
    protocol=McpProtocolVersion::V2026_07_28,
    client_name="mcpx",
    client_version="0.1.4",
  )
  inspect(
    mcp_discover_request(id=1, context)
    .stringify()
    .contains("\"method\":\"server/discover\""),
    content="true",
  )
  let decoded = decode_mcp_discover_response(
    {
      "jsonrpc": "2.0",
      "id": 1,
      "result": {
        "protocolVersions": ["2025-11-25", "2026-07-28"],
        "capabilities": { "tools": Json::empty_object() },
        "instructions": "Use tools",
      },
      "_meta": {
        "io.modelcontextprotocol/serverInfo": {
          "name": "fixture",
          "version": "1",
        },
      },
    },
    expected_id=1,
  ).unwrap()
  inspect(decoded.protocol_versions.length(), content="2")
  @debug.debug_inspect(decoded.instructions, content="Some(\"Use tools\")")
  inspect(
    decoded.response_meta.server_info.unwrap().stringify(),
    content="{\"name\":\"fixture\",\"version\":\"1\"}",
  )
}

///|
test "discovery: rejects mismatched id and missing protocol versions" {
  inspect(
    decode_mcp_discover_response(
      {
        "jsonrpc": "2.0",
        "id": 2,
        "result": { "protocolVersions": ["2026-07-28"] },
      },
      expected_id=1,
    )
    is Err(_),
    content="true",
  )
  inspect(
    decode_mcp_discover_response(
      { "jsonrpc": "2.0", "id": 1, "result": Json::empty_object() },
      expected_id=1,
    )
    is Err(_),
    content="true",
  )
}
