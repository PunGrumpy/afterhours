import type { Metadata } from "next";
import Link from "next/link";

import { SiteFooter } from "@/components/site-footer";
import { SiteHeader } from "@/components/site-header";
import { getReleases, oneLine } from "@/lib/changelog";
import type { Release } from "@/lib/changelog";

export const metadata: Metadata = {
  alternates: { canonical: "/changelog" },
  description:
    "Every Afterhours release, newest first, with what changed in each one.",
  title: "Changelog",
};

const monthDay = new Intl.DateTimeFormat("en-US", {
  day: "numeric",
  month: "long",
  timeZone: "UTC",
});

const byYear = (releases: Release[]) => {
  const groups: { year: string; releases: Release[] }[] = [];
  for (const release of releases) {
    const year = release.date
      ? String(new Date(release.date).getUTCFullYear())
      : "";
    const last = groups.at(-1);
    if (last?.year === year) {
      last.releases.push(release);
    } else {
      groups.push({ releases: [release], year });
    }
  }
  return groups;
};

const Page = async () => {
  const releases = await getReleases();

  return (
    <div className="overflow-x-clip">
      <SiteHeader />
      <main className="mx-auto max-w-[864px] px-6 pt-16 md:pt-24">
        <h1 className="font-serif text-[clamp(2.5rem,6vw,3.5rem)] leading-[1.05] tracking-[-0.02em]">
          Changelog
        </h1>
        <p className="text-ink/65 mt-4 max-w-[34rem] text-[17px] leading-relaxed">
          Every Afterhours release, newest first, with the same notes as its
          GitHub release.
        </p>
        <div className="border-ink/[0.08] mt-12 border-t">
          {byYear(releases).map((group) => (
            <section
              key={group.year || "undated"}
              className="border-ink/[0.08] grid border-b md:grid-cols-[96px_minmax(0,1fr)] md:gap-x-6"
            >
              <h2 className="text-ink/45 pt-4 text-[14px] tabular-nums max-md:pb-1">
                {group.year}
              </h2>
              <ol>
                {group.releases.map((release) => (
                  <li
                    key={release.version}
                    className="border-ink/[0.08] border-t first:border-t-0"
                  >
                    <Link
                      href={`/changelog/${release.slug}`}
                      className="group flex items-center gap-3 py-3.5"
                    >
                      <span className="text-ink shrink-0 text-[15px] font-medium tabular-nums">
                        v{release.version}
                      </span>
                      <span className="text-ink/50 group-hover:text-ink/75 min-w-0 flex-1 truncate text-[14px] max-sm:hidden">
                        {oneLine(release)}
                      </span>
                      <span className="bg-ink/[0.06] text-ink/60 ml-auto shrink-0 rounded-full px-2 py-0.5 text-[12px]">
                        {release.tag}
                      </span>
                      {release.date && (
                        <time
                          dateTime={release.date}
                          className="text-ink/45 w-28 shrink-0 text-right text-[13px] tabular-nums"
                        >
                          {monthDay.format(new Date(release.date))}
                        </time>
                      )}
                    </Link>
                  </li>
                ))}
              </ol>
            </section>
          ))}
        </div>
      </main>
      <SiteFooter className="mt-32" />
    </div>
  );
};

export default Page;
