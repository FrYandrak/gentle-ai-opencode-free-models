/**
 * model-check
 * Triggers Gentle-AI's model check + assignment refresh on OpenCode startup.
 *
 * The shell wiring (~/.bashrc sourcing session-start-hook.sh) observes shell
 * starts, not OpenCode startups, so it cannot honor check_frequency=session
 * (refresh on every OpenCode startup). OpenCode loads plugins at startup, so
 * this plugin provides that trigger: it runs session-start-hook.sh with the
 * `opencode` argument, and the hook's own frequency gate decides whether the
 * invocation actually fetches (session runs always; daily/weekly/monthly share
 * the stamp with the shell trigger).
 *
 * Diagnostics go to stderr (console.error): stdout is reserved for CLI
 * parsing (e.g. `opencode models --verbose` output gentle-ai parses).
 */

import type { Plugin } from "@opencode-ai/plugin"
import { execFile } from "child_process"
import { access } from "fs/promises"
import { join } from "path"
import { promisify } from "util"

const execFileAsync = promisify(execFile)

// Path override mirrors engram.ts so the hook can be pointed at a non-default
// checkout without editing the plugin.
// The repository path below is a placeholder: the `sed` install step in
// README.md ("Install") substitutes your clone path into it. Left
// un-substituted, the skip-guard below stays inert and no check ever runs.
const MODEL_CHECK_REPO = process.env.MODEL_CHECK_REPO ?? "@MODEL_CHECK_REPO@"

async function pathExists(path: string): Promise<boolean> {
  try {
    await access(path)
    return true
  } catch {
    return false
  }
}

export const ModelCheckPlugin: Plugin = async () => {
  const hookPath = join(MODEL_CHECK_REPO, "session-start-hook.sh")

  async function runModelCheck() {
    // Inert on machines without the repo: a missing checkout is a normal
    // situation, not an error. Log the skip to stderr and do nothing.
    if (!(await pathExists(MODEL_CHECK_REPO)) || !(await pathExists(hookPath))) {
      console.error("[model-check] skipping: hook not found:", hookPath)
      return
    }

    try {
      // The hook is idempotent (flock + frequency gate), so a slow or failed
      // refresh is absorbed there; a non-zero exit is logged and swallowed —
      // a failed refresh must never block OpenCode startup.
      await execFileAsync("bash", [hookPath, "opencode"], { timeout: 120_000 })
    } catch (err) {
      console.error("[model-check] hook failed:", err)
    }
  }

  // Don't await — keep OpenCode startup responsive. The spawn itself is what
  // matters; its result is reported (if at all) on stderr after startup.
  runModelCheck().catch((err) => {
    console.error("[model-check] unexpected error:", err)
  })

  return {}
}

export default ModelCheckPlugin
