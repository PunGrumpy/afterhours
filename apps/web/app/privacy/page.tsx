import type { Metadata } from "next";

import { LegalPage, LegalSection } from "@/components/legal";
import { site } from "@/components/site";

export const metadata: Metadata = {
  description:
    "What Afterhours keeps on your Mac, the only requests it sends, and what this website collects.",
  title: "Privacy Policy",
};

const checks = [
  {
    login: "Keychain login, one per ~/.claude* directory",
    provider: "Claude Code",
    to: "api.anthropic.com",
  },
  { login: "~/.codex/auth.json", provider: "Codex", to: "chatgpt.com" },
  { login: "OpenCode's auth.json", provider: "OpenCode Go", to: "opencode.ai" },
  {
    login: "~/.config/github-copilot/apps.json or the gh login",
    provider: "Copilot",
    to: "api.github.com, identified as Copilot Chat",
  },
  {
    login: "The Cursor app's state store or ~/.cursor/auth.json",
    provider: "Cursor",
    to: "api2.cursor.sh",
  },
  {
    login: "~/.grok/auth.json",
    provider: "Grok Build",
    to: "cli-chat-proxy.grok.com",
  },
  {
    login: "The management key you enter",
    provider: "CLIProxyAPI hubs you add",
    to: "The hub's URL",
  },
];

const Page = () => (
  <LegalPage title="Privacy Policy" updated="September 27, 2026">
    <p>
      Afterhours is a menu bar app that runs on your Mac. It has no accounts and
      no servers, and it has no telemetry, analytics, crash reporting, or ads.
      This policy covers the app, how you download it, and this website.
    </p>

    <LegalSection title="What stays on your Mac">
      <p>
        To tell when agents are working, Afterhours reads the names, command
        lines, and CPU time of the processes on your Mac. It uses them in memory
        and never saves or sends them. It never reads your code, your files, or
        your terminal output.
      </p>
      <p>It keeps these on your Mac:</p>
      <ul>
        <li>
          A small file for each hooked agent session in{" "}
          <code>~/Library/Application Support/Afterhours/sessions</code>, with
          the session ID, agent name, state, process ID, working directory, and
          the time of the last event. Afterhours deletes it when the agent
          exits.
        </li>
        <li>
          Your settings, in the <code>app.afterhours.local</code> preferences.
        </li>
        <li>
          The management key of any CLIProxyAPI hub you add, in your Keychain.
        </li>
        <li>
          When you install Claude Code hooks, a copy of your previous{" "}
          <code>settings.json</code> as{" "}
          <code>settings.json.afterhours-backup</code>.
        </li>
        <li>
          When you install lid-closed mode, a sudoers rule in{" "}
          <code>/etc/sudoers.d/afterhours</code> that allows only{" "}
          <code>pmset -a disablesleep 0</code> and{" "}
          <code>pmset -a disablesleep 1</code>.
        </li>
      </ul>
    </LegalSection>

    <LegalSection title="What leaves your Mac">
      <p>
        Only the subscription checks behind the Limits section of the menu.
        They&apos;re on by default. Turn them off in{" "}
        <strong>Settings… &gt; Limits</strong>, and Afterhours makes no network
        requests at all.
      </p>
      <p>
        Each check sends a login your tool already keeps on your Mac straight to
        that tool&apos;s own service, and reads back how much of each rate-limit
        window is left. It runs when you open the menu and every 5 minutes while
        agents work. Afterhours doesn&apos;t store, refresh, or forward these
        logins. Nothing passes through a server of ours, because there
        isn&apos;t one.
      </p>
      <div className="border-ink/[0.08] -mx-1 overflow-hidden rounded-[12px] border">
        <table className="w-full text-left text-[14px]">
          <thead className="bg-surface text-ink">
            <tr>
              <th className="px-4 py-2.5 font-medium">Provider</th>
              <th className="px-4 py-2.5 font-medium">Login it reads</th>
              <th className="px-4 py-2.5 font-medium max-sm:hidden">Sent to</th>
            </tr>
          </thead>
          <tbody>
            {checks.map((check) => (
              <tr key={check.provider} className="border-ink/[0.06] border-t">
                <td className="text-ink px-4 py-2.5 align-top">
                  {check.provider}
                  <span className="text-ink/50 block text-[13px] sm:hidden">
                    {check.to}
                  </span>
                </td>
                <td className="px-4 py-2.5 align-top">{check.login}</td>
                <td className="px-4 py-2.5 align-top max-sm:hidden">
                  {check.to}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <p>Each provider handles these requests under its own privacy policy.</p>
    </LegalSection>

    <LegalSection title="Downloads">
      <p>
        You download Afterhours from GitHub Releases, or through Homebrew, which
        fetches the same file from GitHub. The{" "}
        <a href="https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement">
          GitHub Privacy Statement
        </a>{" "}
        covers those downloads. The app itself doesn&apos;t check for updates.
      </p>
    </LegalSection>

    <LegalSection title="This website">
      <p>
        This site sets no cookies and runs no analytics or tracking scripts. Its
        fonts and images load from the site itself. It&apos;s hosted on Vercel,
        which keeps standard server logs, such as IP addresses and browser
        details, under the{" "}
        <a href="https://vercel.com/legal/privacy-policy">
          Vercel Privacy Policy
        </a>
        .
      </p>
    </LegalSection>

    <LegalSection title="Removing your data">
      <p>
        Everything Afterhours keeps is on your Mac. The{" "}
        <a href={`${site.repo}#uninstall`}>uninstall steps</a> remove all of it.
      </p>
    </LegalSection>

    <LegalSection title="Changes and questions">
      <p>
        If this policy changes, this page shows a new date, and the change is in
        the site&apos;s history on <a href={site.repo}>GitHub</a>. Ask questions
        in <a href={`${site.repo}/issues`}>GitHub issues</a>.
      </p>
    </LegalSection>
  </LegalPage>
);

export default Page;
