// Copies Flydigi's stock screen animations out of the Space Station installer so Apex Station can
// put the original screen back. They're Flydigi's artwork, so this project doesn't ship them.
//   bun scripts/screen-default.ts <ss4_setup.exe>     (needs innoextract: brew install innoextract)
import { $ } from "bun";
import { homedir, tmpdir } from "node:os";

const installer = process.argv[2];
if (!installer) {
  console.error("usage: bun scripts/screen-default.ts <ss4_setup.exe>");
  process.exit(1);
}
const work = `${tmpdir()}/apex-station-screen-${process.pid}`;
const dest = `${homedir()}/Library/Application Support/Apex Station/Screen`;
await $`mkdir -p ${work} ${dest}`;
await $`innoextract -q -I app/Configs/Controller/k5/default -d ${work} ${installer}`;
const files = (await $`find ${work} -name 'default_screen_image_*.bin'`.text()).trim().split("\n").filter(Boolean);
for (const f of files) await $`cp -f ${f} ${dest}/`;
await $`rm -rf ${work}`;
console.log(`copied ${files.length} animations to ${dest}`);
