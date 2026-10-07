import { cn } from "cn";
import Link from "next/link";
import type { ReactNode } from "react";

import { Logo } from "./logo";
import { site } from "./site";

const FooterLink = ({
  href,
  children,
}: {
  href: string;
  children: ReactNode;
}) => (
  <Link href={href} className="text-ink/60 hover:text-ink">
    {children}
  </Link>
);

const FooterColumn = ({
  title,
  children,
}: {
  title: string;
  children: ReactNode;
}) => (
  <div className="flex flex-col gap-2">
    <p className="text-ink font-medium">{title}</p>
    {children}
  </div>
);

export const SiteFooter = ({ className }: { className?: string }) => (
  <footer
    className={cn(
      "border-ink/[0.08] mx-auto max-w-[1216px] border-t px-6 pt-10 pb-12",
      className
    )}
  >
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
        className="grid grid-cols-2 gap-x-16 gap-y-8 text-[14px] sm:grid-cols-3"
      >
        <FooterColumn title="Product">
          <FooterLink href="/#details">Details</FooterLink>
          <FooterLink href="/changelog">Changelog</FooterLink>
          <FooterLink href={site.download}>Download</FooterLink>
        </FooterColumn>
        <FooterColumn title="Source">
          <FooterLink href={site.repo}>GitHub</FooterLink>
          <FooterLink href={site.releases}>Releases</FooterLink>
        </FooterColumn>
        <FooterColumn title="Legal">
          <FooterLink href="/privacy">Privacy</FooterLink>
          <FooterLink href="/terms">Terms</FooterLink>
          <FooterLink href="/legal">Licenses</FooterLink>
        </FooterColumn>
      </nav>
    </div>
    <p className="text-ink/40 mt-10 text-[12px]">
      Agent logos are trademarks of their owners.
    </p>
  </footer>
);
