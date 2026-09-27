import Link from "next/link";
import type { CSSProperties } from "react";

import { AgentMarquee } from "@/components/agent-marquee";
import { BrewCommand } from "@/components/brew-command";
import { DownloadButton, GitHubButton } from "@/components/buttons";
import { Demo } from "@/components/demo";
import { Features } from "@/components/features";
import { Mug } from "@/components/mug";
import { site } from "@/components/site";
import { SiteFooter } from "@/components/site-footer";
import { SiteHeader } from "@/components/site-header";

const riseDelay = (index: number): CSSProperties => ({
  animationDelay: `${index * 60}ms`,
});

const Page = () => (
  <div className="overflow-x-clip">
    <SiteHeader />

    <main>
      <section className="mx-auto flex max-w-[1216px] flex-col items-center px-6 pt-16 text-center md:pt-24">
        <Link
          href="/changelog"
          className="rise bg-surface text-ink/80 hover:text-ink inline-flex h-9 items-center gap-2.5 rounded-full pr-3.5 pl-1.5 text-[13px] font-medium"
        >
          <span className="bg-ink text-canvas rounded-full px-2 py-0.5 text-[12px] font-semibold tabular-nums">
            v{site.version}
          </span>
          Lid-closed mode for coding agents
          <span aria-hidden="true" className="text-ink/40">
            ›
          </span>
        </Link>
        <h1
          className="rise mt-7 font-serif text-[clamp(3rem,8vw,5.25rem)] leading-[1.02] tracking-[-0.03em]"
          style={riseDelay(1)}
        >
          Close the lid.
          <br />
          Your agents keep <em className="italic">working.</em>
        </h1>
        <p
          className="rise text-ink/65 mt-6 max-w-[31rem] text-[17px] leading-relaxed"
          style={riseDelay(2)}
        >
          Afterhours keeps your Mac awake while coding agents work, then lets it
          sleep when the last one finishes.
        </p>
        <div
          className="rise mt-8 flex flex-wrap justify-center gap-2.5"
          style={riseDelay(3)}
        >
          <DownloadButton />
          <GitHubButton />
        </div>
        <div
          className="rise mt-3 flex max-w-full flex-col items-center gap-3"
          style={riseDelay(3)}
        >
          <BrewCommand />
          <p className="text-ink/45 text-[13px]">For macOS 14 or later</p>
        </div>

        <div className="rise mt-14 w-full" style={riseDelay(4)}>
          <AgentMarquee />
        </div>
      </section>

      <section
        aria-label="Try Afterhours"
        className="rise mx-auto mt-6 max-w-[1264px] px-3 md:px-6"
        style={riseDelay(5)}
      >
        <Demo />
      </section>

      <section
        id="details"
        className="mx-auto mt-32 max-w-[1216px] scroll-mt-8 px-6"
      >
        <p className="text-ink/50 text-[13px] font-medium">
          The everyday details
        </p>
        <h2 className="mt-2 max-w-[36rem] text-[clamp(1.5rem,3vw,1.75rem)] leading-tight font-semibold tracking-[-0.02em]">
          Stays up late.{" "}
          <span className="text-ink/45">
            So you can go to bed while agents finish the job.
          </span>
        </h2>
        <div className="mt-10">
          <Features />
        </div>
      </section>

      <section className="mx-auto mt-36 flex max-w-[1216px] flex-col items-center px-6 text-center">
        <Mug mood="awake" steaming className="text-ink size-16" />
        <h2 className="mt-6 font-serif text-[clamp(2.75rem,6vw,4.5rem)] leading-[1.02] tracking-[-0.03em]">
          Go to bed.
          <br />
          <em className="italic">Let them ship.</em>
        </h2>
        <div className="mt-9 flex max-w-full flex-col items-center gap-3">
          <DownloadButton />
          <BrewCommand />
        </div>
      </section>
    </main>

    <SiteFooter className="mt-36" />
  </div>
);

export default Page;
