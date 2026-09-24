import { cn } from "cn";
import type { ReactNode } from "react";

import { AgentLogo } from "./agent-logo";
import { Mug } from "./mug";

const Card = ({
  title,
  children,
  visual,
}: {
  title: string;
  children: ReactNode;
  visual: ReactNode;
}) => (
  <article className="bg-surface flex flex-col rounded-[20px] p-2">
    <div className="grid h-40 place-items-center rounded-[12px] bg-white shadow-[0_0_0_1px_rgb(8_21_46/0.05)]">
      {visual}
    </div>
    <div className="px-3 pt-4 pb-3">
      <h3 className="text-[15px] font-semibold tracking-[-0.01em]">{title}</h3>
      <p className="text-ink/60 mt-1 text-[14px] leading-snug">{children}</p>
    </div>
  </article>
);

const MenuRow = ({
  id,
  name,
  status,
  dot,
}: {
  id: string;
  name: string;
  status: string;
  dot?: string;
}) => (
  <div className="bg-menu flex w-full max-w-[240px] items-center gap-3 rounded-[10px] px-3 py-2.5 text-white">
    <AgentLogo
      id={id}
      className="size-[22px] rounded-[6px] bg-white/10 text-white outline-[0.5px] -outline-offset-[0.5px] outline-white/10"
    />
    <span className="flex-1 text-[13px] font-medium whitespace-nowrap">
      {name}
    </span>
    <span className="text-[12px] text-white/55 tabular-nums">{status}</span>
    {dot && <span className={cn("size-[7px] rounded-full", dot)} />}
  </div>
);

export const Features = () => (
  <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
    <Card
      title="Works with the lid closed"
      visual={
        <div className="flex flex-col items-center">
          <Mug mood="awake" steaming className="text-ink size-12" />
          <div className="mt-2 h-1.5 w-28 rounded-full bg-[linear-gradient(180deg,#56565b,#232326)]" />
          <div className="h-2 w-32 rounded-b-md bg-[linear-gradient(180deg,#3b3b3f,#161618)]" />
        </div>
      }
    >
      A one-time sudoers rule lets it hold sleep off after you shut the lid.
    </Card>

    <Card
      title="Waits for your reply"
      visual={
        <MenuRow
          id="codex"
          name="Codex"
          status="Needs you"
          dot="bg-mac-orange"
        />
      }
    >
      Plugged in, it waits until every session closes. On battery, up to an
      hour.
    </Card>

    <Card
      title="Lets go before your battery does"
      visual={
        <div className="w-full max-w-[200px]">
          <div className="bg-ink/10 relative h-2 rounded-full">
            <div className="bg-mac-orange h-full w-[23%] rounded-full" />
            <div className="bg-mac-red absolute -top-1.5 left-[15%] h-5 w-0.5 rounded-full" />
          </div>
          <div className="mt-2.5 flex justify-between text-[13px] tabular-nums">
            <span className="font-medium">23% left</span>
            <span className="text-ink/50">Stops below 15%</span>
          </div>
        </div>
      }
    >
      Sleeps anyway below your cutoff, in Low Power Mode, or when it runs hot.
    </Card>

    <Card
      title="Steam shows the state"
      visual={
        <div className="flex items-end gap-5">
          {(
            [
              ["awake", "Awake"],
              ["drowsy", "Paused"],
              ["asleep", "Sleeping"],
            ] as const
          ).map(([mood, label]) => (
            <div key={mood} className="flex flex-col items-center gap-1.5">
              <Mug mood={mood} optical={false} className="text-ink size-10" />
              <span className="text-ink/50 text-[12px]">{label}</span>
            </div>
          ))}
        </div>
      }
    >
      Two wisps, it’s awake. One, it’s paused. None, your Mac can sleep.
    </Card>

    <Card
      title="One shortcut turns it off"
      visual={
        <div className="flex gap-1.5">
          {["⌥", "⌘", "L"].map((key) => (
            <kbd
              key={key}
              className="bg-surface grid size-11 place-items-center rounded-[10px] font-sans text-[18px] font-medium shadow-[inset_0_-2px_0_rgb(8_21_46/0.08),0_0_0_1px_rgb(8_21_46/0.08)]"
            >
              {key}
            </kbd>
          ))}
        </div>
      }
    >
      Press ⌥⌘L anywhere to turn Afterhours on or off.
    </Card>

    <Card
      title="Hooks for any tool"
      visual={
        <code className="bg-menu block w-full max-w-[230px] rounded-[10px] px-3 py-2.5 font-mono text-[12px] leading-5 text-white/90">
          <span className="text-mac-green">$</span> afterhours-hook amp
          <br />
          <span className="text-white/45">--state</span> working
        </code>
      }
    >
      Anything with hooks can report working, waiting, or idle.
    </Card>

    <Card
      title="Catches stuck sessions"
      visual={
        <MenuRow id="claude" name="Claude Code" status="Idle after 15m" />
      }
    >
      Esc skips Claude Code’s Stop hook, so a silent “working” session times
      out.
    </Card>

    <Card
      title="Private. No network."
      visual={
        <div className="bg-menu w-full max-w-[220px] rounded-[10px] p-3 text-white">
          <div className="flex items-center justify-between text-[12px]">
            <span className="font-medium">Afterhours</span>
            <span className="text-white/45">Network</span>
          </div>
          <div className="border-b-mac-green/70 mt-3 h-5 border-t border-b-[1.5px] border-dashed [border-bottom-style:solid] border-t-white/10" />
          <dl className="mt-2.5 grid grid-cols-[1fr_auto] gap-y-1 text-[12px] tabular-nums">
            <dt className="text-white/55">Sent</dt>
            <dd className="text-right">0 B</dd>
            <dt className="text-white/55">Received</dt>
            <dd className="text-right">0 B</dd>
          </dl>
        </div>
      }
    >
      It reads process names to spot agents, never your code or terminal.
    </Card>
  </div>
);
