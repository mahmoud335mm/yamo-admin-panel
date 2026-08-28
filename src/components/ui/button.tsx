import * as React from "react";
import { Slot } from "@radix-ui/react-slot";
import { cva, type VariantProps } from "class-variance-authority";

import { cn } from "@/lib/utils";

const buttonVariants = cva(
  "inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-xl text-sm font-semibold cursor-pointer transition-all duration-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-violet-500/60 disabled:pointer-events-none disabled:opacity-50 disabled:cursor-not-allowed active:scale-[0.97] [&_svg]:pointer-events-none [&_svg]:size-4 [&_svg]:shrink-0",
  {
    variants: {
      variant: {
        default: "bg-gradient-to-r from-violet-600 to-orange-500 text-white shadow-lg shadow-violet-500/20 hover:-translate-y-0.5 hover:shadow-xl hover:shadow-orange-500/35",
        destructive: "bg-gradient-to-r from-red-600 to-rose-500 text-white shadow-lg shadow-red-500/20 hover:-translate-y-0.5 hover:shadow-xl hover:shadow-red-500/35",
        outline:
          "border border-violet-400/25 bg-background shadow-sm hover:-translate-y-0.5 hover:border-violet-500/50 hover:bg-violet-500/10 hover:text-violet-600 hover:shadow-lg hover:shadow-violet-500/20",
        secondary: "bg-secondary text-secondary-foreground shadow-sm hover:-translate-y-0.5 hover:shadow-lg hover:shadow-violet-500/20",
        ghost: "hover:bg-violet-500/10 hover:text-violet-600 hover:shadow-md hover:shadow-violet-500/15",
        link: "text-primary underline-offset-4 hover:underline",
      },
      size: {
        default: "h-9 px-4 py-2",
        sm: "h-8 rounded-md px-3 text-xs",
        lg: "h-10 rounded-md px-8",
        icon: "h-9 w-9",
      },
    },
    defaultVariants: {
      variant: "default",
      size: "default",
    },
  },
);

export interface ButtonProps
  extends React.ButtonHTMLAttributes<HTMLButtonElement>, VariantProps<typeof buttonVariants> {
  asChild?: boolean;
}

const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(
  ({ className, variant, size, asChild = false, ...props }, ref) => {
    const Comp = asChild ? Slot : "button";
    return (
      <Comp className={cn(buttonVariants({ variant, size, className }))} ref={ref} {...props} />
    );
  },
);
Button.displayName = "Button";

export { Button, buttonVariants };
