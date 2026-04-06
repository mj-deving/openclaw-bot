/**
 * Defense Shield Plugin — Type Definitions
 *
 * Plugin-specific types for the OpenClaw hook API.
 * Defense layer types are imported from ../types.ts.
 */

/**
 * OpenClaw Plugin API type (subset we use).
 * Full type from "openclaw/plugin-sdk" — we declare what we need
 * to avoid import dependency on the OpenClaw package.
 */
export interface PluginApi {
  id: string;
  name: string;
  pluginConfig?: Record<string, unknown>;
  logger: PluginLogger;
  registerHook: (
    events: string | string[],
    handler: (event: HookEvent) => HookReturnType,
    opts?: { name?: string; description?: string }
  ) => void;
}

export interface PluginLogger {
  info: (msg: string) => void;
  warn: (msg: string) => void;
  error: (msg: string) => void;
}

/** Base event shape shared across all hooks */
export interface HookEvent {
  type: string;
  action: string;
  sessionKey: string;
  context: Record<string, unknown>;
  timestamp: Date;
  messages: string[];
  // Tool call fields (before_tool_call)
  toolName?: string;
  params?: Record<string, unknown>;
  // LLM fields (llm_input, llm_output)
  prompt?: string;
  systemPrompt?: string;
  content?: string;
  assistantTexts?: string[];
  usage?: { input?: number; output?: number; total?: number };
  provider?: string;
  model?: string;
  runId?: string;
  from?: string;
  channelId?: string;
}

/**
 * Hook return type — void hooks ignore return, modifying hooks inspect it.
 * - message_sending: return { content?: string, cancel?: boolean }
 * - before_tool_call: return { block?: boolean, blockReason?: string, params?: unknown }
 * - void hooks: return void or Promise<void>
 */
export type HookReturnType =
  | Promise<void>
  | void
  | Promise<{ content?: string; cancel?: boolean }>
  | { content?: string; cancel?: boolean }
  | Promise<{ block?: boolean; blockReason?: string; params?: unknown }>
  | { block?: boolean; blockReason?: string; params?: unknown };
