// Requires tesseract.js (the bundled Codex Node packages can supply it via NODE_PATH).
// Usage: node tools/ocr-handbook.cjs LANG_DIRECTORY IMAGE [IMAGE ...]
const fs = require('node:fs');
const path = require('node:path');
const { createWorker } = require('tesseract.js');

(async () => {
  const [langPath, ...images] = process.argv.slice(2);
  if (!langPath || !images.length) throw new Error('Expected English language-model directory and image paths.');
  const worker = await createWorker('eng', 1, { langPath: path.resolve(langPath), gzip: false, cacheMethod: 'none' });
  try {
    await worker.setParameters({ tessedit_pageseg_mode: 6, preserve_interword_spaces: '1' });
    for (const image of images) {
      const { data } = await worker.recognize(image, {}, { text: true, tsv: true });
      fs.writeFileSync(image + '.txt', data.text);
      if (data.tsv) fs.writeFileSync(image + '.tsv', data.tsv);
      console.log(`${path.basename(image)} confidence=${data.confidence}`);
    }
  } finally { await worker.terminate(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
