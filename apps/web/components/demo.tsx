"use client";

import { cn } from "cn";
import { useEffect, useRef, useState } from "react";
import type { ReactNode } from "react";

import { AgentLogo } from "./agent-logo";
import { Limits } from "./demo-limits";
import { AppleIcon, BatteryIcon, WifiIcon } from "./icons";
import { Mug } from "./mug";
import type { Mood } from "./mug";
import { pill } from "./pill";
import { agents } from "./site";
import type { AgentState } from "./site";

interface DemoAgent {
  id: string;
  name: string;
  state: AgentState;
  sessions: number;
}

type Hold = "disabled" | "paused" | "working" | "waiting" | "idle";

const START_MINUTES = 60 + 47;
const AWAKE_FOR = 42;
const BATTERY = 82;
const CUTOFF = 15;

const pick = (id: string) => {
  const agent = agents.find((a) => a.id === id);
  if (!agent) {
    throw new Error(`Unknown agent: ${id}`);
  }
  return { id: agent.id, name: agent.name };
};

const initialAgents: DemoAgent[] = [
  { ...pick("claude"), sessions: 2, state: "working" },
  { ...pick("codex"), sessions: 1, state: "waiting" },
  { ...pick("opencode"), sessions: 0, state: "idle" },
];

const nextState: Record<AgentState, AgentState> = {
  idle: "working",
  waiting: "idle",
  working: "waiting",
};

const moodFor: Record<Hold, Mood> = {
  disabled: "asleep",
  idle: "asleep",
  paused: "drowsy",
  waiting: "awake",
  working: "awake",
};

const span = (minutes: number) =>
  `${Math.floor(minutes / 60)}h ${String(minutes % 60).padStart(2, "0")}m`;

const clock = (minutes: number) => {
  const h24 = Math.floor(minutes / 60) % 24;
  const h = h24 % 12 || 12;
  const suffix = h24 < 12 ? "AM" : "PM";
  return `${h}:${String(minutes % 60).padStart(2, "0")} ${suffix}`;
};

const holdFor = ({
  enabled,
  paused,
  working,
  waiting,
}: {
  enabled: boolean;
  paused: boolean;
  working: boolean;
  waiting: boolean;
}): Hold => {
  if (!enabled) {
    return "disabled";
  }
  if (paused) {
    return "paused";
  }
  if (working) {
    return "working";
  }
  return waiting ? "waiting" : "idle";
};

const useElapsedMinutes = () => {
  const [minutes, setMinutes] = useState(0);
  useEffect(() => {
    const start = Date.now();
    const id = setInterval(() => {
      setMinutes(Math.floor((Date.now() - start) / 60_000));
    }, 1000);
    return () => clearInterval(id);
  }, []);
  return minutes;
};

const Divider = () => <div className="mx-4 h-px bg-white/10" />;

const Switch = ({ on, onToggle }: { on: boolean; onToggle: () => void }) => (
  <button
    type="button"
    role="switch"
    aria-checked={on}
    aria-label="Keep your Mac awake while agents work"
    onClick={onToggle}
    className="press aria-checked:bg-mac-blue relative h-6 w-10 shrink-0 rounded-full bg-white/20 transition-colors duration-200 ease-out"
  >
    <span
      className={cn(
        "absolute top-0.5 left-0.5 size-5 rounded-full bg-white shadow-[0_1px_3px_rgb(0_0_0/0.4)] transition-transform duration-250 ease-out motion-reduce:transition-none",
        on && "translate-x-4"
      )}
    />
  </button>
);

const Chip = ({
  children,
  onClick,
}: {
  children: ReactNode;
  onClick: () => void;
}) => (
  <button
    type="button"
    onClick={onClick}
    className="press rounded-[6px] bg-white/10 px-2.5 py-1 text-[12px] font-medium text-white/90 hover:bg-white/[0.18]"
  >
    {children}
  </button>
);

const MenuItem = ({
  children,
  shortcut,
  onClick,
}: {
  children: string;
  shortcut: string;
  onClick: () => void;
}) => (
  <button
    type="button"
    onClick={onClick}
    className="group hover:bg-mac-blue flex items-center justify-between rounded-[4px] px-2 py-1 text-left text-[13px]"
  >
    {children}
    <span className="text-[12px] text-white/45 group-hover:text-white/80">
      {shortcut}
    </span>
  </button>
);

const AgentStatus = ({ agent }: { agent: DemoAgent }) => {
  if (agent.state === "idle") {
    return <span className="text-white/45">Idle</span>;
  }
  const working = agent.state === "working";
  const sessions =
    agent.sessions === 1 ? "1 session" : `${agent.sessions} sessions`;
  return (
    <>
      <span className="text-white/55">{working ? sessions : "Needs you"}</span>
      <span
        className={cn("size-[7px] rounded-full", {
          "bg-mac-green": working,
          "bg-mac-orange": !working,
        })}
      />
    </>
  );
};

const AgentRow = ({
  agent,
  onClick,
}: {
  agent: DemoAgent;
  onClick: () => void;
}) => {
  const active = agent.state !== "idle";
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label={`${agent.name}: ${agent.state}. Change state`}
      className="flex w-full items-center gap-3 rounded-[6px] px-2 py-1 text-left hover:bg-white/[0.07]"
    >
      <AgentLogo
        id={agent.id}
        className="size-[22px] rounded-[6px] bg-white/10 text-white outline-[0.5px] -outline-offset-[0.5px] outline-white/10 transition-opacity duration-200 ease-out"
        style={{ opacity: active ? 1 : 0.45 }}
      />
      <span
        className="flex-1 text-[13px] font-medium transition-opacity duration-200 ease-out"
        style={{ opacity: active ? 1 : 0.45 }}
      >
        {agent.name}
      </span>
      <span
        key={agent.state}
        className="blur-in flex items-center gap-2 text-[12px] tabular-nums"
      >
        <AgentStatus agent={agent} />
      </span>
    </button>
  );
};

const MenuBar = ({
  mood,
  now,
  menuOpen,
  onToggleMenu,
}: {
  mood: Mood;
  now: number;
  menuOpen: boolean;
  onToggleMenu: () => void;
}) => (
  <div className="relative z-10 flex h-8 items-center justify-between bg-black/20 px-3.5 text-[13px] text-white [text-shadow:0_1px_2px_rgb(0_0_0/0.25)]">
    <div className="flex items-center gap-4">
      <AppleIcon className="-mt-px size-3.5" />
      <span className="font-semibold">Terminal</span>
      <span className="hidden gap-4 @2xl:flex">
        <span>Shell</span>
        <span>Edit</span>
        <span>View</span>
        <span className="hidden @3xl:inline">Window</span>
        <span className="hidden @3xl:inline">Help</span>
      </span>
    </div>
    <div className="flex items-center gap-2.5 @md:gap-3.5">
      <button
        type="button"
        onClick={onToggleMenu}
        aria-label="Afterhours menu"
        aria-expanded={menuOpen}
        className="-mx-1.5 grid h-[22px] w-8 place-items-center rounded-[5px] aria-expanded:bg-white/20"
      >
        <Mug key={mood} mood={mood} compact className="blur-in size-[18px]" />
      </button>
      <BatteryIcon
        percent={BATTERY}
        className="hidden h-3 w-[25px] @md:block"
      />
      <WifiIcon className="hidden h-3 w-4 @md:block" />
      <span className="tabular-nums">
        <span className="hidden @md:inline">Thu </span>
        {clock(now)}
      </span>
    </div>
  </div>
);

const Wallpaper = () => (
  <svg
    aria-hidden="true"
    viewBox="0 0 1600 1040"
    preserveAspectRatio="xMidYMid slice"
    className="absolute inset-0 size-full [will-change:transform]"
  >
    <defs>
      <linearGradient id="wp-sky" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stopColor="#10163f" />
        <stop offset="0.5" stopColor="#35296b" />
        <stop offset="0.8" stopColor="#9a5a86" />
        <stop offset="1" stopColor="#f0a07a" />
      </linearGradient>
      <linearGradient id="wp-back" x1="0" y1="0" x2="1" y2="1">
        <stop offset="0" stopColor="#7c68e0" />
        <stop offset="1" stopColor="#2a2170" />
      </linearGradient>
      <linearGradient id="wp-front" x1="0" y1="1" x2="1" y2="0">
        <stop offset="0" stopColor="#081048" />
        <stop offset="0.5" stopColor="#1f3fc4" />
        <stop offset="0.85" stopColor="#5b86f2" />
        <stop offset="1" stopColor="#b9ccff" />
      </linearGradient>
      <linearGradient id="wp-sheen" x1="0" y1="1" x2="1" y2="0">
        <stop offset="0" stopColor="#fff" stopOpacity="0" />
        <stop offset="0.55" stopColor="#dfe8ff" stopOpacity="0.5" />
        <stop offset="1" stopColor="#fff" stopOpacity="0.15" />
      </linearGradient>
      <filter id="wp-far" x="-20%" y="-20%" width="140%" height="140%">
        <feGaussianBlur stdDeviation="26" />
      </filter>
      <filter id="wp-near" x="-10%" y="-10%" width="120%" height="120%">
        <feGaussianBlur stdDeviation="5" />
      </filter>
    </defs>
    <rect width="1600" height="1040" fill="url(#wp-sky)" />
    <g filter="url(#wp-far)">
      <ellipse
        cx="330"
        cy="610"
        rx="300"
        ry="90"
        fill="#4fb6ff"
        opacity="0.45"
      />
      <path
        d="M-60 660C240 520 420 720 720 610S1180 360 1660 420V1100H-60Z"
        fill="url(#wp-back)"
      />
    </g>
    <path
      d="M0 900C380 900 560 760 820 560S1300 120 1600 60V1040H0Z"
      fill="url(#wp-front)"
      filter="url(#wp-near)"
    />
    <path
      d="M0 900C380 900 560 760 820 560S1300 120 1600 60"
      fill="none"
      stroke="url(#wp-sheen)"
      strokeWidth="3"
    />
    <path
      d="M-60 1010C500 1020 900 930 1250 820S1660 700 1660 700V1100H-60Z"
      fill="#050a2a"
      opacity="0.8"
      filter="url(#wp-far)"
    />
  </svg>
);

const Notch = () => (
  <div className="absolute top-0 left-1/2 z-20 h-8 w-[13%] min-w-16 -translate-x-1/2 rounded-b-[9px] bg-black">
    <span className="absolute top-0 right-full size-1.5 bg-[radial-gradient(circle_at_0_100%,transparent_5.5px,#000_6px)]" />
    <span className="absolute top-0 left-full size-1.5 bg-[radial-gradient(circle_at_100%_100%,transparent_5.5px,#000_6px)]" />
    <span className="absolute top-1/2 left-1/2 size-[7px] -translate-1/2 rounded-full bg-[radial-gradient(circle_at_40%_35%,#2a3550,#07080c_70%)] shadow-[0_0_0_1.5px_#0d0d10]" />
  </div>
);

const Base = () => (
  <div className="relative z-10 -mx-[9cqw] h-[2.2cqw] min-h-3">
    <div className="absolute inset-x-[4%] -bottom-[2.6cqw] h-[3.4cqw] bg-[radial-gradient(50%_50%_at_50%_50%,rgb(0_0_0/0.55),transparent)]" />
    <div className="absolute bottom-[-0.3cqw] left-[6%] h-[0.5cqw] w-[5%] rounded-full bg-black/80" />
    <div className="absolute right-[6%] bottom-[-0.3cqw] h-[0.5cqw] w-[5%] rounded-full bg-black/80" />
    <div className="grain relative size-full overflow-hidden rounded-t-[0.5cqw] rounded-b-[1.4cqw] bg-[linear-gradient(180deg,#56565b_0%,#3a3a3e_22%,#26262a_30%,#1c1c1f_70%,#0f0f11_100%)] shadow-[inset_0_-1px_0_rgb(255_255_255/0.08)]">
      <div className="absolute top-0 left-1/2 z-10 h-[72%] w-[17.3%] -translate-x-1/2 rounded-b-[0.9cqw] bg-[linear-gradient(180deg,#232326,#3c3c40_55%,#4a4a4e)] shadow-[inset_0_1px_2px_rgb(0_0_0/0.7)]" />
    </div>
  </div>
);

interface MenuProps {
  open: boolean;
  hold: Hold;
  status: string;
  enabled: boolean;
  paused: boolean;
  list: DemoAgent[];
  limitsOpen: boolean;
  elapsed: number;
  asOf: string;
  onToggleLimits: () => void;
  onToggle: () => void;
  onPause: (minutes: number) => void;
  onResume: () => void;
  onCycle: (id: string) => void;
  onClose: () => void;
}

const Menu = ({
  open,
  hold,
  status,
  enabled,
  paused,
  list,
  limitsOpen,
  elapsed,
  asOf,
  onToggleLimits,
  onToggle,
  onPause,
  onResume,
  onCycle,
  onClose,
}: MenuProps) => {
  const holding = hold === "working" || hold === "waiting";
  const mood = moodFor[hold];
  const workingCount = list.filter((a) => a.state === "working").length;
  const scroller = useRef<HTMLDivElement>(null);

  return (
    <div
      ref={scroller}
      data-open={open || undefined}
      inert={!open}
      className="bg-menu/[0.86] absolute inset-x-0 top-[38px] z-10 mx-auto max-h-[calc(100%-46px)] w-[min(300px,calc(100%-16px))] origin-top [transform:scale(0.97)] [scrollbar-width:none] overflow-y-auto rounded-[12px] text-white opacity-0 shadow-[0_0_0_0.5px_rgb(0_0_0/0.8),0_18px_50px_rgb(0_0_0/0.45)] ring-1 ring-white/10 backdrop-blur-2xl transition-[opacity,transform] duration-100 ease-out ring-inset data-[open]:[transform:none] data-[open]:opacity-100 data-[open]:duration-150 md:right-2 md:left-auto md:mx-0 md:origin-[50%_0]"
    >
      <div className="flex items-center gap-2.5 px-4 pt-3 pb-2.5">
        <div
          className="data-[holding]:bg-mac-blue grid size-8 shrink-0 place-items-center rounded-[8px] bg-white/10 transition-colors duration-200 ease-out"
          data-holding={holding || undefined}
        >
          <Mug
            key={mood}
            mood={mood}
            className={cn("blur-in size-[26px] text-white", {
              "opacity-70": !holding,
            })}
          />
        </div>
        <div className="min-w-0 flex-1">
          <p className="text-[15px] leading-5 font-bold">Afterhours</p>
          <p
            key={hold}
            className="blur-in text-[12px] leading-4 text-white/55 tabular-nums"
          >
            {status}
          </p>
        </div>
        <Switch on={enabled} onToggle={onToggle} />
      </div>

      <Divider />
      <section className="px-4 py-2.5">
        <h3 className="text-[15px] font-bold">Battery</h3>
        <div className="mt-2.5 h-[7px] rounded-full bg-white/15">
          <div
            className="bg-mac-green h-full rounded-full"
            style={{ width: `${BATTERY}%` }}
          />
        </div>
        <div className="mt-2 flex justify-between text-[12px] tabular-nums">
          <span className="font-medium">{BATTERY}% left</span>
          <span className="text-white/45">Stops below {CUTOFF}%</span>
        </div>
      </section>

      <Divider />
      <section className="px-4 py-2.5">
        <div className="flex items-baseline justify-between">
          <h3 className="text-[15px] font-bold">Agents</h3>
          <span className="text-[12px] text-white/45 tabular-nums">
            {workingCount === 0 ? "None working" : `${workingCount} working`}
          </span>
        </div>
        <ul className="-mx-2 mt-1">
          {list.map((agent) => (
            <li key={agent.id}>
              <AgentRow agent={agent} onClick={() => onCycle(agent.id)} />
            </li>
          ))}
        </ul>
      </section>

      <Divider />
      <Limits
        expanded={limitsOpen}
        elapsed={elapsed}
        asOf={asOf}
        menu={scroller}
        onToggle={onToggleLimits}
      />

      <Divider />
      <section className="flex items-center justify-between px-4 py-2.5">
        <h3 className="text-[15px] font-bold">Pause</h3>
        <div className="flex gap-2">
          {paused ? (
            <Chip onClick={onResume}>Resume</Chip>
          ) : (
            <>
              <Chip onClick={() => onPause(30)}>30 min</Chip>
              <Chip onClick={() => onPause(60)}>1 hour</Chip>
            </>
          )}
        </div>
      </section>

      <Divider />
      <div className="flex flex-col gap-0.5 px-2 py-1.5">
        <MenuItem shortcut="⌘," onClick={onClose}>
          Settings…
        </MenuItem>
        <MenuItem shortcut="⌘Q" onClick={onClose}>
          Quit Afterhours
        </MenuItem>
      </div>
    </div>
  );
};

const ClosedCard = ({
  hold,
  sessions,
  elapsed,
}: {
  hold: Hold;
  sessions: number;
  elapsed: number;
}) => {
  const awake = hold === "working" || hold === "waiting";
  const plural = sessions === 1 ? "session" : "sessions";
  const copy: Record<Hold, [string, string]> = {
    disabled: [
      "Lid closed. Sleeping.",
      "Afterhours is off, so your Mac sleeps normally",
    ],
    idle: [
      "Lid closed. Sleeping.",
      "Nothing is working, so your Mac can sleep",
    ],
    paused: [
      "Lid closed. Dozing off.",
      "Paused, so your Mac sleeps like it normally would",
    ],
    waiting: [
      "Lid closed. Still brewing.",
      "An agent needs you, so your Mac waits for your reply",
    ],
    working: [
      "Lid closed. Still brewing.",
      `${sessions} ${plural} working · awake for ${span(AWAKE_FOR + elapsed)}`,
    ],
  };
  const [title, detail] = copy[hold];

  return (
    <div
      className="blur-in pointer-events-none absolute inset-x-0 top-[18%] flex flex-col items-center gap-4 text-center"
      style={{ animationDelay: "450ms", animationFillMode: "backwards" }}
    >
      <Mug
        mood={moodFor[hold]}
        steaming={awake}
        className="size-24 text-white md:size-32"
      />
      <div>
        <p className="font-serif text-[clamp(2rem,4.5vw,3rem)] leading-tight tracking-[-0.02em] text-white">
          {title}
        </p>
        <p className="mt-2 text-[15px] text-white/65 tabular-nums">{detail}</p>
      </div>
    </div>
  );
};

export const Demo = () => {
  const [menuOpen, setMenuOpen] = useState(true);
  const [lidClosed, setLidClosed] = useState(false);
  const [enabled, setEnabled] = useState(true);
  const [pausedUntil, setPausedUntil] = useState<number | null>(null);
  const [list, setList] = useState(initialAgents);
  const [limitsOpen, setLimitsOpen] = useState(false);
  const elapsed = useElapsedMinutes();
  const now = START_MINUTES + elapsed;

  const working = list.filter((a) => a.state === "working");
  const sessions = working.reduce((sum, a) => sum + a.sessions, 0);
  const paused = pausedUntil !== null && pausedUntil > now;
  const hold = holdFor({
    enabled,
    paused,
    waiting: list.some((a) => a.state === "waiting"),
    working: working.length > 0,
  });

  const status: Record<Hold, string> = {
    disabled: "Off. Your Mac sleeps normally",
    idle: "Idle. Your Mac can sleep",
    paused: `Paused until ${clock(pausedUntil ?? now)}`,
    waiting: "Waiting for you while sessions are open",
    working: `Awake for ${span(AWAKE_FOR + elapsed)} · lid can close`,
  };

  const cycle = (id: string) => {
    setList((all) =>
      all.map((a) =>
        a.id === id
          ? {
              ...a,
              sessions: Math.max(a.sessions, 1),
              state: nextState[a.state],
            }
          : a
      )
    );
  };

  const toggleLid = () => {
    setLidClosed((closed) => !closed);
    setMenuOpen(false);
  };

  return (
    <div>
      <div
        className="film overflow-hidden rounded-[20px] px-4 pt-10 pb-12 md:rounded-[32px] md:px-14 md:pt-16 md:pb-20"
        style={{
          background:
            "radial-gradient(55% 45% at 82% 78%, rgb(245 140 80 / 0.75), transparent 70%), radial-gradient(45% 40% at 12% 18%, rgb(96 128 214 / 0.5), transparent 70%), radial-gradient(80% 55% at 45% 105%, rgb(214 98 124 / 0.55), transparent 70%), linear-gradient(180deg, #0a1633 0%, #172659 55%, #2a2c66 100%)",
        }}
      >
        <div className="@container relative z-10 mx-auto max-w-[900px]">
          <div className="relative z-20 [perspective-origin:50%_calc(100%-3.9cqw)] [perspective:444cqw]">
            <div
              className="relative origin-bottom transition-transform duration-[900ms] ease-in-out [transform-style:preserve-3d] data-[closed]:[transform:rotateX(-90deg)] motion-reduce:transition-opacity motion-reduce:duration-300 motion-reduce:data-[closed]:[transform:none] motion-reduce:data-[closed]:opacity-0"
              data-closed={lidClosed || undefined}
              inert={lidClosed}
            >
              <div className="rounded-t-[3.2cqw] bg-[linear-gradient(180deg,#5a5a5f_0%,#2c2c30_1.2%,#1d1d20_100%)] px-[0.35cqw] pt-[0.35cqw] [backface-visibility:hidden]">
                <div className="rounded-t-[2.85cqw] bg-black px-[1.6cqw] pt-[1.6cqw] pb-[2.6cqw] shadow-[inset_0_0_0_1px_rgb(255_255_255/0.04)]">
                  <div
                    className="relative h-[max(520px,62.4cqw)] overflow-hidden rounded-t-[1.25cqw] bg-[#12163a]"
                    onPointerDown={(e) => {
                      if (e.target === e.currentTarget) {
                        setMenuOpen(false);
                      }
                    }}
                  >
                    <Wallpaper />
                    <Notch />
                    <MenuBar
                      mood={moodFor[hold]}
                      now={now}
                      menuOpen={menuOpen}
                      onToggleMenu={() => setMenuOpen((open) => !open)}
                    />
                    <Menu
                      open={menuOpen}
                      hold={hold}
                      status={status[hold]}
                      enabled={enabled}
                      paused={paused}
                      list={list}
                      limitsOpen={limitsOpen}
                      elapsed={elapsed}
                      asOf={clock(now - (elapsed % 5))}
                      onToggleLimits={() => setLimitsOpen((open) => !open)}
                      onToggle={() => setEnabled((on) => !on)}
                      onPause={(minutes) => setPausedUntil(now + minutes)}
                      onResume={() => setPausedUntil(null)}
                      onCycle={cycle}
                      onClose={() => setMenuOpen(false)}
                    />
                    <div
                      className="pointer-events-none absolute inset-0 z-30 bg-black opacity-0 transition-opacity duration-[900ms] ease-in-out data-[closed]:opacity-70"
                      data-closed={lidClosed || undefined}
                    />
                  </div>
                </div>
                <div className="h-[0.7cqw] bg-[linear-gradient(180deg,#26262a,#101012)]" />
              </div>
              <div className="absolute inset-0 [transform:translateZ(-0.9cqw)_rotateX(180deg)] rounded-b-[3.2cqw] bg-[linear-gradient(180deg,#2a2a2e,#3e3e44_70%,#5a5a61)] shadow-[inset_0_-1.5px_0_rgb(255_255_255/0.28)] [backface-visibility:hidden]" />
              <div className="absolute inset-x-0 top-0 h-[0.9cqw] origin-top [transform:translateZ(-0.9cqw)_rotateX(90deg)] rounded-[3.2cqw/0.45cqw] bg-[linear-gradient(180deg,#6b6b72_0%,#3a3a3f_12%,#26262a_60%,#1a1a1d_82%,#030304_88%,#030304_100%)] [backface-visibility:hidden]" />
            </div>
          </div>

          <div
            className="absolute inset-x-[-9cqw] bottom-[2.2cqw] hidden h-[0.9cqw] rounded-t-[0.6cqw] bg-[linear-gradient(180deg,#6a6a70,#2c2c30_40%,#1a1a1d)] opacity-0 transition-opacity duration-150 ease-out data-[closed]:opacity-100 data-[closed]:delay-[750ms] motion-reduce:block"
            data-closed={lidClosed || undefined}
          />

          <Base />

          {lidClosed && (
            <ClosedCard hold={hold} sessions={sessions} elapsed={elapsed} />
          )}
        </div>
      </div>

      <div className="mt-8 flex flex-col items-center gap-3 text-center">
        <p className="text-ink/55 text-[14px] text-balance">
          Psst… it’s interactive. Flip the switch, click an agent, or
        </p>
        <button
          type="button"
          onClick={toggleLid}
          aria-pressed={lidClosed}
          className={pill({ intent: "primary", size: "medium" })}
        >
          {lidClosed ? "Open the lid" : "Close the lid"}
        </button>
      </div>
    </div>
  );
};
