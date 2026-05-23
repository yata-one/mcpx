///|
async fn run_auth(
  command : AuthCommand,
  home : String,
  config_home : String?,
) -> String {
  match (command.code, command.state) {
    (Some(code), Some(state)) =>
      return complete_oauth_auth(command.server, code, state, home, config_home)
    (Some(_), None) => return error_result("OAuth state is required")
    (None, Some(_)) => return error_result("OAuth code is required")
    (None, None) => ()
  }
  let paths = @app_paths.mcpx_app_paths(home, config_home~)
  let config = @storage.load_mcpx_config_or_empty(paths.servers_config)
  match config.servers.get(command.server) {
    None => error_result("server not found: " + command.server)
    Some(server) => {
      let env = match load_mcpx_env(paths.env_file) {
        Ok(value) => value
        Err(message) => return error_result(message)
      }
      let resolved_server = match @config.resolve_server_env(server, env) {
        Ok(value) => value
        Err(error) => return error_result(error.to_string())
      }
      let auth = match resolved_server.auth {
        Some(value) => value
        None =>
          return error_result("server has no OAuth config: " + command.server)
      }
      let metadata = match
        resolve_oauth_metadata(
          server_name=command.server,
          server_url=resolved_server.url,
          metadata_url=auth.metadata_url,
        ) {
        Ok(value) => value
        Err(message) => return error_result(message)
      }
      let redirect_uri = "http://127.0.0.1:8765/callback"
      let (client_id, client_secret) = match auth.client_id {
        Some(value) => (value, auth.client_secret)
        None =>
          match register_oauth_client(metadata, redirect_uri) {
            Ok(value) => (value.client_id, value.client_secret)
            Err(message) => return error_result(message)
          }
      }
      let state = @oauth.random_urlsafe_token(16) catch {
        _ => return error_result("failed to generate OAuth state")
      }
      let verifier = @oauth.random_urlsafe_token(32) catch {
        _ => return error_result("failed to generate OAuth verifier")
      }
      let challenge = @oauth.pkce_s256_challenge(verifier)
      let scopes = @auth.select_oauth_scopes(
        metadata,
        requested_scopes=auth.scopes,
      )
      let authorization_url = @auth.oauth_authorization_url(
        metadata,
        client_id~,
        redirect_uri~,
        state~,
        code_challenge=challenge,
        scopes~,
      )
      let save_result = save_pending_oauth_flow(
        paths.credentials_file,
        server_name=command.server,
        server_url=resolved_server.url,
        client_id~,
        client_secret~,
        token_endpoint=metadata.token_endpoint,
        redirect_uri~,
        code_verifier=verifier,
        state~,
      )
      match save_result {
        Ok(_) => ()
        Err(message) => return error_result(message)
      }
      if command.no_browser {
        auth_start_result(
          command.server,
          authorization_url,
          redirect_uri,
          state,
        )
      } else {
        let callback = @oauth.wait_for_oauth_callback(
          port=8765,
          path="/callback",
          expected_state=state,
          timeout_ms=300000,
          trigger=_redirect_uri => {
            @oauth.open_authorization_url(authorization_url)
          },
        ) catch {
          _ => return error_result("OAuth callback failed or timed out")
        }
        complete_oauth_auth(
          command.server,
          callback.code,
          callback.state,
          home,
          config_home,
        )
      }
    }
  }
}

///|
async fn complete_oauth_auth(
  server_name : String,
  code : String,
  state : String,
  home : String,
  config_home : String?,
) -> String {
  let paths = @app_paths.mcpx_app_paths(home, config_home~)
  let credentials = @storage.load_credentials_file_or_empty(
    paths.credentials_file,
  ) catch {
    _ => return error_result("failed to load credentials")
  }
  let flow = match
    @auth.find_pending_oauth_flow(credentials, server_name~, state~) {
    Some(value) => value
    None => return error_result("pending OAuth flow not found: " + server_name)
  }
  let issued_at = current_time_seconds()
  let body = @auth.authorization_code_token_request_body(
    client_id=flow.client_info.client_id,
    client_secret=flow.client_info.client_secret,
    code~,
    redirect_uri=flow.redirect_uri,
    code_verifier=flow.code_verifier,
  )
  let (response, data) = @http.post(flow.token_endpoint, body, headers={
    "content-type": "application/x-www-form-urlencoded",
    "accept": "application/json",
  }) catch {
    _ => return error_result("failed to exchange OAuth code")
  }
  if response.code != 200 {
    return error_result("failed to exchange OAuth code")
  }
  let token_json = data.json() catch {
    _ => return error_result("invalid OAuth token response")
  }
  let tokens = match @auth.decode_oauth_token_response(token_json, issued_at~) {
    Ok(value) => value
    Err(_) => return error_result("invalid OAuth token response")
  }
  let entry = @auth.credentials_entry(
    server_name~,
    server_url=flow.server_url,
    client_id=Some(flow.client_info.client_id),
    access_token=tokens.access_token,
    refresh_token=tokens.refresh_token,
    expires_at=tokens.expires_at,
    updated_at=issued_at.to_string(),
  )
  let without_pending = @auth.remove_pending_oauth_flow(
    credentials,
    server_name~,
    state~,
  )
  let next = @auth.put_credentials_entry(
    without_pending,
    credentials_cache_key(server_name, flow.client_info.client_id),
    entry,
  )
  @storage.save_credentials_file(paths.credentials_file, next) catch {
    _ => return error_result("failed to save credentials")
  }
  auth_complete_result(server_name)
}

///|
fn save_pending_oauth_flow(
  credentials_path : String,
  server_name~ : String,
  server_url~ : String?,
  client_id~ : String,
  client_secret~ : String?,
  token_endpoint~ : String,
  redirect_uri~ : String,
  code_verifier~ : String,
  state~ : String,
) -> Result[Unit, String] {
  let credentials = @storage.load_credentials_file_or_empty(credentials_path) catch {
    _ => return Err("failed to load credentials")
  }
  let next = @auth.put_pending_oauth_flow(
    credentials,
    @auth.pending_oauth_flow(
      server_name~,
      server_url~,
      client_id~,
      client_secret~,
      token_endpoint~,
      redirect_uri~,
      code_verifier~,
      state~,
      created_at=current_time_seconds().to_string(),
    ),
  )
  @storage.save_credentials_file(credentials_path, next) catch {
    _ => return Err("failed to save pending OAuth flow")
  }
  Ok(())
}

///|
async fn register_oauth_client(
  metadata : @auth.OAuthMetadata,
  redirect_uri : String,
) -> Result[@auth.OAuthClientRegistration, String] {
  let registration_endpoint = match metadata.registration_endpoint {
    Some(value) => value
    None => return Err("OAuth dynamic client registration is unavailable")
  }
  let body = @auth.dynamic_client_registration_request(
    client_name="mcpx",
    redirect_uri~,
  ).stringify()
  let (response, data) = @http.post(registration_endpoint, body, headers={
    "content-type": "application/json",
    "accept": "application/json",
  }) catch {
    _ => return Err("failed to register OAuth client")
  }
  if response.code != 200 && response.code != 201 {
    return Err("failed to register OAuth client")
  }
  let json = data.json() catch {
    _ => return Err("invalid OAuth client registration response")
  }
  match @auth.decode_client_registration_response(json) {
    Ok(value) => Ok(value)
    Err(_) => Err("invalid OAuth client registration response")
  }
}

///|
fn auth_hint_result(hint : @auth.AuthHint) -> String {
  let lines = ["Error: " + hint.summary]
  if !hint.suggested_commands.is_empty() {
    lines.push("")
    lines.push("Try:")
    for command in hint.suggested_commands {
      lines.push("  " + command)
    }
  }
  match hint.config_hint {
    Some(value) => {
      lines.push("")
      lines.push(value)
    }
    None => ()
  }
  lines.join("\n")
}

///|
fn auth_start_result(
  server_name : String,
  authorization_url : String,
  callback_url : String,
  state : String,
) -> String {
  let obj = Map([])
  obj["status"] = Json::string("ok")
  obj["action"] = Json::string("auth")
  obj["server"] = Json::string(server_name)
  obj["authorizationUrl"] = Json::string(authorization_url)
  obj["callbackUrl"] = Json::string(callback_url)
  obj["state"] = Json::string(state)
  obj["noBrowser"] = Json::boolean(true)
  Json::object(obj).stringify()
}

///|
fn auth_complete_result(server_name : String) -> String {
  "Auth complete: " + server_name
}

///|
async fn call_headers_with_cached_auth(
  server_name~ : String,
  server_url~ : String,
  server~ : @config.McpServerConfig,
  credentials_path~ : String,
) -> Result[Map[String, String], String] {
  let headers = server.headers.copy()
  if has_authorization_header(headers) {
    Ok(headers)
  } else {
    match server.auth {
      None => Ok(headers)
      Some(auth) => {
        let credentials = @storage.load_credentials_file_or_empty(
          credentials_path,
        ) catch {
          _ => return Err("failed to load credentials")
        }
        let entry = @auth.find_credentials_entry(
          credentials,
          server_name~,
          server_url=Some(server_url),
        )
        match
          @auth.decide_auth_cache(entry, now_seconds=current_time_seconds()) {
          @auth.CachedAuthDecision::UseBearerHeader(value) => {
            headers["Authorization"] = value
            Ok(headers)
          }
          @auth.CachedAuthDecision::RefreshWithToken(refresh_token) =>
            match entry {
              Some(entry) =>
                match
                  refresh_oauth_credentials(
                    server_name~,
                    server_url~,
                    auth~,
                    entry~,
                    refresh_token~,
                    credentials~,
                    credentials_path~,
                  ) {
                  Ok(value) => {
                    headers["Authorization"] = value
                    Ok(headers)
                  }
                  Err(message) => Err(message)
                }
              None =>
                Err("authentication required: run mcpx auth " + server_name)
            }
          @auth.CachedAuthDecision::ReauthRequired =>
            Err("authentication required: run mcpx auth " + server_name)
        }
      }
    }
  }
}

///|
async fn refresh_oauth_credentials(
  server_name~ : String,
  server_url~ : String,
  auth~ : @config.ServerAuthConfig,
  entry~ : @auth.CredentialsEntry,
  refresh_token~ : String,
  credentials~ : @auth.CredentialsFile,
  credentials_path~ : String,
) -> Result[String, String] {
  let client_id = match oauth_client_id(auth, entry) {
    Some(value) => value
    None => return Err("authentication required: run mcpx auth " + server_name)
  }
  let metadata = match
    resolve_oauth_metadata(
      server_name~,
      server_url=Some(server_url),
      metadata_url=auth.metadata_url,
    ) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let issued_at = current_time_seconds()
  let body = @auth.refresh_token_request_body(
    client_id~,
    client_secret=auth.client_secret,
    refresh_token~,
  )
  let (response, data) = @http.post(metadata.token_endpoint, body, headers={
    "content-type": "application/x-www-form-urlencoded",
    "accept": "application/json",
  }) catch {
    _ => return Err("failed to refresh OAuth token")
  }
  if response.code != 200 {
    return Err("failed to refresh OAuth token")
  }
  let token_json = data.json() catch {
    _ => return Err("invalid OAuth token response")
  }
  let tokens = match @auth.decode_oauth_token_response(token_json, issued_at~) {
    Ok(value) => value
    Err(_) => return Err("invalid OAuth token response")
  }
  let refresh_token_next = match tokens.refresh_token {
    Some(value) => Some(value)
    None => Some(refresh_token)
  }
  let updated_entry = @auth.credentials_entry(
    server_name~,
    server_url=Some(server_url),
    client_id=Some(client_id),
    access_token=tokens.access_token,
    refresh_token=refresh_token_next,
    expires_at=tokens.expires_at,
    updated_at=issued_at.to_string(),
  )
  let updated_credentials = @auth.put_credentials_entry(
    credentials,
    credentials_cache_key(server_name, client_id),
    updated_entry,
  )
  @storage.save_credentials_file(credentials_path, updated_credentials) catch {
    _ => return Err("failed to save refreshed credentials")
  }
  Ok("Bearer " + tokens.access_token)
}

///|
async fn fetch_oauth_metadata(
  metadata_url : String,
) -> Result[@auth.OAuthMetadata, String] {
  let (response, data) = @http.get(metadata_url, headers={
    "accept": "application/json",
  }) catch {
    _ => return Err("failed to fetch OAuth metadata")
  }
  if response.code != 200 {
    return Err("failed to fetch OAuth metadata")
  }
  let metadata_json = data.json() catch {
    _ => return Err("invalid OAuth metadata")
  }
  match @auth.decode_oauth_metadata(metadata_json) {
    Ok(value) => Ok(value)
    Err(_) => Err("invalid OAuth metadata")
  }
}

///|
fn oauth_client_id(
  auth : @config.ServerAuthConfig,
  entry : @auth.CredentialsEntry,
) -> String? {
  match auth.client_id {
    Some(value) => Some(value)
    None =>
      match entry.client_info {
        Some(info) => Some(info.client_id)
        None => None
      }
  }
}

///|
fn credentials_cache_key(server_name : String, client_id : String) -> String {
  server_name + "|" + client_id
}

///|
fn has_authorization_header(headers : Map[String, String]) -> Bool {
  headers.contains("Authorization") || headers.contains("authorization")
}

///|
async fn resolve_oauth_metadata(
  server_name~ : String,
  server_url~ : String?,
  metadata_url~ : String?,
) -> Result[@auth.OAuthMetadata, String] {
  match metadata_url {
    Some(url) => fetch_oauth_metadata(url)
    None => {
      let url = match server_url {
        Some(value) => value
        None => return Err("OAuth metadata URL is required: " + server_name)
      }
      match discover_oauth_metadata(url) {
        Ok(value) => Ok(value)
        Err(_) => Err("OAuth metadata URL is required: " + server_name)
      }
    }
  }
}

///|
async fn discover_oauth_metadata(
  server_url : String,
) -> Result[@auth.OAuthMetadata, String] {
  let (response, _data) = @http.get(server_url) catch {
    _ => return Err("failed to connect to server")
  }
  let www_auth = match http_header(response.headers, "www-authenticate") {
    Some(value) => value
    None => return Err("no www-authenticate header")
  }
  let resource_url = match parse_www_authenticate_resource_metadata(www_auth) {
    Some(value) => value
    None => return Err("no resource_metadata in www-authenticate")
  }
  let (res, res_data) = @http.get(resource_url, headers={
    "accept": "application/json",
  }) catch {
    _ => return Err("failed to fetch resource metadata")
  }
  if res.code != 200 {
    return Err("failed to fetch resource metadata")
  }
  let res_json = res_data.json() catch {
    _ => return Err("invalid resource metadata")
  }
  let auth_servers = match decode_authorization_servers(res_json) {
    Some(value) => value
    None => return Err("no authorization_servers in resource metadata")
  }
  let issuer = match auth_servers.get(0) {
    Some(value) => value
    None => return Err("empty authorization_servers")
  }
  fetch_oauth_metadata(oauth_authorization_server_metadata_url(issuer))
}

///|
fn http_header(headers : Map[String, String], name : String) -> String? {
  match headers.get(name) {
    Some(value) => Some(value)
    None =>
      for key, value in headers {
        if key.equal_ignore_ascii_case(name) {
          break Some(value)
        }
      } nobreak {
        None
      }
  }
}

///|
fn parse_www_authenticate_resource_metadata(header : String) -> String? {
  let marker = "resource_metadata=\""
  let start = match header.to_lower().find(marker) {
    Some(pos) => pos + marker.length()
    None => return None
  }
  let rest = header.to_string_view().view(start_offset=start)
  let end = match rest.find("\"") {
    Some(pos) => pos
    None => return None
  }
  match rest.get_view(start=0, end~) {
    Some(value) => Some(value.to_owned())
    None => None
  }
}

///|
fn decode_authorization_servers(json : Json) -> Array[String]? {
  match json {
    Object(obj) =>
      match obj.get("authorization_servers") {
        Some(Array(servers)) => {
          let urls = []
          for server in servers {
            match server {
              String(url) => urls.push(url)
              _ => ()
            }
          }
          Some(urls)
        }
        _ => None
      }
    _ => None
  }
}

///|
fn oauth_authorization_server_metadata_url(issuer : String) -> String {
  let normalized = match issuer.strip_suffix("/") {
    Some(value) => value.to_owned()
    None => issuer
  }
  let well_known = "/.well-known/oauth-authorization-server"
  match normalized.split_once("://") {
    Some((scheme, rest)) =>
      match rest.find("/") {
        Some(path_start) => {
          let host = rest.view(end_offset=path_start).to_owned()
          let path = rest.view(start_offset=path_start).to_owned()
          scheme.to_owned() + "://" + host + well_known + path
        }
        None => normalized + well_known
      }
    None => normalized + well_known
  }
}
