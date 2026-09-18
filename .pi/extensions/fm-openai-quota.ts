// Optional subscription status only; never replaces Pi's footer or reads credentials.
import { execFile } from "node:child_process";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const KEY = "firstmate-openai-quota";
const REFRESH_MS = 60_000;
const MAX_AGE_MS = 300_000;
const TIMEOUT_MS = 5_000;

type Snapshot = { text: string; expires: number };

// quota-axi owns quota semantics. Display returned windows, not derived runway/cost.
export function parseQuota(stdout: string, now = Date.now()): Snapshot {
  const data = JSON.parse(stdout);
  if (data?.schemaVersion !== 3 || !Array.isArray(data.providers)) throw new Error("unknown");
  const providers = data.providers.filter((p: any) => p?.provider === "codex");
  if (providers.length !== 1) throw new Error("unknown");
  const provider = providers[0];
  if (provider.state?.stale === true || provider.state?.status === "stale") throw new Error("stale");
  if (provider.state?.status !== "fresh" || provider.state.stale !== false) throw new Error("unknown");
  const refreshed = Date.parse(provider.state.refreshedAt);
  if (!Number.isFinite(refreshed) || refreshed > now + TIMEOUT_MS) throw new Error("unknown");
  if (now - refreshed >= MAX_AGE_MS) throw new Error("stale");
  if (!Array.isArray(provider.windows) || !provider.windows.length || provider.windows.length > 20) throw new Error("unknown");
  let expires = refreshed + MAX_AGE_MS;
  const windows = provider.windows.map((window: any) => {
    const percent = window?.percentRemaining;
    // Labels are untrusted terminal text. Never render control sequences or errors.
    if (typeof window?.label !== "string" || !/^[a-zA-Z0-9][a-zA-Z0-9 ._()/+-]{0,47}$/.test(window.label) ||
        typeof percent !== "number" || !Number.isFinite(percent) || percent < 0 || percent > 100) throw new Error("unknown");
    if (window.resetsAt != null) {
      const reset = Date.parse(window.resetsAt);
      if (!Number.isFinite(reset)) throw new Error("unknown");
      if (reset <= now) throw new Error("stale");
      expires = Math.min(expires, reset);
    }
    return `${window.label} ${percent}% left`;
  });
  return { text: `OpenAI ${windows.join(" · ")}`, expires };
}

export default function (pi: ExtensionAPI) {
  pi.registerFlag("openai-quota", {
    description: "Show OpenAI subscription windows from quota-axi in the footer",
    type: "boolean",
    default: false,
  });
  let stop: (() => void) | undefined;
  pi.on("session_start", (_event, ctx) => {
    stop?.();
    stop = undefined;
    if (!pi.getFlag("openai-quota") || ctx.mode !== "tui") return;
    stop = startQuotaStatus(ctx);
  });
  pi.on("session_shutdown", () => {
    stop?.();
    stop = undefined;
  });
}

export function startQuotaStatus(ctx: Pick<ExtensionContext, "ui">): () => void {
  let stopped = false;
  let refreshTimer: ReturnType<typeof setTimeout> | undefined;
  let expiryTimer: ReturnType<typeof setTimeout> | undefined;
  let pending: AbortController | undefined;
  const publish = (text: string | undefined) => ctx.ui.setStatus(KEY, text);
  const refresh = () => {
    if (stopped || pending) return;
    pending = new AbortController();
    // execFile gives a hard deadline and bounded output without a shell or new service.
    execFile("quota-axi", ["--provider", "codex", "--json"], {
      encoding: "utf8", timeout: TIMEOUT_MS, killSignal: "SIGKILL",
      maxBuffer: 256 * 1024, signal: pending.signal,
    }, (error, stdout) => {
      pending = undefined;
      if (stopped) return;
      clearTimeout(expiryTimer);
      try {
        if (error) throw new Error("unavailable");
        const snapshot = parseQuota(stdout);
        publish(snapshot.text);
        expiryTimer = setTimeout(() => publish("OpenAI quota stale"), Math.max(0, snapshot.expires - Date.now()));
        expiryTimer.unref();
      } catch (error) {
        publish(error instanceof Error && error.message === "stale" ? "OpenAI quota stale" : "OpenAI quota unavailable");
      }
      // One completion-driven refresh owner; no overlapping processes or turn hooks.
      refreshTimer = setTimeout(refresh, REFRESH_MS);
      refreshTimer.unref();
    });
  };
  publish("OpenAI quota unknown");
  refresh();
  return () => {
    if (stopped) return;
    stopped = true;
    clearTimeout(refreshTimer);
    clearTimeout(expiryTimer);
    pending?.abort();
    publish(undefined);
  };
}
