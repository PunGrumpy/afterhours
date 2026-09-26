"use client";

import { cn } from "cn";
import { useEffect, useRef, useState } from "react";

import { CheckIcon, CopyIcon } from "./icons";
import { site } from "./site";

export const BrewCommand = ({ className }: { className?: string }) => {
  const [copied, setCopied] = useState(false);
  const command = useRef<HTMLSpanElement>(null);

  useEffect(() => {
    if (!copied) {
      return;
    }
    const timer = setTimeout(() => setCopied(false), 1600);
    return () => clearTimeout(timer);
  }, [copied]);

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(site.brew);
      setCopied(true);
    } catch {
      if (command.current) {
        window.getSelection()?.selectAllChildren(command.current);
      }
    }
  };

  return (
    <div className={cn("flex max-w-full flex-col items-center", className)}>
      <button
        type="button"
        onClick={copy}
        aria-label="Copy the Homebrew install command"
        className="press bg-surface flex h-10 max-w-full items-center gap-3 rounded-full pr-1.5 pl-4 font-mono text-[13px] hover:bg-[#eceef2]"
      >
        <span className="flex min-w-0 [scrollbar-width:none] items-center gap-2 overflow-x-auto max-sm:[mask-image:linear-gradient(to_right,black_85%,transparent)]">
          <span aria-hidden="true" className="text-ink/35 select-none">
            $
          </span>
          <span ref={command} className="text-ink/80 whitespace-nowrap">
            {site.brew}
          </span>
        </span>
        <span className="text-ink/55 grid size-7 shrink-0 place-items-center rounded-full bg-white shadow-[0_0_0_1px_rgb(8_21_46/0.06)]">
          {copied ? (
            <CheckIcon key="check" className="blur-in text-ink size-3.5" />
          ) : (
            <CopyIcon key="copy" className="blur-in size-3.5" />
          )}
        </span>
      </button>
      <span aria-live="polite" className="sr-only">
        {copied ? "Copied the install command" : ""}
      </span>
    </div>
  );
};
