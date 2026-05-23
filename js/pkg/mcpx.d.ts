/**
 * @yata-one/mcpx — MCP client library
 *
 * Functional, stateful API over HTTP transport.
 * Session is plain data — pass it to list_tools / call_tool.
 */

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/**
 * Injected fetch function for HTTP transport.
 *
 * @param method - HTTP method (always "POST" for MCP)
 * @param url - Request URL
 * @param headersJson - Request headers as JSON string
 * @param body - Request body as string
 * @returns Response JSON: `{ statusCode, contentType?, headers, body }`
 */
export type JsFetch = (
  method: string,
  url: string,
  headersJson: string,
  body: string,
) => Promise<string>;

/** Tool metadata returned by `list_tools`. */
export interface ToolInfo {
  name: string;
  description?: string;
  inputSchema: Record<string, unknown>;
}

/** Response envelope. */
export interface McpxResponse<T = unknown> {
  status: "ok" | "error";
  error?: string;
  tools?: ToolInfo[];
  result?: T;
}

// ---------------------------------------------------------------------------
// Functions
// ---------------------------------------------------------------------------

/**
 * Connect to an MCP server.
 * Performs initialize → initialized handshake.
 *
 * @param fetch - JsFetch implementation
 * @param url - MCP server endpoint URL
 * @returns Session JSON string (pass to list_tools / call_tool)
 */
export function connect(
  fetch: JsFetch,
  url: string,
): Promise<string>;

/**
 * List available tools on a connected session.
 *
 * @param fetch - JsFetch implementation
 * @param session - Session JSON from `connect()`
 * @returns JSON string: `{ status: "ok", tools: ToolInfo[] }`
 */
export function list_tools(
  fetch: JsFetch,
  session: string,
): Promise<string>;

/**
 * Call a tool on a connected session.
 *
 * @param fetch - JsFetch implementation
 * @param session - Session JSON from `connect()`
 * @param toolName - Name of the tool to call
 * @param argumentsJson - Tool arguments as JSON string
 * @returns JSON string: `{ status: "ok", result: ... }`
 */
export function call_tool(
  fetch: JsFetch,
  session: string,
  toolName: string,
  argumentsJson: string,
): Promise<string>;

/**
 * Disconnect from a session.
 * No-op for HTTP transport.
 *
 * @param session - Session JSON from `connect()`
 * @returns JSON string: `{ status: "ok" }`
 */
export function disconnect(
  session: string,
): Promise<string>;
