import { cva } from "class-variance-authority";
import { cn } from "cn";
import { useEffect, useId, useRef, useState } from "react";
import type { RefObject } from "react";

import { AgentLogo } from "./agent-logo";

type Verdict = "fine" | "tight" | "out";

interface Segment {
  left: number;
  verdict: Verdict;
  pace?: number;
}

interface UsageWindow {
  id: string;
  label: string;
  resetsIn: number;
  outlook: { runsOutIn: number } | { projectedLeft: number };
  segments: Segment[];
}

interface Pool {
  id: string;
  name: string;
  plan?: string;
  accounts: number;
  where: string;
  windows: UsageWindow[];
}

const pools: Pool[] = [
  {
    accounts: 2,
    id: "claude",
    name: "Claude Code",
    plan: "Max",
    where: "2 accounts",
    windows: [
      {
        id: "session",
        label: "Session",
        outlook: { runsOutIn: 38 },
        resetsIn: 77,
        segments: [
          { left: 40, verdict: "fine" },
          { left: 9, pace: 0.62, verdict: "out" },
        ],
      },
      {
        id: "weekly",
        label: "Weekly",
        outlook: { projectedLeft: 8 },
        resetsIn: 1277,
        segments: [
          { left: 41, pace: 0.68, verdict: "tight" },
          { left: 30, pace: 0.68, verdict: "tight" },
        ],
      },
    ],
  },
  {
    accounts: 1,
    id: "codex",
    name: "Codex",
    plan: "Pro",
    where: "~/.codex",
    windows: [
      {
        id: "session",
        label: "Session",
        outlook: { projectedLeft: 54 },
        resetsIn: 221,
        segments: [{ left: 88, verdict: "fine" }],
      },
      {
        id: "weekly",
        label: "Weekly",
        outlook: { projectedLeft: 29 },
        resetsIn: 5220,
        segments: [{ left: 66, verdict: "fine" }],
      },
    ],
  },
  {
    accounts: 1,
    id: "antigravity",
    name: "Antigravity",
    where: "Google account",
    windows: [
      {
        id: "pro",
        label: "Pro",
        outlook: { projectedLeft: 61 },
        resetsIn: 262,
        segments: [{ left: 91, verdict: "fine" }],
      },
      {
        id: "flash",
        label: "Flash",
        outlook: { projectedLeft: 83 },
        resetsIn: 262,
        segments: [{ left: 97, verdict: "fine" }],
      },
    ],
  },
];

const rank: Record<Verdict, number> = { fine: 0, out: 2, tight: 1 };

const worst = (segments: Segment[]) => {
  let verdict: Verdict = "fine";

  for (const { verdict: candidate } of segments) {
    if (rank[candidate] > rank[verdict]) {
      verdict = candidate;
    }
  }

  return verdict;
};

const pooledLeft = (usage: UsageWindow) =>
  Math.round(
    usage.segments.reduce((sum, segment) => sum + segment.left, 0) /
      usage.segments.length
  );

const fullestWindow = (pool: Pool) => {
  const [fullest] = pool.windows.toSorted(
    (a, b) => pooledLeft(a) - pooledLeft(b)
  );

  return fullest;
};

const needsAttention = (pool: Pool) =>
  pool.windows.some((usage) => worst(usage.segments) !== "fine");

const spokenSummary = (pool: Pool) => {
  const fullest = fullestWindow(pool);
  const verdict = worst(fullest.segments);
  const text = `${pool.name}: ${fullest.label} ${pooledLeft(fullest)}% left`;

  if (verdict === "tight") {
    return `${text}, running low`;
  }

  return verdict === "out" ? `${text}, running out` : text;
};

const countdown = (minutes: number) => {
  const left = Math.max(0, minutes);

  if (left === 0) {
    return "now";
  }

  if (left < 60) {
    return `in ${left}m`;
  }

  if (left < 1440) {
    return `in ${Math.floor(left / 60)}h ${left % 60}m`;
  }

  return `in ${Math.floor(left / 1440)}d ${Math.floor((left % 1440) / 60)}h`;
};

const settle = (progress: number) => 1 - (1 - progress) ** 5;

const badge = cva("text-[12px] font-medium tabular-nums", {
  variants: {
    verdict: {
      fine: "text-mac-blue",
      out: "text-mac-red",
      tight: "text-mac-orange",
    },
  },
});

const tone = cva("", {
  variants: {
    verdict: {
      fine: "text-white/55",
      out: "text-mac-red",
      tight: "text-mac-orange",
    },
  },
});

const fill = cva("h-full min-w-[5px] rounded-full", {
  variants: {
    verdict: {
      fine: "bg-mac-blue",
      out: "bg-mac-red",
      tight: "bg-mac-orange",
    },
  },
});

const collapsible =
  "grid grid-rows-[0fr] opacity-0 transition-[grid-template-rows,opacity] duration-300 ease-out data-[expanded]:grid-rows-[1fr] data-[expanded]:opacity-100 motion-reduce:transition-opacity";

const Chevron = ({ className }: { className?: string }) => (
  <svg
    viewBox="0 0 12 12"
    fill="none"
    stroke="currentColor"
    strokeWidth="2"
    strokeLinecap="round"
    strokeLinejoin="round"
    aria-hidden="true"
    className={className}
  >
    <path d="M4.5 2.5 8 6l-3.5 3.5" />
  </svg>
);

const Warning = ({ reasons }: { reasons: string }) => (
  <span className="text-mac-orange flex shrink-0">
    <svg viewBox="0 0 16 16" aria-hidden="true" className="size-3">
      <title>{reasons}</title>
      <path
        d="M8 1.4c.5 0 .9.3 1.2.7l5.9 10.4c.5.9-.1 2-1.2 2H2.1c-1.1 0-1.7-1.1-1.2-2L6.8 2.1c.3-.4.7-.7 1.2-.7Z"
        fill="currentColor"
      />
      <path
        d="M8 5.7v3.9"
        className="stroke-menu"
        strokeWidth="1.5"
        strokeLinecap="round"
      />
      <circle cx="8" cy="11.9" r="0.9" className="fill-menu" />
    </svg>
    <span className="sr-only">Needs attention</span>
  </span>
);

const Badges = () => {
  const reasons = pools.flatMap((pool) =>
    needsAttention(pool) ? [`${pool.name} needs attention`] : []
  );

  return (
    <span className="flex shrink-0 items-center gap-2">
      {reasons.length > 0 && <Warning reasons={reasons.join("\n")} />}
      {pools.map((pool) => {
        const fullest = fullestWindow(pool);

        return (
          <span key={pool.id} className="flex items-center gap-[5px]">
            <span className="sr-only">{spokenSummary(pool)}</span>
            <AgentLogo
              id={pool.id}
              className="size-[18px] rounded-[5px] bg-white/10 text-white outline-[0.5px] -outline-offset-[0.5px] outline-white/10"
            />
            <span
              aria-hidden="true"
              className={badge({ verdict: worst(fullest.segments) })}
            >
              {pooledLeft(fullest)}%
            </span>
          </span>
        );
      })}
    </span>
  );
};

const Meter = ({ usage }: { usage: UsageWindow }) => (
  <span className="flex h-[5px] w-4 rounded-full bg-white/15">
    <span
      className={fill({ verdict: worst(usage.segments) })}
      style={{ width: `${pooledLeft(usage)}%` }}
    />
  </span>
);

const detail = (usage: UsageWindow, elapsed: number) => {
  const outlook =
    "runsOutIn" in usage.outlook
      ? `Runs out ${countdown(usage.outlook.runsOutIn - elapsed)}`
      : `~${usage.outlook.projectedLeft}% left at reset`;

  return `${outlook} · resets ${countdown(usage.resetsIn - elapsed)}`;
};

const Bar = ({ usage, elapsed }: { usage: UsageWindow; elapsed: number }) => {
  const verdict = worst(usage.segments);

  return (
    <div className="col-span-3 grid grid-cols-subgrid items-center gap-y-1">
      <span className="text-[12px] font-medium">{usage.label}</span>
      <div
        aria-hidden="true"
        className={cn("flex h-[5px]", {
          "gap-[3px]": usage.segments.length > 1,
        })}
      >
        {usage.segments.map((segment, index) => (
          <div
            key={`${usage.id}-${index}`}
            className="relative flex-1 rounded-full bg-white/15"
          >
            <div
              className={fill({ verdict: segment.verdict })}
              style={{ width: `${segment.left}%` }}
            />
            {segment.pace !== undefined && segment.verdict !== "fine" && (
              <div
                className="absolute -top-0.5 h-[9px] w-0.5 -translate-x-1/2 rounded-[1px] bg-white/55"
                style={{ left: `${(1 - segment.pace) * 100}%` }}
              />
            )}
          </div>
        ))}
      </div>
      <span className="min-w-[34px] text-right text-[12px] tabular-nums">
        {pooledLeft(usage)}%<span className="sr-only"> left</span>
      </span>
      {verdict !== "fine" && (
        <span
          className={cn(
            "col-span-3 text-[11px] tabular-nums",
            tone({ verdict })
          )}
        >
          {detail(usage, elapsed)}
        </span>
      )}
    </div>
  );
};

const PoolRow = ({
  pool,
  open,
  elapsed,
  onToggle,
}: {
  pool: Pool;
  open: boolean;
  elapsed: number;
  onToggle: () => void;
}) => {
  const id = useId();
  const fullest = fullestWindow(pool);

  return (
    <div className="flex flex-col">
      <button
        type="button"
        aria-expanded={open}
        aria-controls={id}
        aria-label={spokenSummary(pool)}
        onClick={onToggle}
        className="group flex w-full items-center gap-1.5 text-left transition-opacity duration-150 ease-out active:opacity-55 active:duration-0"
      >
        <AgentLogo
          id={pool.id}
          className="mr-1.5 size-[22px] rounded-[6px] bg-white/10 text-white outline-[0.5px] -outline-offset-[0.5px] outline-white/10"
        />
        <span className="text-[13px] font-medium whitespace-nowrap">
          {pool.name}
        </span>
        {pool.plan && (
          <span className="text-[12px] text-white/45 contrast-more:text-white/75">
            {pool.plan}
          </span>
        )}
        <Chevron
          className={cn(
            "size-[9px] text-white/45 transition-transform duration-200 ease-out group-hover:text-white/55 motion-reduce:transition-none contrast-more:text-white/75",
            { "rotate-90": open }
          )}
        />
        <span className="ml-auto flex min-w-0 items-center gap-2">
          {open ? (
            <span
              key="where"
              className="blur-in truncate text-[12px] text-white/45 tabular-nums contrast-more:text-white/75"
            >
              {pool.accounts > 1 ? `${pool.accounts} accounts` : pool.where}
            </span>
          ) : (
            <span key="meters" className="blur-in flex items-center gap-2">
              <span aria-hidden="true" className="flex items-center gap-[3px]">
                {pool.windows.map((usage) => (
                  <Meter key={usage.id} usage={usage} />
                ))}
              </span>
              <span
                aria-hidden="true"
                className={cn(
                  "min-w-[34px] text-right text-[12px] font-medium tabular-nums",
                  tone({ verdict: worst(fullest.segments) })
                )}
              >
                {pooledLeft(fullest)}%
              </span>
            </span>
          )}
        </span>
      </button>
      <div
        id={id}
        inert={!open}
        data-expanded={open || undefined}
        className={collapsible}
      >
        <div className="flex min-h-0 flex-col justify-end overflow-hidden motion-reduce:justify-start">
          <div className="mt-2 grid grid-cols-[max-content_1fr_auto] gap-x-2 gap-y-2 rounded-[10px] bg-white/[0.06] px-3 py-2.5">
            {pool.windows.map((usage) => (
              <Bar key={usage.id} usage={usage} elapsed={elapsed} />
            ))}
          </div>
        </div>
      </div>
    </div>
  );
};

export const Limits = ({
  expanded,
  elapsed,
  asOf,
  menu,
  onToggle,
}: {
  expanded: boolean;
  elapsed: number;
  asOf: string;
  menu: RefObject<HTMLDivElement | null>;
  onToggle: () => void;
}) => {
  const id = useId();
  const [opened, setOpened] = useState<Record<string, boolean>>({});
  const row = useRef<HTMLButtonElement>(null);
  const body = useRef<HTMLDivElement>(null);
  const frame = useRef(0);

  useEffect(() => {
    const scroller = menu.current;
    const halt = () => cancelAnimationFrame(frame.current);
    scroller?.addEventListener("wheel", halt, { passive: true });
    scroller?.addEventListener("touchstart", halt, { passive: true });

    return () => {
      halt();
      scroller?.removeEventListener("wheel", halt);
      scroller?.removeEventListener("touchstart", halt);
    };
  }, [menu]);

  const reveal = () => {
    cancelAnimationFrame(frame.current);
    const scroller = menu.current;

    if (!scroller || !row.current || !body.current) {
      return;
    }

    const start = scroller.scrollTop;

    const end = Math.min(
      row.current.offsetTop - 10,
      scroller.scrollHeight + body.current.offsetHeight - scroller.clientHeight
    );

    if (end <= start) {
      return;
    }

    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      frame.current = requestAnimationFrame(() => {
        scroller.scrollTop = end;
      });

      return;
    }

    const began = performance.now();

    const step = (time: number) => {
      const progress = Math.min(1, (time - began) / 300);
      scroller.scrollTop = start + (end - start) * settle(progress);

      if (progress < 1) {
        frame.current = requestAnimationFrame(step);
      }
    };

    frame.current = requestAnimationFrame(step);
  };

  return (
    <section className="px-4 py-2.5">
      <button
        ref={row}
        type="button"
        aria-expanded={expanded}
        aria-controls={id}
        onClick={() => {
          cancelAnimationFrame(frame.current);
          onToggle();

          if (!expanded) {
            reveal();
          }
        }}
        className="group flex w-full items-center gap-1.5 text-left transition-opacity duration-150 ease-out active:opacity-55 active:duration-0"
      >
        <span className="text-[15px] font-bold">Limits</span>
        <Chevron
          className={cn(
            "size-[11px] text-white/45 transition-transform duration-200 ease-out group-hover:text-white/55 motion-reduce:transition-none contrast-more:text-white/75",
            { "rotate-90": expanded }
          )}
        />
        <span key={String(expanded)} className="blur-in ml-auto">
          {expanded ? (
            <span className="text-[12px] text-white/45 tabular-nums contrast-more:text-white/75">
              As of {asOf}
            </span>
          ) : (
            <Badges />
          )}
        </span>
      </button>
      <div
        id={id}
        inert={!expanded}
        data-expanded={expanded || undefined}
        className={collapsible}
      >
        <div className="flex min-h-0 flex-col justify-end overflow-hidden motion-reduce:justify-start">
          <div ref={body} className="flex flex-col gap-2 pt-2.5">
            {pools.map((pool) => (
              <PoolRow
                key={pool.id}
                pool={pool}
                open={opened[pool.id] ?? needsAttention(pool)}
                elapsed={elapsed % 30}
                onToggle={() =>
                  setOpened((state) => ({
                    ...state,
                    [pool.id]: !(state[pool.id] ?? needsAttention(pool)),
                  }))
                }
              />
            ))}
          </div>
        </div>
      </div>
    </section>
  );
};
