import type { VariantProps } from "class-variance-authority";
import { cn } from "cn";
import Link from "next/link";
import type { CSSProperties, ReactNode } from "react";

import { AgentMarquee } from "@/components/agent-marquee";
import { Demo } from "@/components/demo";
import { Features } from "@/components/features";
import { AppleIcon, GitHubIcon } from "@/components/icons";
import { Logo } from "@/components/logo";
import { Mug } from "@/components/mug";
import { pill, pillIcon } from "@/components/pill";
import { site } from "@/components/site";

const riseDelay = (index: number): CSSProperties => ({
  animationDelay: `${index * 60}ms`,
});

const DownloadButton = ({ size }: VariantProps<typeof pill>) => (
  <a href={site.download} className={pill({ intent: "primary", size })}>
    <AppleIcon className={cn("-mt-0.5", pillIcon({ size }))} />
    Download for Mac
  </a>
);

const GitHubButton = ({ size }: VariantProps<typeof pill>) => (
  <a href={site.repo} className={pill({ intent: "secondary", size })}>
    <GitHubIcon className={pillIcon({ size })} />
    GitHub
  </a>
);

const FooterLink = ({
  href,
  children,
}: {
  href: string;
  children: ReactNode;
}) => (
  <a href={href} className="text-ink/60 hover:text-ink">
    {children}
  </a>
);

const Page = () => (
  <div className="overflow-x-clip">
    <header className="mx-auto flex max-w-[1216px] items-center justify-between px-6 py-4">
      <Link href="/" aria-label="Afterhours home" className="press">
        <Logo className="h-7 w-auto" />
      </Link>
      <nav className="flex items-center gap-2">
        <a
          href="#details"
          className="text-ink/70 hover:text-ink hidden px-3 text-[14px] sm:block"
        >
          Details
        </a>
        <span className="hidden sm:block">
          <GitHubButton size="small" />
        </span>
        <DownloadButton size="small" />
      </nav>
    </header>

    <main>
      <section className="mx-auto flex max-w-[1216px] flex-col items-center px-6 pt-16 text-center md:pt-24">
        <a
          href={`${site.repo}/releases`}
          className="rise bg-surface text-ink/80 hover:text-ink inline-flex h-9 items-center gap-2.5 rounded-full pr-3.5 pl-1.5 text-[13px] font-medium"
        >
          <span className="bg-ink text-canvas rounded-full px-2 py-0.5 text-[12px] font-semibold tabular-nums">
            v{site.version}
          </span>
          Lid-closed mode for coding agents
          <span aria-hidden="true" className="text-ink/40">
            ›
          </span>
        </a>
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
        <p className="rise text-ink/45 mt-4 text-[13px]" style={riseDelay(3)}>
          For macOS 14 or later
        </p>

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
        <div className="mt-9">
          <DownloadButton />
        </div>
      </section>
    </main>

    <footer className="border-ink/[0.08] mx-auto mt-36 max-w-[1216px] border-t px-6 pt-10 pb-12">
      <div className="flex flex-col gap-8 md:flex-row md:justify-between">
        <div>
          <Logo className="h-6 w-auto" />
          <p className="text-ink/50 mt-3 text-[13px]">
            Brewed late at night by{" "}
            <a
              href={site.author.url}
              className="text-ink/80 hover:text-ink font-medium"
            >
              {site.author.name}
            </a>
            .
          </p>
        </div>
        <nav
          aria-label="Footer"
          className="grid grid-cols-2 gap-x-16 gap-y-2 text-[14px]"
        >
          <p className="text-ink font-medium">Product</p>
          <p className="text-ink font-medium">Source</p>
          <FooterLink href="#details">Details</FooterLink>
          <FooterLink href={site.repo}>GitHub</FooterLink>
          <FooterLink href={site.download}>Download</FooterLink>
          <FooterLink href={`${site.repo}/releases`}>Releases</FooterLink>
        </nav>
      </div>
      <p className="text-ink/40 mt-10 text-[12px]">
        Agent logos are trademarks of their owners.
      </p>
    </footer>
  </div>
);

export default Page;
