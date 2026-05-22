///|
test "bench search: 100 servers single word" (it : @bench.T) {
  let servers : Array[(String, String?)] = Array::makei(100, i => {
    let name = "server-\{i}"
    let desc = Some(
      "Tool for processing data batch \{i} with advanced analytics",
    )
    (name, desc)
  })
  servers.push(("github", Some("GitHub Issues, PRs, and code search")))
  it.bench(() => it.keep(@search.search_servers("github", servers).0.length()))
}

///|
test "bench search: 100 servers multi-word" (it : @bench.T) {
  let servers : Array[(String, String?)] = Array::makei(100, i => {
    let name = "server-\{i}"
    let desc = Some(
      "Tool for processing data batch \{i} with advanced analytics",
    )
    (name, desc)
  })
  servers.push(
    ("code-review-bot", Some("Automated code review for pull requests")),
  )
  servers.push(("gitlab", Some("GitLab code review and project management")))
  it.bench(() => {
    it.keep(@search.search_servers("code review", servers).0.length())
  })
}

///|
test "bench search: 10 servers" (it : @bench.T) {
  let servers : Array[(String, String?)] = [
    ("github", Some("GitHub Issues, PRs, and code search")),
    ("gitlab", Some("GitLab code review and project management")),
    ("gitea", Some("Gitea lightweight Git hosting")),
    ("playwright", Some("Browser automation and testing")),
    ("code-review-bot", Some("Automated code review for pull requests")),
    ("jira", Some("Jira issue tracking and project management")),
    ("notion", Some("Notion workspace and documentation")),
    ("sentry", Some("Error tracking and performance monitoring")),
    ("filesystem", Some("Read and write files on the local filesystem")),
    ("postgres", Some("Query and manage PostgreSQL databases")),
  ]
  it.bench(() => it.keep(@search.search_servers("git", servers).0.length()))
}

///|
test "bench search: 1000 servers no match" (it : @bench.T) {
  let servers : Array[(String, String?)] = Array::makei(1000, i => {
    let name = "srv-\{i}"
    let desc = Some("Processing engine \{i} for data workflows")
    (name, desc)
  })
  it.bench(() => {
    it.keep(@search.search_servers("xyznonexistent", servers).0.length())
  })
}

///|
test "bench search: single score call" (it : @bench.T) {
  it.bench(() => {
    ignore(
      @search.server_search_score(
        "git",
        "github-code-search",
        Some("Search code across GitHub repositories"),
      ),
    )
  })
}
