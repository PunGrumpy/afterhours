import type { Metadata } from "next";

import { LegalPage, LegalSection } from "@/components/legal";
import { site } from "@/components/site";

export const metadata: Metadata = {
  description:
    "The terms for using the Afterhours app and this website, alongside the MIT License that covers the code.",
  title: "Terms of Service",
};

const Page = () => (
  <LegalPage title="Terms of Service" updated="September 27, 2026">
    <p>
      These terms cover the Afterhours app and this website. The source code is
      released under the{" "}
      <a href={`${site.repo}/blob/main/LICENSE`}>MIT License</a>, which governs
      copying, changing, and sharing it.
    </p>

    <LegalSection title="Using Afterhours">
      <p>
        Afterhours is free. You can use it on as many Macs as you like, for
        personal or commercial work.
      </p>
    </LegalSection>

    <LegalSection title="No warranty">
      <p>
        Afterhours is provided as is, without warranty of any kind, as the MIT
        License says. It can have bugs. It might not keep your Mac awake, or let
        it sleep, exactly when you expect.
      </p>
    </LegalSection>

    <LegalSection title="Your Mac, your call">
      <p>
        A Mac kept awake with its lid closed uses battery and makes heat.
        Afterhours stops at a battery cutoff, in Low Power Mode, and at a
        critical temperature, but you decide where your Mac is while it runs.
        Don&apos;t leave a working Mac closed in a bag or on a bed.
      </p>
      <p>
        Lid-closed mode on battery asks for an admin password to add a sudoers
        rule. Only install it on a Mac you&apos;re allowed to administer.
      </p>
    </LegalSection>

    <LegalSection title="Other services">
      <p>
        The Limits section reads your usage from Anthropic, OpenAI, GitHub,
        Cursor, OpenCode, and xAI with the logins their tools already keep on
        your Mac, through the endpoints those tools use. These aren&apos;t
        public APIs, and they can change or stop working. Your use of each
        service stays under that service&apos;s own terms.
      </p>
      <p>
        Afterhours isn&apos;t made, endorsed, or supported by these companies,
        or by the makers of the agents it detects.
      </p>
    </LegalSection>

    <LegalSection title="Liability">
      <p>
        As far as the law allows, the author isn&apos;t liable for damage, lost
        data, or costs that come from using Afterhours, including lost work from
        a Mac that went to sleep.
      </p>
    </LegalSection>

    <LegalSection title="Changes and questions">
      <p>
        If these terms change, this page shows a new date, and the change is in
        the site&apos;s history on <a href={site.repo}>GitHub</a>. Ask questions
        in <a href={`${site.repo}/issues`}>GitHub issues</a>.
      </p>
    </LegalSection>
  </LegalPage>
);

export default Page;
