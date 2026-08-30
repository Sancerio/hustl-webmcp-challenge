import fs from 'node:fs';

const [inputPath, outputPath] = process.argv.slice(2);
if (!inputPath || !outputPath) {
  throw new Error('Usage: node scrub_evaluator_catalog.mjs INPUT OUTPUT');
}

const catalog = JSON.parse(fs.readFileSync(inputPath, 'utf8'));
if (!Array.isArray(catalog)) {
  throw new Error('Evaluator exercise catalog must be a JSON array');
}

const scrubbed = catalog.map((entry) => ({...entry, imageUrl: null}));
fs.writeFileSync(outputPath, `${JSON.stringify(scrubbed)}\n`);
