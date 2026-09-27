import type { VariantProps } from "class-variance-authority";
import { cn } from "cn";

import { AppleIcon, GitHubIcon } from "./icons";
import { pill, pillIcon } from "./pill";
import { site } from "./site";

export const DownloadButton = ({ size }: VariantProps<typeof pill>) => (
  <a href={site.download} className={pill({ intent: "primary", size })}>
    <AppleIcon className={cn("-mt-0.5", pillIcon({ size }))} />
    Download for Mac
  </a>
);

export const GitHubButton = ({ size }: VariantProps<typeof pill>) => (
  <a href={site.repo} className={pill({ intent: "secondary", size })}>
    <GitHubIcon className={pillIcon({ size })} />
    GitHub
  </a>
);
