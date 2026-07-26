///|
fn unsupported_stdio_protocol_mode(server : @config.McpServerConfig) -> String? {
  match server.protocol_mode {
    Some(@config.McpConnectionMode::Auto) =>
      Some(
        "stdio protocol.mode auto is not supported yet; omit protocol.mode or use stateful",
      )
    Some(@config.McpConnectionMode::Stateless) =>
      Some(
        "stdio protocol.mode stateless is not supported yet; omit protocol.mode or use stateful",
      )
    Some(@config.McpConnectionMode::Stateful) | None => None
  }
}
