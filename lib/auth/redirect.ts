/** Accept only local paths, including after the browser normalizes the URL. */
export function safeNextPath(path: string) {
  if (!path.startsWith("/") || path.startsWith("//") || path.includes("\\") || [...path].some((char) => char.charCodeAt(0) <= 32 || char.charCodeAt(0) === 127)) return "";
  try {
    const base = "https://local.invalid";
    const url = new URL(path, base);
    return url.origin === base ? `${url.pathname}${url.search}${url.hash}` : "";
  } catch { return ""; }
}
