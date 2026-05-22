///|
fn run_search(
  command : SearchCommand,
  home : String,
  config_home : String?,
) -> String {
  let paths = @app_paths.mcpx_app_paths(home, config_home~)
  let config = @storage.load_mcpx_config_or_empty(paths.servers_config) catch {
    _ => @config.empty_mcpx_config()
  }
  let servers : Array[(String, String?)] = []
  for name, server in config.servers {
    servers.push((name, server.description))
  }
  let (results, total) = @search.search_servers(command.pattern, servers)
  if total == 0 {
    return "No servers matched " + command.pattern.to_json().stringify()
  }
  let lines = []
  for result in results {
    let desc = if result.description.length() > 0 {
      result.description
    } else {
      "(no description)"
    }
    lines.push(result.name + ": " + desc)
  }
  lines.push("")
  let suffix = if total == 1 { "" } else { "es" }
  let summary = if total <= 5 {
    "\{total} match\{suffix}"
  } else {
    "\{total} matches (showing top 5)"
  }
  lines.push(summary)
  lines.join("\n")
}
