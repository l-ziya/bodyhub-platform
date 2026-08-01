#!/usr/bin/env node
'use strict';

/**
 * Trusted, immutable provisioning for the BODY HUB V2 package catalogue.
 *
 * Defaults to dry-run.
 * --apply creates only missing canonical package documents.
 * Existing conflicting documents are never overwritten.
 */

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const {
  createAdminContext,
} = require('./manage_custom_claim_roles');

const SCHEMA_VERSION = 2;

const CANONICAL_PACKAGES = Object.freeze([
  Object.freeze({
    packageId: 'athletic_10',
    sportId: 'athletic',
    packageType: 'tenSession',
    totalSessions: 10,
    validityDays: 42,
    active: true,
    schemaVersion: SCHEMA_VERSION,
  }),
  Object.freeze({
    packageId: 'athletic_monthly',
    sportId: 'athletic',
    packageType: 'monthly',
    totalSessions: 12,
    validityDays: 30,
    active: true,
    schemaVersion: SCHEMA_VERSION,
  }),
  Object.freeze({
    packageId: 'fitness_10',
    sportId: 'fitness',
    packageType: 'tenSession',
    totalSessions: 10,
    validityDays: 42,
    active: true,
    schemaVersion: SCHEMA_VERSION,
  }),
  Object.freeze({
    packageId: 'fitness_monthly',
    sportId: 'fitness',
    packageType: 'monthly',
    totalSessions: 12,
    validityDays: 30,
    active: true,
    schemaVersion: SCHEMA_VERSION,
  }),
  Object.freeze({
    packageId: 'tennis_10',
    sportId: 'tennis',
    packageType: 'tenSession',
    totalSessions: 10,
    validityDays: 42,
    active: true,
    schemaVersion: SCHEMA_VERSION,
  }),
  Object.freeze({
    packageId: 'tennis_monthly',
    sportId: 'tennis',
    packageType: 'monthly',
    totalSessions: 12,
    validityDays: 30,
    active: true,
    schemaVersion: SCHEMA_VERSION,
  }),
]);

function parseArgs(argv) {
  const options = {
    apply: false,
    emulator: false,
    projectId:
      process.env.GCLOUD_PROJECT ||
      process.env.FIREBASE_PROJECT_ID ||
      null,
    serviceAccount: null,
    operator: null,
    outputDir: path.resolve(
      process.cwd(),
      'provisioning-reports',
    ),
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];

    const next = () => {
      const value = argv[index + 1];

      if (!value || value.startsWith('--')) {
        throw new Error(`${arg} requires a value.`);
      }

      index += 1;
      return value;
    };

    if (arg === '--apply') {
      options.apply = true;
    } else if (arg === '--dry-run') {
      options.apply = false;
    } else if (arg === '--emulator') {
      options.emulator = true;
    } else if (arg === '--project-id') {
      options.projectId = next();
    } else if (arg === '--service-account') {
      options.serviceAccount = path.resolve(next());
    } else if (arg === '--operator') {
      options.operator = next();
    } else if (arg === '--output-dir') {
      options.outputDir = path.resolve(next());
    } else if (arg === '--help') {
      options.help = true;
    } else {
      throw new Error(`Unknown option: ${arg}`);
    }
  }

  if (options.help) return options;

  if (!options.projectId) {
    throw new Error('--project-id is required.');
  }

  if (options.apply && !options.operator) {
    throw new Error('--apply requires --operator.');
  }

  return options;
}

function help() {
  return [
    'Usage:',
    '  node tool/provision_package_catalog.js [options]',
    '',
    'Defaults to dry-run.',
    '',
    'Options:',
    '  --dry-run',
    '  --apply',
    '  --project-id <id>',
    '  --service-account <json>',
    '  --operator <identity>',
    '  --output-dir <path>',
    '  --emulator',
    '  --help',
    '',
    'The tool creates only missing canonical documents.',
    'Existing conflicting documents are never overwritten.',
  ].join('\n');
}

function sameDocument(actual, expected) {
  if (!actual || typeof actual !== 'object') {
    return false;
  }

  const actualKeys = Object.keys(actual).sort();
  const expectedKeys = Object.keys(expected).sort();

  return (
    actualKeys.length === expectedKeys.length &&
    actualKeys.every(
      (key, index) => key === expectedKeys[index],
    ) &&
    expectedKeys.every(
      (key) => actual[key] === expected[key],
    )
  );
}

class JsonlAuditWriter {
  constructor(outputDir, runId) {
    fs.mkdirSync(outputDir, { recursive: true });

    this.path = path.join(
      outputDir,
      `${runId}.jsonl`,
    );
  }

  write(entry) {
    fs.appendFileSync(
      this.path,
      `${JSON.stringify({
        timestamp: new Date().toISOString(),
        ...entry,
      })}\n`,
      'utf8',
    );
  }
}

class PackageCatalogProvisioner {
  constructor({
    db,
    projectId,
    operator,
    outputDir,
    environment,
  }) {
    this.db = db;
    this.projectId = projectId;
    this.operator = operator || 'read-only';
    this.environment = environment;

    this.runId =
      `package-catalog-${new Date()
        .toISOString()
        .replace(/[:.]/g, '-')}-${crypto
        .randomUUID()
        .slice(0, 8)}`;

    this.audit = new JsonlAuditWriter(
      outputDir,
      this.runId,
    );
  }

  async provision({ apply }) {
    const collection = this.db.collection(
      'package_catalog',
    );

    const snapshots = await Promise.all(
      CANONICAL_PACKAGES.map(
        (record) => collection.doc(record.packageId).get(),
      ),
    );

    const allDocuments = await collection.get();

    const matching = [];
    const missing = [];
    const conflicts = [];

    for (
      let index = 0;
      index < CANONICAL_PACKAGES.length;
      index += 1
    ) {
      const expected = CANONICAL_PACKAGES[index];
      const snapshot = snapshots[index];

      if (!snapshot.exists) {
        missing.push(expected);
      } else if (
        sameDocument(snapshot.data(), expected)
      ) {
        matching.push(expected.packageId);
      } else {
        conflicts.push({
          packageId: expected.packageId,
          existing: snapshot.data(),
          expected,
        });
      }
    }

    const canonicalIds = new Set(
      CANONICAL_PACKAGES.map(
        (record) => record.packageId,
      ),
    );

    const extras = allDocuments.docs
      .filter(
        (snapshot) => !canonicalIds.has(snapshot.id),
      )
      .map((snapshot) => ({
        packageId: snapshot.id,
        existing: snapshot.data(),
      }));

    const report = {
      runId: this.runId,
      projectId: this.projectId,
      environment: this.environment,
      operator: this.operator,
      mode: apply ? 'apply' : 'dry_run',
      matching,
      missing: missing.map(
        (record) => record.packageId,
      ),
      conflicts,
      extras,
    };

    this.audit.write({
      action: 'audit',
      ...report,
    });

    if (!apply || missing.length === 0) {
      return report;
    }

    if (conflicts.length > 0) {
      throw new Error(
        'Refusing --apply: canonical package conflicts were found.',
      );
    }

    const batch = this.db.batch();

    for (const record of missing) {
      const reference = collection.doc(
        record.packageId,
      );

      batch.create(reference, record);

      this.audit.write({
        action: 'create_proposed',
        packageId: record.packageId,
        record,
      });
    }

    await batch.commit();

    const created = missing.map(
      (record) => record.packageId,
    );

    this.audit.write({
      action: 'apply_complete',
      created,
    });

    return {
      ...report,
      created,
    };
  }
}

async function runCli(argv = process.argv.slice(2)) {
  const options = parseArgs(argv);

  if (options.help) {
    console.log(help());
    return;
  }

  const context = createAdminContext(options);

  try {
    const provisioner = new PackageCatalogProvisioner({
      db: context.db,
      projectId: options.projectId,
      operator: options.operator,
      outputDir: options.outputDir,
      environment: context.environment,
    });

    const report = await provisioner.provision(
      options,
    );

    console.log(
      JSON.stringify(
        {
          report,
          auditPath: provisioner.audit.path,
        },
        null,
        2,
      ),
    );
  } finally {
    await context.app.delete();
  }
}

if (require.main === module) {
  runCli().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}

module.exports = {
  CANONICAL_PACKAGES,
  SCHEMA_VERSION,
  PackageCatalogProvisioner,
  parseArgs,
  sameDocument,
  runCli,
};