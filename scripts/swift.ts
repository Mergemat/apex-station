// Runs SwiftPM with the flags Xcode would normally supply, so the project builds and
// tests with only Apple's Command Line Tools. With Xcode (as on CI) they aren't needed.
import { existsSync } from "node:fs";

const plugins = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing";
export const swiftFlags = existsSync(plugins) ? ["-Xswiftc", "-plugin-path", "-Xswiftc", plugins] : [];

export async function swift(args: string[]) {
  const proc = Bun.spawn(["swift", ...args, ...swiftFlags], { stdout: "inherit", stderr: "inherit" });
  const code = await proc.exited;
  if (code !== 0) process.exit(code);
}

if (import.meta.main) await swift(Bun.argv.slice(2));
