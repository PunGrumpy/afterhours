import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";

import { ChevronIcon, GitHubIcon } from "@/components/icons";
import { renderInline } from "@/components/inline-markdown";
import { pill, pillIcon } from "@/components/pill";
import { Prose } from "@/components/prose";
import { SiteFooter } from "@/components/site-footer";
import { SiteHeader } from "@/components/site-header";
import { getReleases, oneLine } from "@/lib/changelog";

export const dynamicParams = false;

export const generateStaticParams = async () => {
  const releases = await getReleases();
  return releases.map((release) => ({ version: release.slug }));
};

export const generateMetadata = async ({
  params,
}: PageProps<"/changelog/[version]">): Promise<Metadata> => {
  const [{ version }, releases] = await Promise.all([params, getReleases()]);
  const release = releases.find((item) => item.slug === version);
  return release
    ? {
        alternates: { canonical: `/changelog/${release.slug}` },
        description: oneLine(release),
        title: { absolute: `Afterhours ${release.version}` },
      }
    : {};
};

const fullDate = new Intl.DateTimeFormat("en-US", {
  day: "numeric",
  month: "long",
  timeZone: "UTC",
  year: "numeric",
});

const Page = async ({ params }: PageProps<"/changelog/[version]">) => {
  const [{ version }, releases] = await Promise.all([params, getReleases()]);
  const index = releases.findIndex((item) => item.slug === version);
  const release = releases[index];
  if (!release) {
    notFound();
  }
  const newer = releases[index - 1];
  const older = releases[index + 1];

  return (
    <div className="overflow-x-clip">
      <SiteHeader />
      <main className="mx-auto max-w-[680px] px-6 pt-16 md:pt-24">
        <Link
          href="/changelog"
          className="text-ink/55 hover:text-ink -ml-1 inline-flex items-center gap-1 text-[13px] font-medium"
        >
          <ChevronIcon className="size-3.5 rotate-180" />
          Changelog
        </Link>
        <div className="mt-6 flex items-center gap-3 text-[13px]">
          {release.date && (
            <time dateTime={release.date} className="text-ink/50 tabular-nums">
              {fullDate.format(new Date(release.date))}
            </time>
          )}
          <span className="bg-ink/[0.06] text-ink/60 rounded-full px-2 py-0.5 text-[12px]">
            {release.tag}
          </span>
        </div>
        <h1 className="mt-2 font-serif text-[clamp(2.5rem,6vw,3.5rem)] leading-[1.05] tracking-[-0.02em]">
          Afterhours {release.version}
        </h1>
        <Prose className="mt-8 gap-8">
          {release.summary.map((paragraph) => (
            <p key={paragraph}>{renderInline(paragraph)}</p>
          ))}
          {release.sections.map((section) => (
            <section key={section.title} className="flex flex-col gap-3">
              <h2 className="text-ink text-[17px] font-semibold tracking-[-0.01em]">
                {section.title}
              </h2>
              <ul>
                {section.items.map((item) => (
                  <li key={item}>{renderInline(item)}</li>
                ))}
              </ul>
            </section>
          ))}
        </Prose>
        <div className="mt-10">
          <a
            href={release.url}
            className={pill({ intent: "secondary", size: "medium" })}
          >
            <GitHubIcon className={pillIcon({ size: "medium" })} />
            Download {release.version} from GitHub
          </a>
        </div>
        <nav
          aria-label="Other releases"
          className="border-ink/[0.08] mt-16 grid grid-cols-2 gap-4 border-t pt-6 text-[14px]"
        >
          {older ? (
            <Link
              href={`/changelog/${older.slug}`}
              className="text-ink/55 hover:text-ink flex flex-col gap-0.5"
            >
              <span className="text-ink/40 text-[12px]">Older</span>
              <span className="text-ink font-medium">v{older.version}</span>
            </Link>
          ) : (
            <span />
          )}
          {newer && (
            <Link
              href={`/changelog/${newer.slug}`}
              className="text-ink/55 hover:text-ink flex flex-col items-end gap-0.5 text-right"
            >
              <span className="text-ink/40 text-[12px]">Newer</span>
              <span className="text-ink font-medium">v{newer.version}</span>
            </Link>
          )}
        </nav>
      </main>
      <SiteFooter className="mt-32" />
    </div>
  );
};

export default Page;
