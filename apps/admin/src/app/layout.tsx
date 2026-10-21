import type { Metadata, Viewport } from "next";
import { IBM_Plex_Sans_Arabic } from "next/font/google";
import { cookies } from "next/headers";
import type { ReactNode } from "react";

import { AppProviders } from "@/components/providers/AppProviders";
import { dirFor, getDictionary, LOCALE_COOKIE, resolveLocale } from "@/lib/i18n";

import "./globals.css";

// One family covers Arabic and Latin; self-hosted by next/font (no runtime request to Google).
const plex = IBM_Plex_Sans_Arabic({
  subsets: ["arabic", "latin"],
  weight: ["400", "500", "600", "700"],
  display: "swap",
  variable: "--font-plex",
});

export async function generateMetadata(): Promise<Metadata> {
  const locale = resolveLocale((await cookies()).get(LOCALE_COOKIE)?.value);
  const t = getDictionary(locale);
  return { title: { default: t.meta.title, template: `%s · RideFlow` }, description: t.meta.tagline, robots: { index: false } };
}

export const viewport: Viewport = { themeColor: "#10243A", width: "device-width", initialScale: 1 };

export default async function RootLayout({ children }: { children: ReactNode }) {
  const locale = resolveLocale((await cookies()).get(LOCALE_COOKIE)?.value);
  return (
    <html lang={locale} dir={dirFor(locale)} className={plex.variable}>
      <body className="min-h-dvh antialiased">
        <AppProviders locale={locale}>{children}</AppProviders>
      </body>
    </html>
  );
}
