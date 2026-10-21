import { cookies } from "next/headers";
import { redirect } from "next/navigation";

export default async function Home() {
  const jar = await cookies();
  const scope = jar.has("rf_rt") ? jar.get("rf_scope")?.value : undefined;
  redirect(scope === "platform" ? "/platform" : scope === "tenant" ? "/operator" : "/login");
}
