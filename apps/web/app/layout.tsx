import type { Metadata, Viewport } from "next";
import { Instrument_Serif } from "next/font/google";

import { site } from "@/components/site";

import "./globals.css";

const instrument = Instrument_Serif({
  style: ["normal", "italic"],
  subsets: ["latin"],
  variable: "--font-instrument",
  weight: "400",
});

export const metadata: Metadata = {
  applicationName: "Afterhours",
  description:
    "A menu bar app that keeps your Mac awake while coding agents work, even with the lid closed. When the last agent finishes, your Mac sleeps again.",
  metadataBase: new URL(site.url),
  title: {
    default: "Afterhours — Keep your Mac awake for your coding agents",
    template: "%s · Afterhours",
  },
};

export const viewport: Viewport = {
  themeColor: "#fcfcfd",
};

const RootLayout = ({ children }: LayoutProps<"/">) => (
  <html lang="en" className={instrument.variable}>
    <body className="min-h-dvh">{children}</body>
  </html>
);

export default RootLayout;
