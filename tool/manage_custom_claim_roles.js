#!/usr/bin/env node
'use strict';

/**
 * Controlled Firebase Auth custom-claim administration for BODY HUB.
 * This tool is intentionally independent from the Flutter clients.
 */
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const admin = require('firebase-admin');
const { cert, initializeApp } = require('firebase-admin/app');
const { FieldValue, getFirestore } = require('firebase-admin/firestore');
const { getAuth } = require('firebase-admin/auth');

const ALLOWED_ROLES = new Set(['student', 'coach', 'admin']);
const WRITE_OPERATIONS = new Set(['set-role', 'remove-role']);
const PRODUCTION_PROJECT_ID = 'body-hub-10745';

function parseArgs(argv) {
  const options = {
    command: null,
    apply: false,
    emulator: false,
    uid: null,
    email: null,
    role: null,
    projectId: process.env.GCLOUD_PROJECT || process.env.FIREBASE_PROJECT_ID || null,
    serviceAccount: null,
    operator: null,
    outputDir: path.resolve(process.cwd(), 'claim-role-reports'),
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
    else if (arg === '--uid') options.uid = next();
    else if (arg === '--email') options.email = next();
    else if (arg === '--role') options.role = next();
    else if (arg === '--project-id') options.projectId = next();
    else if (arg === '--service-account') options.serviceAccount = path.resolve(next());
    else if (arg === '--operator') options.operator = next();
    else if (arg === '--output-dir') options.outputDir = path.resolve(next());
    else if (arg === '--help') options.help = true;
    else throw new Error(`Unknown option: ${arg}`);
  }
  if (options.help) return options;
  if (!['set-role', 'remove-role', 'show-role', 'list-privileged-users'].includes(options.command)) {
    throw new Error('Command must be set-role, remove-role, show-role, or list-privileged-users.');
  }
  if (options.uid && options.email) throw new Error('Use either --uid or --email, not both.');
  if (options.command !== 'list-privileged-users' && !options.uid && !options.email) {
    throw new Error(`${options.command} requires --uid or --email.`);
  }
  if (options.command === 'set-role' && !ALLOWED_ROLES.has(options.role)) {
    throw new Error('--role must be student, coach, or admin.');
  }
  if (options.command === 'remove-role' && options.role && !ALLOWED_ROLES.has(options.role)) {
    throw new Error('--role must be student, coach, or admin.');
  }
  if (!['set-role', 'remove-role'].includes(options.command) && options.role) {
    throw new Error('--role is only valid for set-role or remove-role.');
  }
  if (!options.projectId) throw new Error('--project-id is required.');
  if (WRITE_OPERATIONS.has(options.command) && options.apply && !options.operator) {
    throw new Error('--operator is required for --apply writes.');
  }
  return options;
}

function help() {
  return `Usage: node tool/manage_custom_claim_roles.js <command> [options]\n\n` +
    `Commands:\n` +
    `  set-role --uid <uid>|--email <email> --role student|coach|admin [--apply]\n` +
    `  remove-role --uid <uid>|--email <email> [--role student|coach|admin] [--apply]\n` +
    `  show-role --uid <uid>|--email <email>\n` +
    `  list-privileged-users\n\n` +
    `Safety:\n` +
    `  Writes are dry-run unless --apply is supplied.\n` +
    `  Production requires --service-account with a matching --project-id.\n` +
    `  Emulator use requires --emulator and both Firebase emulator host variables.\n\n` +
    `Common options: --project-id <id> --service-account <json> --operator <identity>\n` +
    `                --output-dir <directory> --emulator\n`;
}

function isLoopbackHost(host) {
  if (!host) return false;
  const hostname = host.split(':')[0].toLowerCase();
  return hostname === '127.0.0.1' || hostname === 'localhost' || hostname === '::1';
}

function createAdminContext(options, dependencies = {}) {
  const sdk = dependencies.admin || admin;
  if (options.emulator) {
    if (!process.env.FIREBASE_AUTH_EMULATOR_HOST || !process.env.FIRESTORE_EMULATOR_HOST) {
      throw new Error('--emulator requires FIREBASE_AUTH_EMULATOR_HOST and FIRESTORE_EMULATOR_HOST.');
    }
    if (!isLoopbackHost(process.env.FIREBASE_AUTH_EMULATOR_HOST)
      || !isLoopbackHost(process.env.FIRESTORE_EMULATOR_HOST)) {
      throw new Error('Emulator hosts must be loopback addresses.');
    }
    if (options.projectId === PRODUCTION_PROJECT_ID) {
      throw new Error('--emulator cannot use the production project ID.');
    }
    if (options.serviceAccount) throw new Error('--emulator must not use a production service account.');
    const app = initializeApp({ projectId: options.projectId }, `claim-role-emulator-${crypto.randomUUID()}`);
    return { app, auth: getAuth(app), db: getFirestore(app), environment: 'emulator' };
  }

  if (process.env.FIREBASE_AUTH_EMULATOR_HOST || process.env.FIRESTORE_EMULATOR_HOST) {
    throw new Error('Production mode refuses emulator environment variables. Use --emulator explicitly.');
  }
  if (!options.serviceAccount) throw new Error('Production mode requires --service-account.');
  const credentials = JSON.parse(fs.readFileSync(options.serviceAccount, 'utf8'));
  if (credentials.project_id !== options.projectId) {
    throw new Error('Service account project_id must match --project-id.');
  }
  const app = initializeApp({
    credential: cert(credentials),
    projectId: options.projectId,
  }, `claim-role-production-${crypto.randomUUID()}`);
  return { app, auth: getAuth(app), db: getFirestore(app), environment: 'production' };
}

class JsonlAuditWriter {
  constructor(outputDir, runId) {
    this.outputDir = outputDir;
    this.runId = runId;
    fs.mkdirSync(outputDir, { recursive: true });
    this.path = path.join(outputDir, `${runId}.jsonl`);
  }

  write(entry) {
    fs.appendFileSync(this.path, `${JSON.stringify({ timestamp: new Date().toISOString(), ...entry })}\n`);
  }
}

function managedRoles(userRecord) {
  const canonical = userRecord.customClaims?.roles;
  const roles = canonical && typeof canonical === 'object'
    ? Object.entries(canonical)
      .filter(([role, enabled]) => ALLOWED_ROLES.has(role) && enabled === true)
      .map(([role]) => role)
    : [];
  if (roles.length > 0) return roles.sort();
  const legacy = userRecord.customClaims?.role;
  return ALLOWED_ROLES.has(legacy) ? [legacy] : [];
}

function primaryRole(roles) {
  if (roles.includes('admin')) return 'admin';
  if (roles.includes('coach')) return 'coach';
  if (roles.includes('student')) return 'student';
  return null;
}

class CustomClaimRoleManager {
  constructor({ auth, db, projectId, operator, outputDir, environment = 'production' }) {
    this.auth = auth;
    this.db = db;
    this.projectId = projectId;
    this.operator = operator || 'read-only';
    this.environment = environment;
    this.runId = `claim-role-${new Date().toISOString().replace(/[:.]/g, '-')}-${crypto.randomUUID().slice(0, 8)}`;
    this.audit = new JsonlAuditWriter(outputDir, this.runId);
  }

  async resolveUser({ uid, email }) {
    return uid ? this.auth.getUser(uid) : this.auth.getUserByEmail(email);
  }

  async showRole(selector) {
    const user = await this.resolveUser(selector);
    const metadata = await this.db.collection('users').doc(user.uid).get();
    return this._report(user, {
      command: 'show-role',
      currentRole: primaryRole(managedRoles(user)),
      currentRoles: managedRoles(user),
      metadataRole: metadata.exists ? metadata.get('role') ?? null : null,
      result: 'read_only',
    });
  }

  async listPrivilegedUsers() {
    const users = [];
    let pageToken;
    do {
      const page = await this.auth.listUsers(1000, pageToken);
      for (const user of page.users) {
        const roles = managedRoles(user);
        if (roles.some((role) => role === 'coach' || role === 'admin')) {
          users.push(this._report(user, {
            command: 'list-privileged-users', currentRole: primaryRole(roles), currentRoles: roles, result: 'read_only',
          }));
        }
      }
      pageToken = page.pageToken;
    } while (pageToken);
    return users;
  }

  async changeRole({ command, uid, email, role, apply }) {
    const user = await this.resolveUser({ uid, email });
    const currentRoles = managedRoles(user);
    const nextRoles = new Set(currentRoles);
    if (command === 'set-role') nextRoles.add(role);
    else if (role) nextRoles.delete(role);
    else nextRoles.clear();
    const normalizedNextRoles = [...nextRoles].sort();
    const currentRole = primaryRole(currentRoles);
    const nextRole = primaryRole(normalizedNextRoles);
    const proposal = this._report(user, {
      command,
      currentRole,
      currentRoles,
      proposedRole: nextRole,
      proposedRoles: normalizedNextRoles,
      result: apply ? 'proposed_apply' : 'dry_run',
    });
    this.audit.write(proposal);
    if (!apply) return proposal;

    if (currentRoles.includes('admin') && !normalizedNextRoles.includes('admin') && await this._isLastAdmin(user.uid)) {
      const blocked = { ...proposal, result: 'blocked_last_admin', reason: 'Refusing to remove or demote the final admin.' };
      this.audit.write(blocked);
      return blocked;
    }

    const claims = { ...(user.customClaims || {}) };
    if (normalizedNextRoles.length > 0) {
      claims.roles = Object.fromEntries(normalizedNextRoles.map((managedRole) => [managedRole, true]));
    } else {
      delete claims.roles;
    }
    // Managed writes migrate the legacy scalar to the canonical map while
    // preserving all unrelated custom claims.
    delete claims.role;
    const metadata = await this.db.collection('users').doc(user.uid).get();
    const claimsAlreadyMatch = JSON.stringify(currentRoles) === JSON.stringify(normalizedNextRoles)
      && !Object.prototype.hasOwnProperty.call(user.customClaims || {}, 'role');
    try {
      if (!claimsAlreadyMatch) await this.auth.setCustomUserClaims(user.uid, claims);
      const metadataResult = await this._syncMetadata(user.uid, nextRole, metadata);
      const result = ['synced', 'already_synced'].includes(metadataResult)
        ? (claimsAlreadyMatch ? 'noop' : 'applied')
        : 'partial_failure';
      const completed = { ...proposal, result, metadataResult };
      this.audit.write(completed);
      return completed;
    } catch (error) {
      const failed = { ...proposal, result: 'failed', error: error.message };
      this.audit.write(failed);
      throw error;
    }
  }

  async _syncMetadata(uid, nextRole, metadataSnapshot) {
    if (!metadataSnapshot.exists) return 'metadata_missing';
    try {
      const currentMetadataRole = metadataSnapshot.get('role') ?? null;
      if (currentMetadataRole === nextRole) return 'already_synced';
      if (nextRole) await metadataSnapshot.ref.update({ role: nextRole });
      else await metadataSnapshot.ref.update({ role: FieldValue.delete() });
      return 'synced';
    } catch (error) {
      return `metadata_error:${error.code || error.message}`;
    }
  }

  async _isLastAdmin(targetUid) {
    let pageToken;
    let admins = 0;
    do {
      const page = await this.auth.listUsers(1000, pageToken);
      for (const user of page.users) {
        if (managedRoles(user).includes('admin')) admins += 1;
      }
      pageToken = page.pageToken;
    } while (pageToken);
    return admins === 1;
  }

  _report(user, extra) {
    return {
      runId: this.runId,
      projectId: this.projectId,
      environment: this.environment,
      operator: this.operator,
      uid: user.uid,
      email: user.email || null,
      ...extra,
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
    const manager = new CustomClaimRoleManager({
      auth: context.auth,
      db: context.db,
      projectId: options.projectId,
      operator: options.operator,
      outputDir: options.outputDir,
      environment: context.environment,
    });
    let result;
    if (options.command === 'show-role') result = await manager.showRole(options);
    else if (options.command === 'list-privileged-users') result = await manager.listPrivilegedUsers();
    else result = await manager.changeRole({ ...options, command: options.command });
    console.log(JSON.stringify({ result, auditPath: manager.audit.path }, null, 2));
    if (result?.result === 'blocked_last_admin') process.exitCode = 2;
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
  ALLOWED_ROLES,
  managedRoles,
  CustomClaimRoleManager,
  JsonlAuditWriter,
  createAdminContext,
  parseArgs,
  runCli,
};
