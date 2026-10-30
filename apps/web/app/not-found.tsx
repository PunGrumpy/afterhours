import type { Metadata } from "next";
import Link from "next/link";

import { pill } from "@/components/pill";
import { SiteFooter } from "@/components/site-footer";
import { SiteHeader } from "@/components/site-header";

export const metadata: Metadata = {
  title: "Page not found",
};

const NotFound = () => (
  <div className="overflow-x-clip">
    <SiteHeader />
    <main className="mx-auto max-w-[680px] px-6 pt-16 md:pt-24">
      <h1 className="font-serif text-[clamp(2.5rem,6vw,3.5rem)] leading-[1.05] tracking-[-0.02em]">
        Page not found
      </h1>
      <p className="text-ink/60 mt-6 text-[17px] leading-7">
        There’s nothing at this address. The page may have moved, or the link is
        out of date.
      </p>
      <div className="mt-10 flex flex-wrap gap-3">
        <Link href="/" className={pill({ intent: "primary", size: "medium" })}>
          Go to the home page
        </Link>
        <Link
          href="/changelog"
          className={pill({ intent: "secondary", size: "medium" })}
        >
          See the changelog
        </Link>
      </div>
    </main>
    <SiteFooter className="mt-32" />
  </div>
);

export default NotFound;
