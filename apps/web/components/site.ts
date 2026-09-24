import app from "../../macos/package.json";

export const site = {
  author: {
    name: "Noppakorn Kaewsalabnil",
    url: "https://github.com/PunGrumpy",
  },
  download: "https://github.com/PunGrumpy/afterhours/releases/latest",
  repo: "https://github.com/PunGrumpy/afterhours",
  version: app.version,
};

export type AgentState = "working" | "waiting" | "idle";

export const agents = [
  { id: "claude", name: "Claude Code" },
  { id: "codex", name: "Codex" },
  { id: "opencode", name: "OpenCode" },
  { id: "antigravity", name: "Antigravity CLI" },
  { id: "gemini", name: "Gemini CLI" },
  { id: "copilot", name: "Copilot CLI" },
  { id: "cursor", name: "Cursor CLI" },
  { id: "aider", name: "Aider" },
  { id: "amp", name: "Amp" },
  { id: "droid", name: "Droid" },
  { id: "goose", name: "Goose" },
  { id: "kiro", name: "Kiro CLI" },
  { id: "kilo", name: "Kilo CLI" },
  { id: "openclaw", name: "OpenClaw" },
  { id: "hermes", name: "Hermes Agent" },
  { id: "cline", name: "Cline CLI" },
] as const;
