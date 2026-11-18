// Octal-only OCR candidates. These results require independent scan review.
const fs = require('node:fs');
const path = require('node:path');
const {createWorker} = require('tesseract.js');
(async()=>{
  const [langPath,...images]=process.argv.slice(2);
  if(!langPath||!images.length) throw new Error('Usage: ocr-octal.cjs LANG_DIRECTORY IMAGE...');
  const worker=await createWorker('eng',1,{langPath:path.resolve(langPath),gzip:false,cacheMethod:'none'});
  try {
    await worker.setParameters({tessedit_pageseg_mode:6,tessedit_char_whitelist:'01234567',preserve_interword_spaces:'1'});
    for(const image of images) {
      const {data}=await worker.recognize(image,{}, {text:true,tsv:true});
      fs.writeFileSync(image+'.octal.json',JSON.stringify({image,status:'unreviewed OCR candidate',confidence:data.confidence,text:data.text,tsv:data.tsv},null,2));
      console.log(`${path.basename(image)} confidence=${data.confidence}\n${data.text}`);
    }
  } finally {await worker.terminate()}
})().catch(error=>{console.error(error);process.exitCode=1});
