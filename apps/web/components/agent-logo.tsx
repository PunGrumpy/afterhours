import { cn } from "cn";
import type { CSSProperties } from "react";

export const AgentLogo = ({
  id,
  className,
  style,
}: {
  id: string;
  className?: string;
  style?: CSSProperties;
}) => (
  <span
    className={cn("grid shrink-0 place-items-center", className)}
    style={style}
  >
    <span
      className="size-[70%] bg-current [mask-size:contain] [mask-position:center] [mask-repeat:no-repeat]"
      style={{
        WebkitMaskImage: `url(/agents/${id}.svg)`,
        maskImage: `url(/agents/${id}.svg)`,
      }}
    />
  </span>
);
