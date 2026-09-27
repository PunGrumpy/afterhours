import type { Metadata } from "next";

import { LegalPage, LegalSection } from "@/components/legal";
import { site } from "@/components/site";

export const metadata: Metadata = {
  description:
    "Licenses for Afterhours and the fonts and icons it uses, and the trademarks it names.",
  title: "Licenses and Trademarks",
};

const Page = () => (
  <LegalPage title="Licenses and Trademarks" updated="September 27, 2026">
    <LegalSection title="Afterhours">
      <p>
        Copyright © 2026 {site.author.name}. The app, its hook, and this website
        are released under the{" "}
        <a href={`${site.repo}/blob/main/LICENSE`}>MIT License</a>. The app
        contains no third-party code.
      </p>
    </LegalSection>

    <LegalSection title="Agent logos">
      <p>
        The agent logos come from{" "}
        <a href="https://github.com/lobehub/lobe-icons">LobeHub Icons</a>,
        released under the MIT License, and from each vendor&apos;s own site.
        They appear only to show which agents Afterhours works with.
      </p>
    </LegalSection>

    <LegalSection title="Trademarks">
      <p>
        The names and logos of agents and services belong to their owners.
        Apple, Mac, and macOS are trademarks of Apple Inc. Naming them here
        doesn&apos;t mean their owners endorse Afterhours.
      </p>
    </LegalSection>

    <LegalSection title="Fonts and open source">
      <p>
        Headings use{" "}
        <a href="https://fonts.google.com/specimen/Instrument+Serif">
          Instrument Serif
        </a>{" "}
        under the SIL Open Font License 1.1. This site is built with Next.js,
        React, Tailwind CSS, cn, and class-variance-authority, all under the MIT
        License.
      </p>
    </LegalSection>
  </LegalPage>
);

export default Page;
