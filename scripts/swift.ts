// Runs SwiftPM with the flags Xcode would normally supply, so the project builds and
// tests with only Apple's Command Line Tools.
const CLT = "/Library/Developer/CommandLineTools";
export const swiftFlags = [
  "-Xswiftc", "-plugin-path", "-Xswiftc", `${CLT}/usr/lib/swift/host/plugins/testing`,
];

export async function swift(args: string[]) {
  const proc = Bun.spawn(["swift", ...args, ...swiftFlags], { stdout: "inherit", stderr: "inherit" });
  const code = await proc.exited;
  if (code !== 0) process.exit(code);
}

if (import.meta.main) await swift(Bun.argv.slice(2));
