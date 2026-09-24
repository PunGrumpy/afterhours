import { cn } from "cn";
import { useId } from "react";

export type Mood = "awake" | "drowsy" | "asleep" | "alarmed";

const WISPS: Record<Mood, number> = {
  alarmed: 0,
  asleep: 0,
  awake: 2,
  drowsy: 1,
};

const Arc = ({
  cx,
  cy,
  r,
  width,
}: {
  cx: number;
  cy: number;
  r: number;
  width: number;
}) => {
  const dx = r * Math.cos(0.15 * Math.PI);
  const dy = r * Math.sin(0.15 * Math.PI);
  return (
    <path
      d={`M${cx + dx} ${cy + dy}A${r} ${r} 0 0 1 ${cx - dx} ${cy + dy}`}
      fill="none"
      strokeWidth={width}
    />
  );
};

const Eye = ({
  mood,
  x,
  y,
  w,
  h,
  left,
}: {
  mood: Mood;
  x: number;
  y: number;
  w: number;
  h: number;
  left: boolean;
}) => {
  if (mood === "awake") {
    return (
      <rect
        x={x - w / 2}
        y={y - h / 2}
        width={w}
        height={h}
        rx={w / 2}
        stroke="none"
      />
    );
  }
  if (mood === "drowsy") {
    const dh = h * 0.45;
    return (
      <rect
        x={x - w / 2}
        y={y + h * 0.25 - dh / 2}
        width={w}
        height={dh}
        rx={dh / 2}
        stroke="none"
      />
    );
  }
  if (mood === "asleep") {
    return <Arc cx={x} cy={y - h * 0.1} r={h * 0.4} width={w * 0.6} />;
  }
  const s = h * 0.34;
  const d = left ? 1 : -1;
  return (
    <polyline
      points={`${x - s * d},${y - s} ${x + s * d},${y} ${x - s * d},${y + s}`}
      fill="none"
      strokeWidth={w * 0.6}
    />
  );
};

export const Mug = ({
  mood,
  compact = false,
  steaming = false,
  optical = true,
  className,
}: {
  mood: Mood;
  compact?: boolean;
  steaming?: boolean;
  optical?: boolean;
  className?: string;
}) => {
  const mask = useId();
  const k = compact ? 1.3 : 1;
  const w = 8 * k;
  const h = 13 * k;
  const offset =
    mood === "awake" || mood === "drowsy"
      ? "translate(2.2 -1.5)"
      : "translate(2.1 -13)";

  return (
    <svg
      viewBox="0 0 100 100"
      fill="currentColor"
      aria-hidden="true"
      className={className}
    >
      <g transform={optical ? offset : undefined}>
        <mask
          id={mask}
          maskUnits="userSpaceOnUse"
          x="0"
          y="0"
          width="100"
          height="100"
        >
          <rect width="100" height="100" fill="#fff" />
          <g
            fill="#000"
            stroke="#000"
            strokeLinecap="round"
            strokeLinejoin="round"
          >
            <Eye mood={mood} x={31} y={57} w={w} h={h} left />
            <Eye mood={mood} x={51} y={57} w={w} h={h} left={false} />
            {!compact && mood === "awake" && (
              <Arc cx={41} cy={66} r={5} width={3.5} />
            )}
          </g>
        </mask>
        <rect
          x="12"
          y="36"
          width="58"
          height="54"
          rx="11"
          mask={`url(#${mask})`}
        />
        <ellipse
          cx="72.5"
          cy="60.5"
          rx="12.5"
          ry="13.5"
          fill="none"
          stroke="currentColor"
          strokeWidth="8"
        />
        {[32, 50].map((x, i) => (
          <path
            key={x}
            d={`M${x} 29C${x - 9} 21 ${x + 9} 13 ${x} 5`}
            fill="none"
            stroke="currentColor"
            strokeWidth={compact ? 7 : 6}
            strokeLinecap="round"
            className={cn("transition-opacity duration-200 ease-out", {
              steam: steaming,
            })}
            style={{
              animationDelay: `${i * -1.2}s`,
              opacity: i < WISPS[mood] ? 1 : 0,
            }}
          />
        ))}
      </g>
    </svg>
  );
};
