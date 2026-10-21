import { NextResponse, type NextRequest } from "next/server";

/**
 * Route protection (UX only — the API enforces every permission). Operator and platform portals are
 * separate sessions: a platform session cannot open operator pages and vice versa.
 */
export function proxy(req: NextRequest) {
  const { pathname, search } = req.nextUrl;
  const hasSession = req.cookies.has("rf_rt");
  const scope = req.cookies.get("rf_scope")?.value;

  const redirect = (to: string) => {
    const url = req.nextUrl.clone();
    url.pathname = to;
    url.search = to.endsWith("login") ? `?next=${encodeURIComponent(pathname + search)}` : "";
    return NextResponse.redirect(url);
  };

  if (pathname.startsWith("/operator")) {
    if (!hasSession) return redirect("/login");
    if (scope !== "tenant") return redirect(scope === "platform" ? "/platform" : "/login");
  } else if (pathname.startsWith("/platform") && !pathname.startsWith("/platform/login")) {
    if (!hasSession) return redirect("/platform/login");
    if (scope !== "platform") return redirect(scope === "tenant" ? "/operator" : "/platform/login");
  }
  return NextResponse.next();
}

export const config = { matcher: ["/operator/:path*", "/platform/:path*"] };
