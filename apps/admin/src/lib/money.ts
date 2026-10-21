/** Converts a user-typed decimal amount ("5000", "12.5") into integer minor units without floating point. */
export function toMinor(input: string, minorUnits: number): number | null {
  const s = input.trim().replace(/,/g, "");
  if (!/^\d+(\.\d+)?$/.test(s)) return null;
  const [whole = "0", frac = ""] = s.split(".");
  if (frac.length > minorUnits) return null;
  return Number(whole) * 10 ** minorUnits + Number(frac.padEnd(minorUnits, "0") || "0");
}

export function fromMinor(minor: number, minorUnits: number): string {
  const neg = minor < 0;
  const abs = Math.abs(minor);
  const whole = Math.floor(abs / 10 ** minorUnits);
  const frac = abs % 10 ** minorUnits;
  const text = minorUnits && frac ? `${whole}.${String(frac).padStart(minorUnits, "0").replace(/0+$/, "")}` : String(whole);
  return neg ? `-${text}` : text;
}
