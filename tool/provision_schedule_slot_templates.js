#!/usr/bin/env node
'use strict';

/**
 * Trusted, versioned provisioning for the immutable V2 hourly slot catalogue.
 * This is an operational Admin-SDK tool, never a Flutter runtime dependency.
 */
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { createAdminContext } = require('./manage_custom_claim_roles');

const slotCatalogPath = path.resolve(
  __dirname,
  '../../bodyhub_domain_contract/schema/canonical_schedule_slots.json',
);
const slotCatalog = JSON.parse(fs.readFileSync(slotCatalogPath, 'utf8'));
const SCHEMA_VERSION = slotCatalog.schemaVersion;
const TEMPLATE_IDS = Object.freeze(slotCatalog.slotIds);

if (!Number.isInteger(SCHEMA_VERSION) ||
  TEMPLATE_IDS.length !== 13 ||
  new Set(TEMPLATE_IDS).size !== TEMPLATE_IDS.length ||
  TEMPLATE_IDS.some((slotId) => !/^(0[89]|1[0-9]|20)00$/.test(slotId))) {
  throw new Error('Invalid canonical schedule slot catalogue.');
}

const CANONICAL_TEMPLATES = Object.freeze(
  TEMPLATE_IDS.map((slotId, sequence) => Object.freeze({
    slotId,
    sequence,
    active: true,
    schemaVersion: SCHEMA_VERSION,
  })),
);

function parseArgs(argv) {
  const options = {
    apply: false,
    emulator: false,
    projectId: process.env.GCLOUD_PROJECT || process.env.FIREBASE_PROJECT_ID || null,
    serviceAccount: null,
    operator: null,
    outputDir: path.resolve(process.cwd(), 'provisioning-reports'),
  };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    const next = () => {
      const value = argv[index + 1];
      if (!value || value.startsWith('--')) throw new Error(`${arg} requires a value.`);
      index += 1;
      return value;
    };
    if (arg === '--apply') options.apply = true;
    else if (arg === '--dry-run') options.apply = false;
    else if (arg === '--emulator') options.emulator = true;
    else if (arg === '--project-id') options.projectId = next();
    else if (arg === '--service-account') options.serviceAccount = path.resolve(next());
    else if (arg === '--operator') options.operator = next();
    else if (arg === '--output-dir') options.outputDir = path.resolve(next());
    else if (arg === '--help') options.help = true;
    else throw new Error(`Unknown option: ${arg}`);
  }
  if (options.help) return options;
  if (!options.projectId) throw new Error('--project-id is required.');
  if (options.apply && !options.operator) throw new Error('--apply requires --operator.');
  return options;
}

function sameTemplate(actual, expected) {
  if (!actual || typeof actual !== 'object') return false;
  const keys = Object.keys(actual).sort();
  const expectedKeys = Object.keys(expected).sort();
  return keys.length === expectedKeys.length
    && keys.every((key, index) => key === expectedKeys[index])
    && expectedKeys.every((key) => actual[key] === expected[key]);
}

class JsonlAuditWriter {
  constructor(outputDir, runId) {
    fs.mkdirSync(outputDir, { recursive: true });
    this.path = path.join(outputDir, `${runId}.jsonl`);
  }

  write(entry) {
    fs.appendFileSync(this.path, `${JSON.stringify({ timestamp: new Date().toISOString(), ...entry })}\n`);
  }
}

class ScheduleSlotTemplateProvisioner {
  constructor({ db, projectId, operator, outputDir, environment }) {
    this.db = db;
    this.projectId = projectId;
    this.operator = operator || 'read-only';
    this.environment = environment;
    this.runId = `schedule-templates-${new Date().toISOString().replace(/[:.]/g, '-')}-${crypto.randomUUID().slice(0, 8)}`;
    this.audit = new JsonlAuditWriter(outputDir, this.runId);
  }

  async provision({ apply }) {
    const collection = this.db.collection('schedule_slot_templates');
    const snapshots = await Promise.all(CANONICAL_TEMPLATES.map((template) => collection.doc(template.slotId).get()));
    const all = await collection.get();
    const missing = [];
    const matching = [];
    const conflicts = [];

    for (let index = 0; index < CANONICAL_TEMPLATES.length; index += 1) {
      const expected = CANONICAL_TEMPLATES[index];
      const snapshot = snapshots[index];
      if (!snapshot.exists) missing.push(expected);
      else if (sameTemplate(snapshot.data(), expected)) matching.push(expected.slotId);
      else conflicts.push({ slotId: expected.slotId, existing: snapshot.data(), expected });
    }
    const extras = all.docs
      .filter((snapshot) => !TEMPLATE_IDS.includes(snapshot.id))
      .map((snapshot) => ({ slotId: snapshot.id, existing: snapshot.data() }));
    const report = {
      runId: this.runId,
      projectId: this.projectId,
      environment: this.environment,
      operator: this.operator,
      mode: apply ? 'apply' : 'dry_run',
      matching,
      missing: missing.map((template) => template.slotId),
      conflicts,
      extras,
    };
    this.audit.write({ action: 'audit', ...report });
    if (!apply || missing.length === 0) return report;
    if (conflicts.length > 0) {
      throw new Error('Refusing --apply: one or more canonical templates conflict with the expected immutable content.');
    }
    const batch = this.db.batch();
    for (const template of missing) {
      batch.create(collection.doc(template.slotId), template);
      this.audit.write({ action: 'create_proposed', slotId: template.slotId, template });
    }
    await batch.commit();
    this.audit.write({ action: 'apply_complete', created: missing.map((template) => template.slotId) });
    return { ...report, created: missing.map((template) => template.slotId) };
  }
}

function help() {
  return `Usage: node tool/provision_schedule_slot_templates.js [options]\n\n`
    + `Defaults to dry-run. --apply creates only missing canonical templates.\n`
    + `Options: --apply --dry-run --project-id <id> --service-account <json>\n`
    + `         --operator <identity> --emulator --output-dir <path>\n`;
}

async function runCli(argv = process.argv.slice(2)) {
  const options = parseArgs(argv);
  if (options.help) {
    console.log(help());
    return;
  }
  const context = createAdminContext(options);
  try {
    const provisioner = new ScheduleSlotTemplateProvisioner({
      db: context.db,
      projectId: options.projectId,
      operator: options.operator,
      outputDir: options.outputDir,
      environment: context.environment,
    });
    const report = await provisioner.provision(options);
    console.log(JSON.stringify({ report, auditPath: provisioner.audit.path }, null, 2));
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
  CANONICAL_TEMPLATES,
  SCHEMA_VERSION,
  ScheduleSlotTemplateProvisioner,
  parseArgs,
  sameTemplate,
};
