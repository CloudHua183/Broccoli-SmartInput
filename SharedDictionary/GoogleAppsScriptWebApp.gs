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
    fileId: fileId,
    bytes: Utilities.newBlob(contents, "text/plain", config.description).getBytes().length,
  });
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
