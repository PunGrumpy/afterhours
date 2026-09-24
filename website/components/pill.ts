import { cva } from "class-variance-authority";

export const pill = cva(
  "press inline-flex items-center gap-2 rounded-full font-medium",
  {
    defaultVariants: { intent: "primary", size: "large" },
    variants: {
      intent: {
        primary: "bg-ink text-canvas hover:bg-[#15254a]",
        secondary: "bg-surface hover:bg-[#eceef2]",
      },
      size: {
        large: "h-11 pr-5 pl-4 text-[15px]",
        medium: "h-10 px-5 text-[14px]",
        small: "h-[34px] pr-3.5 pl-3 text-[14px]",
      },
    },
  }
);

export const pillIcon = cva("", {
  defaultVariants: { size: "large" },
  variants: {
    size: {
      large: "size-4",
      medium: "size-4",
      small: "size-3.5",
    },
  },
});
