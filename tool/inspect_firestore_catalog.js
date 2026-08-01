#!/usr/bin/env node
'use strict';

/**
 * BODY HUB
 * Firestore Catalog Inspector
 *
 * READ ONLY
 *
 * Bu araç production veya emulator Firestore'u yalnızca okur.
 * Hiçbir create/update/delete işlemi yapmaz.
 */

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const {
  createAdminContext,
} = require('./manage_custom_claim_roles');
function parseArgs(argv) {
  const options = {
    emulator: false,
    projectId:
      process.env.GCLOUD_PROJECT ||
      process.env.FIREBASE_PROJECT_ID ||
      null,
    serviceAccount: null,
    outputDir: path.resolve(
      process.cwd(),
      'inspection-reports',
    ),
  };

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];

    const next = () => {
      const value = argv[i + 1];

      if (!value || value.startsWith('--')) {
        throw new Error(`${arg} requires a value.`);
      }

      i++;

      return value;
    };

    if (arg === '--emulator') {
      options.emulator = true;
    } else if (arg === '--project-id') {
      options.projectId = next();
    } else if (arg === '--service-account') {
      options.serviceAccount = path.resolve(next());
    } else if (arg === '--output-dir') {
      options.outputDir = path.resolve(next());
    } else if (arg === '--help') {
      options.help = true;
    } else {
      throw new Error(`Unknown option: ${arg}`);
    }
  }

  if (options.help) {
    return options;
  }

  if (!options.projectId) {
    throw new Error('--project-id is required.');
  }

  return options;
}
class JsonReportWriter {

  constructor(outputDir) {

    fs.mkdirSync(outputDir, {
      recursive: true,
    });

    this.path = path.join(
      outputDir,
      `inspection-${new Date()
        .toISOString()
        .replace(/[:.]/g, '-')}-${crypto
        .randomUUID()
        .slice(0, 8)}.json`,
    );
  }

  write(report) {

    fs.writeFileSync(
      this.path,
      JSON.stringify(report, null, 2),
      'utf8',
    );
  }

}

async function inspectCollection(db, collectionName) {
  const snapshot = await db.collection(collectionName).get();

  const documents = [];
  const fieldNames = new Set();
  const schemaVersions = {};
  const activeValues = {};

  for (const doc of snapshot.docs) {
    const data = doc.data();

    documents.push({
      id: doc.id,
      data,
    });

    for (const key of Object.keys(data)) {
      fieldNames.add(key);
    }

    const schema = data.schemaVersion ?? 'missing';
    schemaVersions[schema] =
      (schemaVersions[schema] ?? 0) + 1;

    if (Object.prototype.hasOwnProperty.call(data, 'active')) {
      const value = String(data.active);
      activeValues[value] =
        (activeValues[value] ?? 0) + 1;
    }
  }

  return {
    collection: collectionName,
    documentCount: snapshot.size,
    documentIds: documents.map((d) => d.id),
    fieldNames: [...fieldNames].sort(),
    schemaVersions,
    activeValues,
    sampleDocuments: documents,
  };
}

function printSummary(report) {
  console.log(`\n=== ${report.collection} ===`);
  console.log(`Documents : ${report.documentCount}`);
  console.log(`Fields    : ${report.fieldNames.join(', ')}`);

  console.log('\nSchema Versions');
  console.table(report.schemaVersions);

  if (Object.keys(report.activeValues).length > 0) {
    console.log('\nActive Values');
    console.table(report.activeValues);
  }
}

function help() {
  return [
    'Usage:',
    '  node tool/inspect_firestore_catalog.js --project-id <id> --service-account <json>',
    '',
    'Options:',
    '  --project-id <id>',
    '  --service-account <json>',
    '  --output-dir <path>',
    '  --emulator',
    '  --help',
    '',
    'This tool is read-only. It never writes to Firestore.',
  ].join('\n');
}

async function runCli(argv = process.argv.slice(2)) {
  const options = parseArgs(argv);

  if (options.help) {
    console.log(help());
    return;
  }

  const context = createAdminContext(options);
  const writer = new JsonReportWriter(options.outputDir);

  try {
    const collectionNames = [
      'packages',
      'package_catalog',
      'schedule_slot_templates',
    ];

    const collections = [];

    for (const collectionName of collectionNames) {
      const report = await inspectCollection(
        context.db,
        collectionName,
      );

      collections.push(report);
      printSummary(report);
    }

    const finalReport = {
      inspectedAt: new Date().toISOString(),
      projectId: options.projectId,
      environment: context.environment,
      readOnly: true,
      collections,
    };

    writer.write(finalReport);

    console.log(`\nReport written to: ${writer.path}`);
  } finally {
    await context.app.delete();
  }
}

if (require.main === module) {
  runCli().catch((error) => {
    console.error(`Inspection failed: ${error.message}`);
    process.exitCode = 1;
  });
}

module.exports = {
  inspectCollection,
  JsonReportWriter,
  parseArgs,
  printSummary,
  runCli,
};
