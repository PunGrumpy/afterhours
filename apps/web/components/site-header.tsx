import Link from "next/link";

import { DownloadButton, GitHubButton } from "./buttons";
import { Logo } from "./logo";

export const SiteHeader = () => (
  <header className="mx-auto flex max-w-[1216px] items-center justify-between px-6 py-4">
    <Link href="/" aria-label="Afterhours home" className="press">
      <Logo className="h-7 w-auto" />
    </Link>
    <nav className="flex items-center gap-2">
      <Link
        href="/changelog"
        className="text-ink/70 hover:text-ink hidden px-3 text-[14px] sm:block"
      >
        Changelog
      </Link>
      <Link
        href="/#details"
        className="text-ink/70 hover:text-ink hidden px-3 text-[14px] sm:block"
      >
        Details
      </Link>
      <span className="hidden sm:block">
        <GitHubButton size="small" />
      </span>
      <DownloadButton size="small" />
    </nav>
  </header>
);
