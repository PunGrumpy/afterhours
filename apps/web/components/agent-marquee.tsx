import { cn } from "cn";

import { AgentLogo } from "./agent-logo";
import { agents } from "./site";

const AgentList = ({ hidden = false }: { hidden?: boolean }) => (
  <ul
    aria-hidden={hidden || undefined}
    aria-label={hidden ? undefined : "Works with"}
    className={cn(
      "flex shrink-0 gap-1.5 pr-1.5 motion-reduce:flex-wrap motion-reduce:justify-center motion-reduce:pr-0",
      { "motion-reduce:hidden": hidden }
    )}
  >
    {agents.map((agent) => (
      <li
        key={agent.id}
        className="bg-surface text-ink/80 flex h-9 shrink-0 items-center gap-2 rounded-full pr-3.5 pl-1.5 text-[13px] font-medium whitespace-nowrap"
      >
        <AgentLogo
          id={agent.id}
          className="bg-ink size-6 rounded-full text-white"
        />
        {agent.name}
      </li>
    ))}
  </ul>
);

export const AgentMarquee = () => (
  <div className="w-full overflow-hidden [mask-image:linear-gradient(to_right,transparent,black_12%,black_88%,transparent)] motion-reduce:[mask-image:none]">
    <div className="animate-marquee flex w-max hover:[animation-play-state:paused] motion-reduce:w-full motion-reduce:animate-none motion-reduce:justify-center">
      <AgentList />
      <AgentList hidden />
    </div>
  </div>
);
