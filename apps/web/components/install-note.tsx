import { cn } from "cn";

export const InstallNote = ({ className }: { className?: string }) => (
  <p
    className={cn(
      "text-ink/45 max-w-[27rem] text-[13px] leading-relaxed text-balance",
      className
    )}
  >
    For macOS 14 or later. Afterhours isn&apos;t notarized yet, so the first
    time you open it, go to{" "}
    <span className="text-ink/70">System Settings › Privacy & Security</span>{" "}
    and click <span className="text-ink/70">Open Anyway</span>.
  </p>
);
