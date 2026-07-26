///|
pub struct McpResponseMeta {
  server_info : Json?
  raw : Json
} derive(Debug)

///|
pub struct McpDiscoverInfo {
  protocol_versions : Array[McpProtocolVersion]
  capabilities : Json
  instructions : String?
  response_meta : McpResponseMeta
} derive(Debug)

///|
pub fn mcp_discover_request(id~ : Int, context : McpRequestContext) -> Json {
  mcp_request(
    id,
    "server/discover",
    Some(with_mcp_request_meta(Map([]), context)),
  )
}

///|
pub fn decode_mcp_discover_response(
  response : Json,
  expected_id~ : Int,
) -> Result[McpDiscoverInfo, McpProtocolError] {
  let root = match response {
    Object(value) => value
    _ => return Err(InvalidResponse("discover response must be object"))
  }
  let result = decode_mcp_result(response, expected_id~) catch {
    error => return Err(error)
  }
  let result = match result {
    Object(value) => value
    _ => return Err(InvalidResponse("discover result must be object"))
  }
  let versions_json = match result.get("protocolVersions") {
    Some(Array(value)) => value
    _ => return Err(InvalidResponse("discover result missing protocolVersions"))
  }
  let versions = []
  for value in versions_json {
    match value {
      String(version) => versions.push(parse_mcp_protocol_version(version))
      _ =>
        return Err(InvalidResponse("discover protocol version must be string"))
    }
  }
  if versions.is_empty() {
    return Err(InvalidResponse("discover protocolVersions must not be empty"))
  }
  let capabilities = result.get("capabilities").unwrap_or(Json::empty_object())
  let instructions = match result.get("instructions") {
    Some(String(value)) => Some(value)
    Some(_) =>
      return Err(InvalidResponse("discover instructions must be string"))
    None => None
  }
  let raw_meta = root.get("_meta").unwrap_or(Json::empty_object())
  let server_info = match raw_meta {
    Object(meta) => meta.get("io.modelcontextprotocol/serverInfo")
    _ => None
  }
  Ok({
    protocol_versions: versions,
    capabilities,
    instructions,
    response_meta: { server_info, raw: raw_meta },
  })
}
