#!/usr/bin/env node
'use strict';

/**
 * Backfills only missing legacy coachId fields from student_profiles.
 * This tool is intentionally independent from either Flutter application.
 */
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const admin = require('firebase-admin');
const { FieldPath, FieldValue, getFirestore } = require('firebase-admin/firestore');

const MIGRATION_VERSION = 'legacy-coach-ownership-v1';
const COLLECTIONS = [
  'bookings',
  'lesson_change_requests',
  'package_requests',
  'availabilities',
  'student_packages',
];

function parseArgs(argv) {
  const options = {
    mode: 'dry-run',
    projectId: process.env.GCLOUD_PROJECT || process.env.FIREBASE_PROJECT_ID || 'bodyhub-migration',
    pageSize: 250,
    limit: Infinity,
    errorThreshold: 0.05,
    outputDir: path.resolve(process.cwd(), 'migration-reports'),
    retryLimit: 3,
    resume: null,
    rollback: null,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    const next = () => {
      const value = argv[index + 1];
      if (!value || value.startsWith('--')) throw new Error(`${arg} requires a value.`);
      index += 1;
      return value;
    };
    if (arg === '--apply') options.mode = 'apply';
    else if (arg === '--dry-run') options.mode = 'dry-run';
    else if (arg === '--rollback') options.rollback = next();
    else if (arg === '--resume') {
      const value = argv[index + 1];
      options.resume = value && !value.startsWith('--') ? next() : 'latest';
    } else if (arg === '--project-id') options.projectId = next();
    else if (arg === '--page-size') options.pageSize = Number(next());
    else if (arg === '--limit') options.limit = Number(next());
    else if (arg === '--error-threshold') options.errorThreshold = Number(next());
    else if (arg === '--output-dir') options.outputDir = path.resolve(next());
    else if (arg === '--retry-limit') options.retryLimit = Number(next());
    else if (arg === '--help') options.help = true;
    else throw new Error(`Unknown option: ${arg}`);
  }
  if (!Number.isInteger(options.pageSize) || options.pageSize < 1 || options.pageSize > 450) {
    throw new Error('--page-size must be an integer between 1 and 450.');
  }
  if (!(options.limit > 0) && options.limit !== Infinity) throw new Error('--limit must be positive.');
  if (!(options.errorThreshold >= 0 && options.errorThreshold <= 1)) {
    throw new Error('--error-threshold must be between 0 and 1.');
  }
  return options;
}

function help() {
  return `Usage: node tool/migrate_legacy_coach_ownership.js [options]\n\n` +
    `Defaults to --dry-run. --apply is required for writes.\n\n` +
    `  --dry-run\n  --apply\n  --rollback <runId|report directory>\n` +
    `  --resume [runId|report directory]\n  --project-id <id>\n` +
    `  --page-size <1..450>\n  --limit <records>\n` +
    `  --error-threshold <0..1>\n  --output-dir <directory>\n`;
}

function iso(value = new Date()) {
  return value instanceof Date ? value.toISOString() : value.toDate().toISOString();
}

function isNonEmptyString(value) {
  return typeof value === 'string' && value.trim().length > 0;
}

function hasNonEmptyCoachId(data) {
  return isNonEmptyString(data.coachId);
}

function csv(value) {
  const text = value == null ? '' : String(value);
  return /[",\n]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
}

class ReportWriter {
  constructor(directory, { append = false } = {}) {
    this.directory = directory;
    fs.mkdirSync(directory, { recursive: true });
    this.recordsPath = path.join(directory, 'records.jsonl');
    this.rollbackPath = path.join(directory, 'rollback.jsonl');
    this.csvPath = path.join(directory, 'records.csv');
    if (!append || !fs.existsSync(this.csvPath)) {
      fs.writeFileSync(this.csvPath, 'timestamp,collection,documentId,status,reason,studentId,currentCoachId,proposedCoachId\n');
    }
  }

  record(entry) {
    const full = { timestamp: new Date().toISOString(), ...entry };
    fs.appendFileSync(this.recordsPath, `${JSON.stringify(full)}\n`);
    fs.appendFileSync(this.csvPath, [
      full.timestamp, full.collection, full.documentId, full.status, full.reason,
      full.studentId, full.currentCoachId, full.proposedCoachId,
    ].map(csv).join(',') + '\n');
  }

  rollback(entry) {
    fs.appendFileSync(this.rollbackPath, `${JSON.stringify({ timestamp: new Date().toISOString(), ...entry })}\n`);
  }

  writeJson(name, data) {
    fs.writeFileSync(path.join(this.directory, name), `${JSON.stringify(data, null, 2)}\n`);
  }
}

class LegacyCoachOwnershipMigrator {
  constructor(db, options = {}) {
    this.db = db;
    this.options = {
      mode: 'dry-run', pageSize: 250, limit: Infinity, errorThreshold: 0.05,
      outputDir: path.resolve(process.cwd(), 'migration-reports'), retryLimit: 3,
      projectId: 'bodyhub-migration', ...options,
    };
    this.runId = options.runId || `${MIGRATION_VERSION}-${new Date().toISOString().replace(/[:.]/g, '-')}-${crypto.randomUUID().slice(0, 8)}`;
    this.runDirectory = options.runDirectory || path.join(this.options.outputDir, this.runId);
    this.summary = {
      runId: this.runId,
      projectId: this.options.projectId,
      mode: this.options.mode,
      migrationVersion: MIGRATION_VERSION,
      startedAt: new Date().toISOString(),
      finishedAt: null,
      scanned: 0,
      updated: 0,
      wouldUpdate: 0,
      skipped: 0,
      conflicts: 0,
      failed: 0,
      alreadyCorrect: 0,
      haltedByErrorThreshold: false,
    };
    this.writer = new ReportWriter(this.runDirectory, { append: Boolean(options.resume) });
    this.checkpoint = this._loadCheckpoint(options.resume);
    this.beforeWrite = options.beforeWrite;
  }

  _loadCheckpoint(resume) {
    if (!resume) return { collectionIndex: 0, collection: null, lastDocumentId: null, page: 0 };
    const checkpointPath = path.join(this.runDirectory, 'checkpoint.json');
    if (!fs.existsSync(checkpointPath)) throw new Error(`Checkpoint not found: ${checkpointPath}`);
    return JSON.parse(fs.readFileSync(checkpointPath, 'utf8'));
  }

  _saveCheckpoint(checkpoint) {
    this.checkpoint = checkpoint;
    this.writer.writeJson('checkpoint.json', checkpoint);
  }

  _record(status, entry = {}) {
    const result = { status, ...entry };
    this.writer.record(result);
    if (status === 'updated') this.summary.updated += 1;
    else if (status === 'dry_run_candidate') this.summary.wouldUpdate += 1;
    else if (status === 'already_correct') this.summary.alreadyCorrect += 1;
    else if (status === 'conflict') this.summary.conflicts += 1;
    else if (status === 'failed') this.summary.failed += 1;
    else this.summary.skipped += 1;
  }

  async run() {
    for (let collectionIndex = this.checkpoint.collectionIndex; collectionIndex < COLLECTIONS.length; collectionIndex += 1) {
      const collection = COLLECTIONS[collectionIndex];
      let lastDocumentId = collectionIndex === this.checkpoint.collectionIndex
        ? this.checkpoint.lastDocumentId : null;
      let page = collectionIndex === this.checkpoint.collectionIndex ? this.checkpoint.page : 0;
      while (this.summary.scanned < this.options.limit) {
        let query = this.db.collection(collection).orderBy(FieldPath.documentId()).limit(
          Math.min(this.options.pageSize, this.options.limit - this.summary.scanned),
        );
        if (lastDocumentId) query = query.startAfter(lastDocumentId);
        const snapshot = await query.get();
        if (snapshot.empty) break;
        page += 1;
        await this._processPage(collection, snapshot.docs);
        lastDocumentId = snapshot.docs.at(-1).id;
        this._saveCheckpoint({ collectionIndex, collection, lastDocumentId, page });
        if (this._technicalFailureRate() > this.options.errorThreshold) {
          this.summary.haltedByErrorThreshold = true;
          return this._finish();
        }
        if (this.summary.scanned >= this.options.limit) return this._finish();
        if (snapshot.size < this.options.pageSize) break;
      }
      this._saveCheckpoint({ collectionIndex: collectionIndex + 1, collection, lastDocumentId: null, page: 0 });
      if (this.summary.scanned >= this.options.limit) break;
    }
    return this._finish();
  }

  _technicalFailureRate() {
    const denominator = Math.max(1, this.summary.scanned);
    return this.summary.failed / denominator;
  }

  async _processPage(collection, docs) {
    const profiles = await this._profilesFor(docs, collection);
    const lessons = collection === 'lesson_change_requests'
      ? await this._lessonsFor(docs) : new Map();
    const writer = this.options.mode === 'apply' ? this.db.bulkWriter({ throttling: false }) : null;
    if (writer) writer.onWriteError((error) => error.failedAttempts < this.options.retryLimit);
    const pendingWrites = [];
    for (const doc of docs) {
      this.summary.scanned += 1;
      const candidate = this._validate(collection, doc, profiles, lessons);
      if (candidate.status !== 'candidate') {
        this._record(candidate.status, candidate);
        continue;
      }
      if (this.options.mode === 'dry-run') {
        this._record('dry_run_candidate', candidate);
        continue;
      }
      const scheduled = await this._scheduleCandidate(doc, candidate, writer);
      if (scheduled) pendingWrites.push(scheduled);
    }
    if (writer) await writer.close();
    for (const pending of pendingWrites) {
      try {
        await pending.write;
        this.writer.rollback({ ...pending.rollbackEntry, status: 'written' });
        this._record('updated', pending.candidate);
      } catch (error) {
        this._record('failed', {
          ...pending.candidate,
          reason: 'write_failed',
          error: String(error.message || error),
        });
      }
    }
  }

  async _profilesFor(docs, collection) {
    const ids = [...new Set(docs.map((doc) => this._studentId(collection, doc)).filter(isNonEmptyString))];
    const result = new Map();
    for (let offset = 0; offset < ids.length; offset += 100) {
      const refs = ids.slice(offset, offset + 100).map((id) => this.db.collection('student_profiles').doc(id));
      const snapshots = await this.db.getAll(...refs);
      for (const snapshot of snapshots) result.set(snapshot.id, snapshot);
    }
    return result;
  }

  async _lessonsFor(docs) {
    const ids = [...new Set(docs.map((doc) => doc.get('lessonId')).filter(isNonEmptyString))];
    const result = new Map();
    for (let offset = 0; offset < ids.length; offset += 100) {
      const refs = ids.slice(offset, offset + 100).map((id) => this.db.collection('lessons').doc(id));
      const snapshots = await this.db.getAll(...refs);
      for (const snapshot of snapshots) result.set(snapshot.id, snapshot);
    }
    return result;
  }

  _studentId(collection, doc) {
    const data = doc.data();
    if (collection === 'student_packages') return isNonEmptyString(data.studentId) ? data.studentId : doc.id;
    return data.studentId;
  }

  _validate(collection, doc, profiles, lessons) {
    const data = doc.data();
    const base = {
      collection, documentId: doc.id, studentId: this._studentId(collection, doc),
      currentCoachId: data.coachId ?? null, proposedCoachId: null,
    };
    if (collection === 'student_packages' && isNonEmptyString(data.studentId) && data.studentId !== doc.id) {
      return { ...base, status: 'conflict', reason: 'student_package_document_id_mismatch' };
    }
    if (hasNonEmptyCoachId(data)) {
      const existingProfile = isNonEmptyString(base.studentId) ? profiles.get(base.studentId) : null;
      const profileCoachId = existingProfile?.exists ? existingProfile.get('coachId') : null;
      if (isNonEmptyString(profileCoachId) && profileCoachId !== data.coachId) {
        return { ...base, status: 'conflict', reason: 'existing_coach_id_differs_from_profile' };
      }
      return { ...base, status: 'already_correct', reason: 'coach_id_already_present' };
    }
    if (!isNonEmptyString(base.studentId)) return { ...base, status: 'skipped', reason: 'missing_student_id' };
    const profile = profiles.get(base.studentId);
    if (!profile?.exists) return { ...base, status: 'skipped', reason: 'student_profile_missing' };
    const profileData = profile.data();
    if (profileData.status !== 'active') return { ...base, status: 'skipped', reason: 'student_profile_not_active' };
    if (!isNonEmptyString(profileData.coachId)) return { ...base, status: 'skipped', reason: 'student_profile_coach_missing' };
    base.proposedCoachId = profileData.coachId;
    if (collection === 'lesson_change_requests') {
      const lessonId = data.lessonId;
      const lesson = isNonEmptyString(lessonId) ? lessons.get(lessonId) : null;
      if (!lesson?.exists) return { ...base, status: 'skipped', reason: 'lesson_relationship_missing' };
      const lessonData = lesson.data();
      if (lessonData.studentId !== base.studentId || lessonData.coachId !== base.proposedCoachId) {
        return { ...base, status: 'conflict', reason: 'lesson_relationship_mismatch' };
      }
    }
    return { ...base, status: 'candidate', reason: 'profile_coach_verified' };
  }

  async _scheduleCandidate(doc, candidate, writer) {
    const rollbackEntry = {
      status: 'pending_write', collection: candidate.collection, documentId: candidate.documentId,
      path: doc.ref.path, migrationCoachId: candidate.proposedCoachId,
      hadCoachIdField: Object.prototype.hasOwnProperty.call(doc.data(), 'coachId'),
      previousCoachId: doc.get('coachId') ?? null,
      sourceUpdateTime: iso(doc.updateTime),
    };
    this.writer.rollback(rollbackEntry);
    try {
      if (this.beforeWrite) await this.beforeWrite(doc, candidate);
      return {
        candidate,
        rollbackEntry,
        write: writer.update(
          doc.ref,
          { coachId: candidate.proposedCoachId },
          { lastUpdateTime: doc.updateTime },
        ),
      };
    } catch (error) {
      this._record('failed', { ...candidate, reason: 'write_failed', error: String(error.message || error) });
      return null;
    }
  }

  _finish() {
    this.summary.finishedAt = new Date().toISOString();
    this.summary.errorRate = this._technicalFailureRate();
    this.writer.writeJson('summary.json', this.summary);
    return this.summary;
  }
}

async function rollbackMigration(db, options) {
  const source = options.rollback;
  const reportDirectory = fs.existsSync(source) ? source : path.join(options.outputDir, source);
  const rollbackPath = path.join(reportDirectory, 'rollback.jsonl');
  if (!fs.existsSync(rollbackPath)) throw new Error(`Rollback report not found: ${rollbackPath}`);
  const entries = fs.readFileSync(rollbackPath, 'utf8').trim().split('\n')
    .filter(Boolean).map((line) => JSON.parse(line)).filter((entry) => entry.status === 'written');
  const report = new ReportWriter(reportDirectory, { append: true });
  const summary = { runId: path.basename(reportDirectory), mode: 'rollback', migrationVersion: MIGRATION_VERSION, startedAt: new Date().toISOString(), rolledBack: 0, skipped: 0, failed: 0 };
  for (const entry of entries) {
    const ref = db.doc(entry.path);
    const current = await ref.get();
    if (!current.exists || current.get('coachId') !== entry.migrationCoachId) {
      summary.skipped += 1;
      report.record({ collection: entry.collection, documentId: entry.documentId, status: 'rollback_skipped', reason: 'coach_id_changed_or_document_missing', studentId: null, currentCoachId: current.exists ? current.get('coachId') : null, proposedCoachId: entry.migrationCoachId });
      continue;
    }
    try {
      const writer = db.bulkWriter({ throttling: false });
      const write = writer.update(ref, {
        coachId: entry.hadCoachIdField ? entry.previousCoachId : FieldValue.delete(),
      }, { lastUpdateTime: current.updateTime });
      await writer.close();
      await write;
      summary.rolledBack += 1;
      report.record({ collection: entry.collection, documentId: entry.documentId, status: 'rolled_back', reason: 'rollback_safe_match', studentId: null, currentCoachId: entry.migrationCoachId, proposedCoachId: entry.previousCoachId });
    } catch (error) {
      summary.failed += 1;
      report.record({ collection: entry.collection, documentId: entry.documentId, status: 'rollback_failed', reason: 'write_failed', error: String(error.message || error), studentId: null, currentCoachId: entry.migrationCoachId, proposedCoachId: entry.previousCoachId });
    }
  }
  summary.finishedAt = new Date().toISOString();
  report.writeJson('rollback-summary.json', summary);
  return summary;
}

function resolveResumeDirectory(options) {
  if (!options.resume) return null;
  if (options.resume !== 'latest') return fs.existsSync(options.resume) ? path.resolve(options.resume) : path.join(options.outputDir, options.resume);
  const directories = fs.readdirSync(options.outputDir, { withFileTypes: true })
    .filter((entry) => entry.isDirectory()).map((entry) => path.join(options.outputDir, entry.name))
    .filter((directory) => fs.existsSync(path.join(directory, 'checkpoint.json')))
    .sort();
  if (!directories.length) throw new Error('No resumable migration checkpoint was found.');
  return directories.at(-1);
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) return console.log(help());
  const app = admin.initializeApp({ projectId: options.projectId });
  const db = getFirestore(app);
  if (options.rollback) {
    const summary = await rollbackMigration(db, options);
    console.log(JSON.stringify(summary, null, 2));
    return;
  }
  const resumeDirectory = resolveResumeDirectory(options);
  const migrator = new LegacyCoachOwnershipMigrator(db, {
    ...options,
    runId: resumeDirectory ? path.basename(resumeDirectory) : undefined,
    runDirectory: resumeDirectory || undefined,
  });
  const summary = await migrator.run();
  console.log(JSON.stringify(summary, null, 2));
  if (summary.haltedByErrorThreshold) process.exitCode = 2;
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error.stack || error.message || error);
    process.exitCode = 1;
  });
}

module.exports = { COLLECTIONS, LegacyCoachOwnershipMigrator, MIGRATION_VERSION, parseArgs, rollbackMigration };
