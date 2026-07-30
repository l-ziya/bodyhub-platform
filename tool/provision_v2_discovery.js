#!/usr/bin/env node
'use strict';

/**
 * Trusted, Admin-SDK-only provisioning for the V2 sports catalogue and public
 * Coach discovery profiles. Flutter clients have no create/delete path.
 */
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { FieldValue } = require('firebase-admin/firestore');
const { createAdminContext } = require('./manage_custom_claim_roles');

const SCHEMA_VERSION = 2;
const WRITE_OPERATIONS = new Set(['upsert-sport', 'upsert-coach-profile']);
const SPORT_ID = /^[a-z0-9]+(?:_[a-z0-9]+)*$/;

function parseArgs(argv) {
  const options = {
    command: null,
    apply: false,
    emulator: false,
    input: null,
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
    if (!options.command && !arg.startsWith('--')) options.command = arg;
    else if (arg === '--apply') options.apply = true;
    else if (arg === '--emulator') options.emulator = true;
    else if (arg === '--input') options.input = path.resolve(next());
    else if (arg === '--project-id') options.projectId = next();
    else if (arg === '--service-account') options.serviceAccount = path.resolve(next());
    else if (arg === '--operator') options.operator = next();
    else if (arg === '--output-dir') options.outputDir = path.resolve(next());
    else if (arg === '--help') options.help = true;
    else throw new Error(`Unknown option: ${arg}`);
  }
  if (options.help) return options;
  if (!WRITE_OPERATIONS.has(options.command)) {
    throw new Error('Command must be upsert-sport or upsert-coach-profile.');
  }
  if (!options.input) throw new Error('--input is required.');
  if (!options.projectId) throw new Error('--project-id is required.');
  if (options.apply && !options.operator) throw new Error('--operator is required for --apply writes.');
  return options;
}

function readInput(inputPath) {
  let value;
  try {
    value = JSON.parse(fs.readFileSync(inputPath, 'utf8'));
  } catch (error) {
    throw new Error(`Cannot read valid JSON from --input: ${error.message}`);
  }
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error('--input must be one JSON object.');
  }
  return value;
}

function normalizedSpecialtyIds(values) {
  if (!Array.isArray(values)) throw new Error('specialtyIds must be an array.');
  const ids = [...new Set(values.map((value) => String(value).trim()).filter(Boolean))];
  if (ids.length !== values.length || ids.some((id) => !SPORT_ID.test(id))) {
    throw new Error('specialtyIds must contain unique stable sport slugs.');
  }
  return ids;
}

function hasCoachClaim(user) {
  const roles = user.customClaims?.roles;
  return roles?.coach === true || roles?.admin === true
    || user.customClaims?.role === 'coach' || user.customClaims?.role === 'admin';
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

class V2DiscoveryProvisioner {
  constructor({ auth, db, projectId, operator, outputDir, environment = 'production' }) {
    this.auth = auth;
    this.db = db;
    this.projectId = projectId;
    this.operator = operator || 'read-only';
    this.environment = environment;
    this.runId = `v2-discovery-${new Date().toISOString().replace(/[:.]/g, '-')}-${crypto.randomUUID().slice(0, 8)}`;
    this.audit = new JsonlAuditWriter(outputDir, this.runId);
  }

  async upsertSport(input, { apply }) {
    const sportId = String(input.sportId || '').trim();
    const name = String(input.name || '').trim();
    if (!SPORT_ID.test(sportId) || !name) {
      throw new Error('sportId must be a stable slug and name is required.');
    }
    const proposed = {
      name,
      active: input.active === true,
      sortOrder: Number.isInteger(input.sortOrder) ? input.sortOrder : 0,
      schemaVersion: SCHEMA_VERSION,
    };
    const reference = this.db.collection('sports').doc(sportId);
    const existing = await reference.get();
    const report = this._report('upsert-sport', sportId, {
      previous: existing.exists ? existing.data() : null,
      proposed,
      result: apply ? 'proposed_apply' : 'dry_run',
    });
    this.audit.write(report);
    if (!apply) return report;
    await this.db.runTransaction(async (transaction) => {
      const current = await transaction.get(reference);
      const write = {
        ...proposed,
        updatedAt: FieldValue.serverTimestamp(),
        updatedBy: this.operator,
      };
      if (!current.exists) {
        write.createdAt = FieldValue.serverTimestamp();
        write.createdBy = this.operator;
      }
      transaction.set(reference, write, { merge: true });
    });
    const completed = { ...report, result: 'applied' };
    this.audit.write(completed);
    return completed;
  }

  async upsertCoachProfile(input, { apply }) {
    const coachId = String(input.coachId || '').trim();
    const displayName = String(input.displayName || '').trim();
    if (!coachId || displayName.length < 2) {
      throw new Error('coachId and a displayName of at least two characters are required.');
    }
    const specialties = normalizedSpecialtyIds(input.specialtyIds || []);
    const coach = await this.auth.getUser(coachId);
    if (!hasCoachClaim(coach)) throw new Error('coachId must have a Coach or Admin custom claim.');
    const sportSnapshots = await Promise.all(
      specialties.map((sportId) => this.db.collection('sports').doc(sportId).get()),
    );
    if (sportSnapshots.some((sport) => !sport.exists || sport.get('active') !== true)) {
      throw new Error('Every specialtyId must reference an active provisioned sport.');
    }
    const proposed = {
      displayName,
      active: input.active === true,
      bookingEnabled: input.bookingEnabled === true,
      specialtyIds: specialties,
      bio: String(input.bio || '').trim(),
      photoUrl: String(input.photoUrl || '').trim(),
      schemaVersion: SCHEMA_VERSION,
    };
    const reference = this.db.collection('coach_profiles').doc(coachId);
    const existing = await reference.get();
    const report = this._report('upsert-coach-profile', coachId, {
      previous: existing.exists ? existing.data() : null,
      proposed,
      result: apply ? 'proposed_apply' : 'dry_run',
    });
    this.audit.write(report);
    if (!apply) return report;
    await this.db.runTransaction(async (transaction) => {
      const current = await transaction.get(reference);
      const write = {
        ...proposed,
        updatedAt: FieldValue.serverTimestamp(),
        updatedBy: this.operator,
      };
      if (!current.exists) {
        write.createdAt = FieldValue.serverTimestamp();
        write.createdBy = this.operator;
      }
      transaction.set(reference, write, { merge: true });
    });
    const completed = { ...report, result: 'applied' };
    this.audit.write(completed);
    return completed;
  }

  _report(command, targetId, extra) {
    return {
      runId: this.runId,
      projectId: this.projectId,
      environment: this.environment,
      operator: this.operator,
      command,
      targetId,
      ...extra,
    };
  }
}

function help() {
  return `Usage: node tool/provision_v2_discovery.js <command> --input <json> [options]\n\n`
    + `Commands: upsert-sport, upsert-coach-profile\n`
    + `Writes are dry-run unless --apply is present. Production requires a matching\n`
    + `--service-account; emulator mode requires --emulator and loopback hosts.\n`;
}

async function runCli(argv = process.argv.slice(2)) {
  const options = parseArgs(argv);
  if (options.help) {
    console.log(help());
    return;
  }
  const context = createAdminContext(options);
  try {
    const provisioner = new V2DiscoveryProvisioner({
      auth: context.auth,
      db: context.db,
      projectId: options.projectId,
      operator: options.operator,
      outputDir: options.outputDir,
      environment: context.environment,
    });
    const input = readInput(options.input);
    const result = options.command === 'upsert-sport'
      ? await provisioner.upsertSport(input, options)
      : await provisioner.upsertCoachProfile(input, options);
    console.log(JSON.stringify({ result, auditPath: provisioner.audit.path }, null, 2));
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
  SCHEMA_VERSION,
  V2DiscoveryProvisioner,
  hasCoachClaim,
  normalizedSpecialtyIds,
  parseArgs,
  readInput,
  runCli,
};
