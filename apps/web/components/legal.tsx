import type { ReactNode } from "react";

import { Prose } from "./prose";
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
      <Prose className="mt-10 gap-10">{children}</Prose>
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
