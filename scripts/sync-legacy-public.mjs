import { copyFile, cp, mkdir, readdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const projectRoot = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const publicDirectory = path.join(projectRoot, "public");
const legacyDirectories = [
  "admin", "assets", "blog", "forgot-password", "login", "member",
  "my-card", "my-passport", "reset-password", "signup", "verify",
];
const rootAssetExtensions = new Set([
  ".css", ".html", ".ico", ".jpeg", ".jpg", ".js", ".mp4", ".png", ".svg", ".webm", ".webp", ".woff", ".woff2",
]);

await mkdir(publicDirectory, { recursive: true });

for (const directory of legacyDirectories) {
  await cp(path.join(projectRoot, directory), path.join(publicDirectory, directory), { recursive: true, force: true });
}

for (const entry of await readdir(projectRoot, { withFileTypes: true })) {
  if (!entry.isFile() || !rootAssetExtensions.has(path.extname(entry.name).toLowerCase())) continue;
  await copyFile(path.join(projectRoot, entry.name), path.join(publicDirectory, entry.name));
}
