import { cva } from "class-variance-authority";
import { cn } from "cn";
import { useId, useRef } from "react";
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
  plan: string;
  where: string;
  windows: UsageWindow[];
}

const pools: Pool[] = [
  {
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
          { left: 64, verdict: "fine" },
          { left: 21, pace: 0.62, verdict: "out" },
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

const outlookText = cva("text-[12px] tabular-nums", {
  variants: {
    verdict: {
      fine: "text-white/45",
      out: "text-mac-red",
      tight: "text-mac-orange",
    },
  },
});

const fill = cva("h-full min-w-1.5 rounded-full", {
  variants: {
    verdict: {
      fine: "bg-mac-blue",
      out: "bg-mac-red",
      tight: "bg-mac-orange",
    },
  },
});

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

const Badges = () => (
  <span aria-hidden="true" className="flex items-center gap-2.5">
    {pools.map((pool) => {
      const [fullest] = pool.windows.toSorted(
        (a, b) => pooledLeft(a) - pooledLeft(b)
      );
      return (
        <span key={pool.id} className="flex items-center gap-[5px]">
          <AgentLogo
            id={pool.id}
            className="size-[18px] rounded-[5px] bg-white/10 text-white outline-[0.5px] -outline-offset-[0.5px] outline-white/10"
          />
          <span className={badge({ verdict: worst(fullest.segments) })}>
            {pooledLeft(fullest)}%
          </span>
        </span>
      );
    })}
  </span>
);

const Bar = ({ usage, elapsed }: { usage: UsageWindow; elapsed: number }) => {
  const verdict = worst(usage.segments);
  const outlook =
    "runsOutIn" in usage.outlook
      ? `Runs out ${countdown(usage.outlook.runsOutIn - elapsed)}`
      : `~${usage.outlook.projectedLeft}% left at reset`;

  return (
    <div className="flex flex-col gap-[5px]">
      <div className="flex items-baseline justify-between gap-2">
        <span className="text-[13px] font-semibold">{usage.label}</span>
        <span className={outlookText({ verdict })}>{outlook}</span>
      </div>
      <div
        aria-hidden="true"
        className={cn("flex h-1.5", { "gap-[3px]": usage.segments.length > 1 })}
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
                className="absolute -top-0.5 h-2.5 w-0.5 -translate-x-1/2 rounded-[1px] bg-white/55"
                style={{ left: `${(1 - segment.pace) * 100}%` }}
              />
            )}
          </div>
        ))}
      </div>
      <div className="flex items-baseline justify-between gap-2 tabular-nums">
        <span className="text-[13px]">{pooledLeft(usage)}% left</span>
        <span className="text-[12px] text-white/45">
          Resets {countdown(usage.resetsIn - elapsed)}
        </span>
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
  const row = useRef<HTMLButtonElement>(null);
  const body = useRef<HTMLDivElement>(null);

  const reveal = () => {
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
      requestAnimationFrame(() => {
        scroller.scrollTop = end;
      });
      return;
    }
    const began = performance.now();
    const step = (time: number) => {
      const progress = Math.min(1, (time - began) / 300);
      scroller.scrollTop = start + (end - start) * settle(progress);
      if (progress < 1) {
        requestAnimationFrame(step);
      }
    };
    requestAnimationFrame(step);
  };

  return (
    <section className="px-4 py-2.5">
      <button
        ref={row}
        type="button"
        aria-expanded={expanded}
        aria-controls={id}
        onClick={() => {
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
            "size-[11px] text-white/45 transition-transform duration-200 ease-out group-hover:text-white/55 motion-reduce:transition-none",
            { "rotate-90": expanded }
          )}
        />
        <span key={String(expanded)} className="blur-in ml-auto">
          {expanded ? (
            <span className="text-[12px] text-white/45 tabular-nums">
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
        className="grid grid-rows-[0fr] opacity-0 transition-[grid-template-rows,opacity] duration-300 ease-out data-[expanded]:grid-rows-[1fr] data-[expanded]:opacity-100 motion-reduce:transition-opacity"
      >
        <div className="flex min-h-0 flex-col justify-end overflow-hidden motion-reduce:justify-start">
          <div ref={body} className="flex flex-col gap-3.5 pt-2.5">
            {pools.map((pool) => (
              <div key={pool.id} className="flex flex-col gap-2">
                <div className="flex items-center gap-1.5">
                  <AgentLogo
                    id={pool.id}
                    className="mr-1 size-[22px] rounded-[6px] bg-white/10 text-white outline-[0.5px] -outline-offset-[0.5px] outline-white/10"
                  />
                  <span className="text-[13px] font-semibold">{pool.name}</span>
                  <span className="text-[12px] text-white/45">{pool.plan}</span>
                  <span className="ml-auto truncate text-[12px] text-white/45 tabular-nums">
                    {pool.where}
                  </span>
                </div>
                <div className="flex flex-col gap-3 rounded-[10px] bg-white/[0.06] px-3 py-2.5">
                  {pool.windows.map((usage) => (
                    <Bar key={usage.id} usage={usage} elapsed={elapsed} />
                  ))}
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
};
