const SHARED_SECRET_PROPERTY = "SHARED_SECRET";

const TARGETS = {
  smart: {
    fileIdProperty: "SMART_MIXED_ASCII_WORDS_FILE_ID",
    description: "smart-mixed-ascii-words.txt",
    validator: validateSmartMixedASCIIWords,
  },
  user: {
    fileIdProperty: "USER_PHRASES_FILE_ID",
    description: "data.txt",
    validator: validateUserPhrases,
  },
};

function doGet(e) {
  const target = normalizeTarget(e && e.parameter && e.parameter.target);
  if (!target) {
    return jsonResponse({
      ok: true,
      message: "Broccoli SmartInput Google Apps Script Web App",
      targets: Object.keys(TARGETS),
    });
  }

  const config = TARGETS[target];
  const fileId = PropertiesService.getScriptProperties().getProperty(config.fileIdProperty);
  return jsonResponse({
    ok: true,
    target: target,
    description: config.description,
    configured: Boolean(fileId),
  });
}

function doPost(e) {
  const authError = checkSharedSecret(e);
  if (authError) {
    return jsonResponse({ ok: false, error: authError });
  }

  const target = normalizeTarget(e && e.parameter && e.parameter.target);
  if (!target) {
    return jsonResponse({ ok: false, error: "Missing or invalid target parameter." });
  }

  const config = TARGETS[target];
  const fileId = PropertiesService.getScriptProperties().getProperty(config.fileIdProperty);
  if (!fileId) {
    return jsonResponse({ ok: false, error: `Missing script property: ${config.fileIdProperty}` });
  }

  const contents = normalizeContent(e && e.postData && e.postData.contents);
  const validationError = config.validator(contents);
  if (validationError) {
    return jsonResponse({ ok: false, error: validationError });
  }

  const lock = LockService.getScriptLock();
  lock.waitLock(30000);
  try {
    DriveApp.getFileById(fileId).setContent(contents);
  } finally {
    lock.releaseLock();
  }

  return jsonResponse({
    ok: true,
    target: target,
    bytes: Utilities.newBlob(contents, "text/plain", config.description).getBytes().length,
  });
}

// The deployment has to allow anonymous access, because the input method
// uploads without an OAuth token. Anyone who learns the deployment URL can
// therefore reach doPost, and setContent() replaces the whole dictionary. A
// shared secret kept in Script Properties (and in the local, git-ignored
// patch-source.json) is what actually gates writes.
//
// This fails closed: if SHARED_SECRET is not set on the script, every upload
// is rejected rather than silently accepted.
function checkSharedSecret(e) {
  const expected = PropertiesService.getScriptProperties().getProperty(SHARED_SECRET_PROPERTY);
  if (!expected) {
    return `Missing script property: ${SHARED_SECRET_PROPERTY}. Uploads are disabled until it is set.`;
  }
  const provided = e && e.parameter && e.parameter.secret;
  if (!provided || !constantTimeEquals(String(provided), String(expected))) {
    return "Unauthorized.";
  }
  return null;
}

// Compare without leaking the position of the first differing byte through
// timing. Apps Script has no crypto.timingSafeEqual, so do it by hand.
function constantTimeEquals(a, b) {
  if (a.length !== b.length) {
    return false;
  }
  let diff = 0;
  for (let i = 0; i < a.length; i += 1) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

function normalizeTarget(rawTarget) {
  if (!rawTarget) {
    return null;
  }
  const target = String(rawTarget).trim().toLowerCase();
  return Object.prototype.hasOwnProperty.call(TARGETS, target) ? target : null;
}

function normalizeContent(rawContent) {
  return String(rawContent || "").replace(/\r\n?/g, "\n");
}

function validateSmartMixedASCIIWords(contents) {
  const lines = contents.split("\n");
  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i].trim();
    if (!line || line.startsWith("#")) {
      continue;
    }
    if (!/^[A-Za-z0-9]+$/.test(line)) {
      return `Invalid smart mixed ASCII word on line ${i + 1}: only ASCII letters and digits are allowed.`;
    }
  }
  return null;
}

function validateUserPhrases(contents) {
  const lines = contents.split("\n");
  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i].trim();
    if (!line || line.startsWith("#")) {
      continue;
    }
    const parts = line.split(/\s+/);
    if (parts.length < 2) {
      return `Invalid user phrase on line ${i + 1}: expected at least phrase and reading.`;
    }
  }
  return null;
}

function jsonResponse(payload) {
  return ContentService.createTextOutput(JSON.stringify(payload, null, 2)).setMimeType(
    ContentService.MimeType.JSON
  );
}
