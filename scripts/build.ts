// Builds "Apex Station.app" with only Apple's Command Line Tools.
//   bun scripts/build.ts            → build/Apex Station.app
//   bun scripts/build.ts --install  → also installs to /Applications and relaunches it
import { $ } from "bun";
import { swift } from "./swift";

const root = `${import.meta.dir}/..`;
const app = `${root}/build/Apex Station.app`;
const version = (await Bun.file(`${root}/VERSION`).text()).trim();

await swift(["build", "-c", "release", "--package-path", root]);
const binDir = (await $`swift build -c release --package-path ${root} --show-bin-path`.text()).trim();

await $`rm -rf ${app}`;
await $`mkdir -p ${app}/Contents/MacOS ${app}/Contents/Resources`;
await $`cp ${binDir}/ApexStation ${app}/Contents/MacOS/ApexStation`;
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
</dict></plist>
`);

// The virtual Xbox controller needs Apple's virtual-HID entitlement. Ad-hoc signed builds
// only get it while AMFI is relaxed; a Developer ID build needs Apple to grant it.
await $`codesign --force --sign - --options runtime --entitlements ${root}/Resources/ApexStation.entitlements ${app}`.quiet();
console.log(`built ${app} (${version})`);

if (Bun.argv.includes("--install")) {
  const target = "/Applications/Apex Station.app";
  await $`pkill -x ApexStation`.nothrow().quiet();
  await $`rm -rf ${target}`;
  await $`cp -R ${app} ${target}`;
  await $`open ${target}`;
  console.log(`installed ${target}`);
}
