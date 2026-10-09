// Renders the app icon at every size macOS wants and packs Resources/AppIcon.icns.
//   bun scripts/icon.ts
import { $ } from "bun";
import { swift } from "./swift";

const root = `${import.meta.dir}/..`;
await swift(["build", "--package-path", root]);
const bin = `${(await $`swift build --package-path ${root} --show-bin-path`.text()).trim()}/ApexStation`;
const set = `${root}/build/AppIcon.iconset`;
await $`rm -rf ${set} && mkdir -p ${set}`;
for (const pt of [16, 32, 128, 256, 512]) {
  await $`${bin} --render-icon ${set}/icon_${pt}x${pt}.png ${pt}`;
  await $`${bin} --render-icon ${set}/icon_${pt}x${pt}@2x.png ${pt * 2}`;
}
await $`mkdir -p ${root}/Resources`;
await $`iconutil -c icns ${set} -o ${root}/Resources/AppIcon.icns`;
console.log("wrote Resources/AppIcon.icns");
