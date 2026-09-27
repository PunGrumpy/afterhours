import type { ReactNode } from "react";

import { SiteFooter } from "./site-footer";
import { SiteHeader } from "./site-header";

export const LegalPage = ({
  title,
  updated,
  children,
}: {
  title: string;
  updated: string;
  children: ReactNode;
}) => (
  <div className="overflow-x-clip">
    <SiteHeader />
    <main className="mx-auto max-w-[680px] px-6 pt-16 md:pt-24">
      <p className="text-ink/50 text-[13px] font-medium">
        Last updated {updated}
      </p>
      <h1 className="mt-2 font-serif text-[clamp(2.5rem,6vw,3.5rem)] leading-[1.05] tracking-[-0.02em]">
        {title}
      </h1>
      <div className="text-ink/70 [&_a]:text-ink [&_a]:decoration-ink/25 [&_a:hover]:decoration-ink/60 [&_code]:bg-surface [&_strong]:text-ink mt-10 flex flex-col gap-10 text-[15px] leading-relaxed [&_a]:underline [&_a]:underline-offset-2 [&_code]:rounded-[5px] [&_code]:px-1 [&_code]:py-0.5 [&_code]:font-mono [&_code]:text-[13px] [&_li]:pl-1 [&_strong]:font-medium [&_ul]:flex [&_ul]:list-disc [&_ul]:flex-col [&_ul]:gap-2 [&_ul]:pl-5">
        {children}
      </div>
    </main>
    <SiteFooter className="mt-32" />
  </div>
);

export const LegalSection = ({
  title,
  children,
}: {
  title: string;
  children: ReactNode;
}) => (
  <section className="flex flex-col gap-3">
    <h2 className="text-ink text-[17px] font-semibold tracking-[-0.01em]">
      {title}
    </h2>
    {children}
  </section>
);
