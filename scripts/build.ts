// Builds "Apex Station.app" with only Apple's Command Line Tools.
//   bun scripts/build.ts            → build/Apex Station.app
//   bun scripts/build.ts --install  → also installs to /Applications and relaunches it
//   bun scripts/build.ts --release  → universal (Apple Silicon + Intel) build, zipped for download
import { $ } from "bun";
import { swift } from "./swift";

const root = `${import.meta.dir}/..`;
const app = `${root}/build/Apex Station.app`;
const version = (await Bun.file(`${root}/VERSION`).text()).trim();

const release = Bun.argv.includes("--release");
const arch = release ? ["--arch", "arm64", "--arch", "x86_64"] : [];
await swift(["build", "-c", "release", "--package-path", root, ...arch]);
const binDir = (await $`swift build -c release --package-path ${root} ${arch} --show-bin-path`.text()).trim();

await $`rm -rf ${app}`;
await $`mkdir -p ${app}/Contents/MacOS ${app}/Contents/Resources`;
await $`cp ${binDir}/ApexStation ${app}/Contents/MacOS/ApexStation`;
await $`cp ${binDir}/ApexPad ${app}/Contents/MacOS/ApexPad`;
if (await Bun.file(`${root}/Resources/AppIcon.icns`).exists()) {
  await $`cp ${root}/Resources/AppIcon.icns ${app}/Contents/Resources/AppIcon.icns`;
}

await Bun.write(`${app}/Contents/Info.plist`, `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.bomarov.ApexStation</string>
  <key>CFBundleName</key><string>Apex Station</string>
  <key>CFBundleDisplayName</key><string>Apex Station</string>
  <key>CFBundleExecutable</key><string>ApexStation</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${version}</string>
  <key>CFBundleVersion</key><string>${version}</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSUIElement</key><true/>
</dict></plist>
`);

// Ad-hoc signed: Apple Silicon only runs signed code, and the app needs no Apple account or
// entitlements, so it runs on any Mac once Gatekeeper is told to allow it. The ApexPad helper
// asks for the virtual-HID entitlement, which macOS honours for ad-hoc code only with AMFI
// relaxed; elsewhere the helper is stopped and the app carries on without it.
await $`codesign --force --sign - --options runtime --entitlements ${root}/Resources/ApexPad.entitlements ${app}/Contents/MacOS/ApexPad`.quiet();
await $`codesign --force --sign - --options runtime ${app}`.quiet();
console.log(`built ${app} (${version})`);

if (release) {
  const zip = `${root}/build/Apex-Station-${version}.zip`;
  await $`rm -f ${zip}`;
  await $`ditto -c -k --keepParent ${app} ${zip}`;
  console.log(`packed ${zip}`);
}

if (Bun.argv.includes("--install")) {
  const target = "/Applications/Apex Station.app";
  await $`pkill -x ApexStation`.nothrow().quiet();
  await $`rm -rf ${target}`;
  await $`cp -R ${app} ${target}`;
  await $`open ${target}`;
  console.log(`installed ${target}`);
}
