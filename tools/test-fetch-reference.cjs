// Run with: node tools/test-fetch-reference.cjs
// Exercises transport and file checks against a local server; no external downloads.
const http = require('http');
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const {spawn} = require('child_process');

const tempParent = fs.realpathSync(os.tmpdir());
const scratch = fs.mkdtempSync(path.join(tempParent, 'goodapollo-reference-test-'));
const downloader = path.join(__dirname, 'fetch-reference.ps1');
const pdf = Buffer.from('%PDF-1.4\n' + 'A'.repeat(131072) + '\n%%EOF\n');
const requests = [];
const results = [];
let interrupted = false;

const server = http.createServer((req, res) => {
  requests.push({method: req.method, url: req.url, range: req.headers.range || ''});
  if (req.url === '/missing.pdf') {
    res.writeHead(404, {'Content-Length': 0});
    res.end();
    return;
  }
  const body = req.url === '/html.pdf' ? Buffer.from('<html>Landing page, not a PDF.</html>') : pdf;
  if (req.method === 'HEAD') {
    res.writeHead(200, {'Content-Length': body.length, 'Content-Type': 'application/pdf'});
    res.end();
    return;
  }
  if (req.url === '/interrupt.pdf' && !interrupted && !req.headers.range) {
    interrupted = true;
    res.writeHead(200, {'Content-Length': body.length, 'Content-Type': 'application/pdf'});
    res.write(body.subarray(0, 8192));
    setTimeout(() => res.destroy(), 50);
    return;
  }
  if (req.headers.range && req.url !== '/no-range.pdf') {
    const offset = Number(req.headers.range.match(/^bytes=(\d+)-$/)[1]);
    res.writeHead(206, {
      'Content-Length': body.length - offset,
      'Content-Type': 'application/pdf',
      'Content-Range': `bytes ${offset}-${body.length - 1}/${body.length}`,
    });
    res.end(body.subarray(offset));
    return;
  }
  res.writeHead(200, {'Content-Length': body.length, 'Content-Type': 'application/pdf'});
  res.end(body);
});

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function run(name, url) {
  const root = path.join(scratch, name);
  fs.mkdirSync(root, {recursive: true});
  const manifestPath = path.join(root, 'manifest.json');
  fs.writeFileSync(manifestPath, JSON.stringify({
    bases: {},
    items: [{cat: 'docs', p: 0, kind: 'file', url, title: name}],
  }));
  return new Promise((resolve, reject) => {
    const child = spawn('powershell.exe', [
      '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', downloader,
      '-DataRoot', root, '-MaxPriority', '0', '-FilesOnly', '-ManifestPath', manifestPath,
    ], {windowsHide: true});
    let output = '';
    let timedOut = false;
    const timer = setTimeout(() => {
      timedOut = true;
      child.kill();
    }, 30000);
    child.stdout.on('data', data => output += data);
    child.stderr.on('data', data => output += data);
    child.once('error', error => {
      clearTimeout(timer);
      reject(error);
    });
    // close waits for captured output, unlike exit.
    child.once('close', (code, signal) => {
      clearTimeout(timer);
      if (timedOut) return reject(new Error(`Downloader timed out: ${name}\n${output}`));
      if (signal) return reject(new Error(`Downloader stopped by ${signal}: ${name}\n${output}`));
      resolve({code, output, root, final: path.join(root, 'docs', path.basename(new URL(url).pathname))});
    });
  });
}

async function test(name, action) {
  try {
    await action();
    results.push(true);
    console.log(`PASS ${name}`);
  } catch (error) {
    results.push(false);
    console.error(`FAIL ${name}\n${error.message}`);
  }
}

async function main() {
  try {
    await new Promise((resolve, reject) => {
      server.once('error', reject);
      server.listen(0, '127.0.0.1', resolve);
    });
    const base = `http://127.0.0.1:${server.address().port}`;
    await test('valid PDF and SHA-256 receipt', async () => {
      const r = await run('valid', `${base}/valid.pdf`);
      assert(r.code === 0, r.output);
      assert(fs.readFileSync(r.final).equals(pdf), 'Downloaded bytes differ');
      const receipt = JSON.parse(fs.readFileSync(path.join(r.root, 'download-receipt.json'), 'utf8').replace(/^\uFEFF/, ''));
      assert(receipt.files[0].sha256 === crypto.createHash('sha256').update(pdf).digest('hex'), 'Hash differs');
    });
    await test('completed file skips GET', async () => {
      const before = requests.filter(x => x.method === 'GET' && x.url === '/valid.pdf').length;
      const r = await run('valid', `${base}/valid.pdf`);
      assert(r.code === 0 && r.output.includes('VERIFIED'), r.output);
      assert(requests.filter(x => x.method === 'GET' && x.url === '/valid.pdf').length === before, 'Repeated GET');
    });
    await test('200 HTML cannot become a PDF', async () => {
      const r = await run('html', `${base}/html.pdf`);
      assert(r.code === 1 && r.output.includes('Not a PDF'), r.output);
      assert(!fs.existsSync(r.final), 'HTML promoted to final');
    });
    await test('HTTP 404 fails', async () => {
      const r = await run('missing', `${base}/missing.pdf`);
      assert(r.code === 1 && r.output.includes('HEAD request failed'), r.output);
      assert(requests.some(x => x.method === 'HEAD' && x.url === '/missing.pdf'), '404 fixture was never reached');
      assert(!fs.existsSync(r.final), '404 saved as final');
    });
    await test('partial download resumes with Range', async () => {
      const root = path.join(scratch, 'range', 'docs');
      fs.mkdirSync(root, {recursive: true});
      fs.writeFileSync(path.join(root, 'range.pdf.part'), pdf.subarray(0, 4096));
      const r = await run('range', `${base}/range.pdf`);
      assert(r.code === 0, r.output);
      assert(fs.readFileSync(r.final).equals(pdf), 'Resumed bytes differ');
      assert(requests.some(x => x.url === '/range.pdf' && x.range === 'bytes=4096-'), 'No resume Range');
    });
    await test('interrupted transfer retains partial and resumes', async () => {
      const first = await run('interrupted', `${base}/interrupt.pdf`);
      assert(first.code === 1 && fs.existsSync(first.final + '.part') && !fs.existsSync(first.final), first.output);
      const second = await run('interrupted', `${base}/interrupt.pdf`);
      assert(second.code === 0, second.output);
      assert(fs.readFileSync(second.final).equals(pdf), 'Interrupted resume bytes differ');
      assert(requests.some(x => x.url === '/interrupt.pdf' && x.range === 'bytes=8192-'), 'No interrupted Range');
    });
    await test('server ignoring Range triggers full retry', async () => {
      const root = path.join(scratch, 'no-range', 'docs');
      fs.mkdirSync(root, {recursive: true});
      fs.writeFileSync(path.join(root, 'no-range.pdf.part'), pdf.subarray(0, 4096));
      const r = await run('no-range', `${base}/no-range.pdf`);
      assert(r.code === 0 && r.output.includes('restarting'), r.output);
      assert(fs.readFileSync(r.final).equals(pdf), 'Restart bytes differ');
      assert(requests.some(x => x.url === '/no-range.pdf' && x.range === 'bytes=4096-'), 'No ignored Range attempt');
      assert(requests.some(x => x.url === '/no-range.pdf' && x.method === 'GET' && !x.range), 'No full retry');
    });
    await test('checksum mismatch fails without redownload', async () => {
      const final = path.join(scratch, 'valid', 'docs', 'valid.pdf');
      const tampered = Buffer.from(pdf);
      tampered[4096] = 66;
      fs.writeFileSync(final, tampered);
      const before = requests.filter(x => x.method === 'GET' && x.url === '/valid.pdf').length;
      const r = await run('valid', `${base}/valid.pdf`);
      assert(r.code === 1 && r.output.includes('SHA256 mismatch'), r.output);
      assert(requests.filter(x => x.method === 'GET' && x.url === '/valid.pdf').length === before, 'Redownload on mismatch');
    });
    const passed = results.filter(Boolean).length;
    console.log(`${passed}/${results.length} downloader checks passed.`);
    if (passed !== results.length) process.exitCode = 1;
  } finally {
    if (server.listening) {
      await new Promise(resolve => {
        server.close(resolve);
        server.closeAllConnections();
      });
    }
    // Verify the exact directory before recursively deleting only this run's scratch data.
    const resolvedScratch = fs.realpathSync(scratch);
    assert(path.dirname(resolvedScratch) === tempParent && path.basename(resolvedScratch).startsWith('goodapollo-reference-test-'), 'Unexpected cleanup target');
    fs.rmSync(resolvedScratch, {recursive: true, force: true});
  }
}

main().catch(error => {
  console.error(error.message);
  process.exitCode = 1;
});
