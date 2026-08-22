import { supabase } from "@/integrations/supabase/client";

export type MediaAssetKind = "entry_effect" | "frame" | "room_background";
export type MediaProcessingStatus = "ready" | "needs_processor" | "failed";

export type PreparedMedia = {
  original: File;
  processed: Blob;
  processedName: string;
  thumbnail: Blob;
  width: number;
  height: number;
  durationMs: number | null;
  mediaType: "image" | "video";
  mimeType: string;
  processingStatus: MediaProcessingStatus;
  processingError: string | null;
  metadata: Record<string, unknown>;
};

export type UploadedMedia = PreparedMedia & {
  mediaUrl: string;
  originalUrl: string;
  thumbnailUrl: string;
  storagePaths: string[];
};

const BUCKET = "yamo-media-assets";
const MAX_UPLOAD_BYTES = 50 * 1024 * 1024;

function extensionForMime(type: string) {
  if (type.includes("webp")) return "webp";
  if (type.includes("png")) return "png";
  if (type.includes("jpeg") || type.includes("jpg")) return "jpg";
  if (type.includes("webm")) return "webm";
  if (type.includes("quicktime")) return "mov";
  return "mp4";
}

function sanitizeName(value: string) {
  return value.replace(/[^a-zA-Z0-9._-]+/g, "-").replace(/-+/g, "-").slice(-80);
}

function blobToFile(blob: Blob, name: string) {
  return new File([blob], name, { type: blob.type || "application/octet-stream" });
}

async function loadImage(source: Blob): Promise<HTMLImageElement> {
  const url = URL.createObjectURL(source);
  try {
    const img = new Image();
    img.decoding = "async";
    img.src = url;
    await img.decode();
    return img;
  } finally {
    // revoke after decode is safe in modern browsers because pixels are resident.
    URL.revokeObjectURL(url);
  }
}

async function imageToWebp(source: Blob, maxSide = 2048, quality = 0.92): Promise<{ blob: Blob; width: number; height: number }> {
  const img = await loadImage(source);
  const scale = Math.min(1, maxSide / Math.max(img.naturalWidth, img.naturalHeight));
  const width = Math.max(1, Math.round(img.naturalWidth * scale));
  const height = Math.max(1, Math.round(img.naturalHeight * scale));
  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  const ctx = canvas.getContext("2d", { willReadFrequently: true });
  if (!ctx) throw new Error("تعذر تجهيز الصورة");
  ctx.clearRect(0, 0, width, height);
  ctx.drawImage(img, 0, 0, width, height);
  const blob = await new Promise<Blob>((resolve, reject) =>
    canvas.toBlob((value) => (value ? resolve(value) : reject(new Error("تعذر ضغط الصورة"))), "image/webp", quality),
  );
  return { blob, width, height };
}

function colorDistance(r: number, g: number, b: number, bg: [number, number, number]) {
  const dr = r - bg[0];
  const dg = g - bg[1];
  const db = b - bg[2];
  return Math.sqrt(dr * dr + dg * dg + db * db);
}

/**
 * Conservative edge-connected background cleanup for still frames/images.
 * Only pixels connected to the outside border and close to the sampled corner
 * color are removed, so colors inside the actual artwork are not blindly cut.
 */
async function removeEdgeBackground(source: Blob, removeMatchingInterior = false): Promise<{ blob: Blob; width: number; height: number }> {
  const normalized = await imageToWebp(source, 2048, 0.96);
  const img = await loadImage(normalized.blob);
  const width = normalized.width;
  const height = normalized.height;
  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  const ctx = canvas.getContext("2d", { willReadFrequently: true });
  if (!ctx) throw new Error("تعذر تحليل حواف الصورة");
  ctx.drawImage(img, 0, 0, width, height);
  const imageData = ctx.getImageData(0, 0, width, height);
  const data = imageData.data;

  const samplePoints = [
    [0, 0], [width - 1, 0], [0, height - 1], [width - 1, height - 1],
    [Math.floor(width / 2), 0], [Math.floor(width / 2), height - 1],
    [0, Math.floor(height / 2)], [width - 1, Math.floor(height / 2)],
  ];
  let sr = 0; let sg = 0; let sb = 0; let count = 0;
  for (const [x, y] of samplePoints) {
    const i = (y * width + x) * 4;
    if (data[i + 3] < 20) continue;
    sr += data[i]; sg += data[i + 1]; sb += data[i + 2]; count += 1;
  }
  if (count === 0) {
    return { blob: normalized.blob, width, height };
  }
  const bg: [number, number, number] = [sr / count, sg / count, sb / count];
  const hard = 42;
  const feather = 34;
  const visited = new Uint8Array(width * height);
  const queue = new Int32Array(width * height);
  let head = 0; let tail = 0;

  const enqueue = (x: number, y: number) => {
    if (x < 0 || y < 0 || x >= width || y >= height) return;
    const index = y * width + x;
    if (visited[index]) return;
    const p = index * 4;
    const d = colorDistance(data[p], data[p + 1], data[p + 2], bg);
    if (d > hard + feather || data[p + 3] === 0) return;
    visited[index] = 1;
    queue[tail++] = index;
  };

  for (let x = 0; x < width; x += 1) { enqueue(x, 0); enqueue(x, height - 1); }
  for (let y = 0; y < height; y += 1) { enqueue(0, y); enqueue(width - 1, y); }

  while (head < tail) {
    const index = queue[head++];
    const x = index % width;
    const y = Math.floor(index / width);
    const p = index * 4;
    const d = colorDistance(data[p], data[p + 1], data[p + 2], bg);
    if (d <= hard) data[p + 3] = 0;
    else data[p + 3] = Math.min(data[p + 3], Math.round(((d - hard) / feather) * 255));
    enqueue(x + 1, y); enqueue(x - 1, y); enqueue(x, y + 1); enqueue(x, y - 1);
  }

  // Frames often have the same flat background inside the closed ring as
  // outside it. Remove only very-close matches globally so the center becomes
  // transparent without applying a destructive full-image chroma key.
  if (removeMatchingInterior) {
    const innerHard = 28;
    const innerFeather = 18;
    for (let index = 0; index < width * height; index += 1) {
      const p = index * 4;
      if (data[p + 3] === 0) continue;
      const d = colorDistance(data[p], data[p + 1], data[p + 2], bg);
      if (d <= innerHard) data[p + 3] = 0;
      else if (d < innerHard + innerFeather) data[p + 3] = Math.min(data[p + 3], Math.round(((d - innerHard) / innerFeather) * 255));
    }
  }

  ctx.putImageData(imageData, 0, 0);
  const blob = await new Promise<Blob>((resolve, reject) =>
    canvas.toBlob((value) => (value ? resolve(value) : reject(new Error("تعذر حفظ الشفافية"))), "image/webp", 0.95),
  );
  return { blob, width, height };
}

async function makeImageThumbnail(source: Blob, framePreview: boolean) {
  const img = await loadImage(source);
  const size = 480;
  const canvas = document.createElement("canvas");
  canvas.width = size;
  canvas.height = size;
  const ctx = canvas.getContext("2d");
  if (!ctx) throw new Error("تعذر إنشاء الصورة المصغرة");

  if (framePreview) {
    const gradient = ctx.createLinearGradient(0, 0, size, size);
    gradient.addColorStop(0, "#5b21b6");
    gradient.addColorStop(1, "#f97316");
    ctx.fillStyle = gradient;
    ctx.fillRect(0, 0, size, size);
    ctx.fillStyle = "rgba(255,255,255,.16)";
    ctx.beginPath();
    ctx.arc(size / 2, size / 2, size * 0.26, 0, Math.PI * 2);
    ctx.fill();
  } else {
    ctx.fillStyle = "#111827";
    ctx.fillRect(0, 0, size, size);
  }

  const scale = Math.min(size / img.naturalWidth, size / img.naturalHeight);
  const w = img.naturalWidth * scale;
  const h = img.naturalHeight * scale;
  ctx.drawImage(img, (size - w) / 2, (size - h) / 2, w, h);
  return new Promise<Blob>((resolve, reject) =>
    canvas.toBlob((value) => (value ? resolve(value) : reject(new Error("تعذر إنشاء الصورة المصغرة"))), "image/webp", 0.9),
  );
}

async function readVideoMetadata(file: File) {
  const url = URL.createObjectURL(file);
  try {
    const video = document.createElement("video");
    video.preload = "metadata";
    video.muted = true;
    video.playsInline = true;
    video.src = url;
    await new Promise<void>((resolve, reject) => {
      video.onloadedmetadata = () => resolve();
      video.onerror = () => reject(new Error("ملف الفيديو غير قابل للقراءة"));
    });
    return {
      width: video.videoWidth,
      height: video.videoHeight,
      durationMs: Math.round(video.duration * 1000),
    };
  } finally {
    URL.revokeObjectURL(url);
  }
}



type CapturableVideo = HTMLVideoElement & {
  captureStream?: () => MediaStream;
  mozCaptureStream?: () => MediaStream;
};

function chooseRecorderMimeType(includeAudio: boolean) {
  const candidates = includeAudio
    ? ["video/webm;codecs=vp9,opus", "video/webm;codecs=vp8,opus", "video/webm"]
    : ["video/webm;codecs=vp9", "video/webm;codecs=vp8", "video/webm"];
  return candidates.find((type) => typeof MediaRecorder !== "undefined" && MediaRecorder.isTypeSupported(type)) ?? "video/webm";
}

async function trimVideoClip(
  file: File,
  maxDurationMs: number,
  includeAudio: boolean,
): Promise<{ blob: Blob; durationMs: number; mimeType: string }> {
  if (typeof MediaRecorder === "undefined") {
    throw new Error("المتصفح الحالي لا يدعم القص التلقائي للفيديو. افتح لوحة التحكم بآخر إصدار من Chrome أو Edge");
  }

  const url = URL.createObjectURL(file);
  const video = document.createElement("video") as CapturableVideo;
  video.preload = "auto";
  video.playsInline = true;
  video.src = url;
  // Keep processing silent and autoplay-safe. In Chromium captureStream keeps
  // the selected source audio track available to MediaRecorder even while the
  // local media element itself is muted.
  video.muted = true;
  video.volume = 0;

  try {
    await new Promise<void>((resolve, reject) => {
      video.onloadedmetadata = () => resolve();
      video.onerror = () => reject(new Error("تعذر قراءة الفيديو للقص التلقائي"));
    });
    if (!Number.isFinite(video.duration) || video.duration <= 0) throw new Error("مدة الفيديو غير صالحة");

    const capture = video.captureStream ?? video.mozCaptureStream;
    if (!capture) throw new Error("المتصفح الحالي لا يدعم القص التلقائي للفيديو. استخدم Chrome أو Edge");

    video.currentTime = 0;
    await new Promise<void>((resolve, reject) => {
      if (video.readyState >= 2) return resolve();
      video.oncanplay = () => resolve();
      video.onerror = () => reject(new Error("تعذر تجهيز الفيديو للقص التلقائي"));
    });

    const sourceStream = capture.call(video);
    if (!includeAudio) {
      sourceStream.getAudioTracks().forEach((track) => {
        sourceStream.removeTrack(track);
        track.stop();
      });
    }

    const mimeType = chooseRecorderMimeType(includeAudio);
    const chunks: BlobPart[] = [];
    const recorder = new MediaRecorder(sourceStream, {
      mimeType,
      videoBitsPerSecond: 5_000_000,
      ...(includeAudio ? { audioBitsPerSecond: 128_000 } : {}),
    });

    const done = new Promise<Blob>((resolve, reject) => {
      recorder.ondataavailable = (event) => { if (event.data.size > 0) chunks.push(event.data); };
      recorder.onerror = () => reject(new Error("فشل القص التلقائي للفيديو"));
      recorder.onstop = () => {
        const blob = new Blob(chunks, { type: recorder.mimeType || mimeType });
        if (!blob.size) reject(new Error("النسخة المقصوصة من الفيديو فارغة"));
        else resolve(blob);
      };
    });

    recorder.start(250);
    await video.play();
    const durationToKeep = Math.min(maxDurationMs, Math.round(video.duration * 1000));
    await new Promise<void>((resolve) => {
      let finished = false;
      const finish = () => {
        if (finished) return;
        finished = true;
        video.pause();
        if (recorder.state !== "inactive") recorder.stop();
        resolve();
      };
      const timer = window.setTimeout(finish, durationToKeep + 120);
      video.onended = () => { window.clearTimeout(timer); finish(); };
    });

    const blob = await done;
    sourceStream.getTracks().forEach((track) => track.stop());
    return { blob, durationMs: durationToKeep, mimeType: blob.type || mimeType };
  } finally {
    video.pause();
    video.removeAttribute("src");
    video.load();
    URL.revokeObjectURL(url);
  }
}

async function makeVideoThumbnail(file: File) {
  const url = URL.createObjectURL(file);
  try {
    const video = document.createElement("video");
    video.preload = "auto";
    video.muted = true;
    video.playsInline = true;
    video.src = url;
    await new Promise<void>((resolve, reject) => {
      video.onloadedmetadata = () => resolve();
      video.onerror = () => reject(new Error("تعذر قراءة الفيديو لإنشاء المعاينة"));
    });
    const target = Math.min(Math.max(video.duration * 0.2, 0.05), Math.max(video.duration - 0.05, 0.05));
    video.currentTime = target;
    await new Promise<void>((resolve) => { video.onseeked = () => resolve(); });

    const size = 480;
    const canvas = document.createElement("canvas");
    canvas.width = size;
    canvas.height = size;
    const ctx = canvas.getContext("2d");
    if (!ctx) throw new Error("تعذر إنشاء معاينة الفيديو");
    ctx.fillStyle = "#111827";
    ctx.fillRect(0, 0, size, size);
    const scale = Math.min(size / video.videoWidth, size / video.videoHeight);
    const w = video.videoWidth * scale;
    const h = video.videoHeight * scale;
    ctx.drawImage(video, (size - w) / 2, (size - h) / 2, w, h);
    return await new Promise<Blob>((resolve, reject) =>
      canvas.toBlob((value) => (value ? resolve(value) : reject(new Error("تعذر إنشاء معاينة الفيديو"))), "image/webp", 0.88),
    );
  } finally {
    URL.revokeObjectURL(url);
  }
}

export async function prepareMediaAsset(
  file: File,
  kind: MediaAssetKind,
  removeBackground: boolean,
  customThumbnail?: File | null,
  audioEnabled = false,
): Promise<PreparedMedia> {
  if (file.size <= 0) throw new Error("الملف فارغ");
  if (file.size > MAX_UPLOAD_BYTES) throw new Error("حجم الملف أكبر من 50 MB");
  const isVideo = file.type.startsWith("video/");
  const isImage = file.type.startsWith("image/");
  if (!isVideo && !isImage) throw new Error("استخدم صورة أو فيديو فقط");
  if (kind === "frame" && !isImage) throw new Error("الإطار يجب أن يكون صورة PNG/WebP/JPG");

  if (isVideo) {
    const meta = await readVideoMetadata(file);
    const maxDurationMs = kind === "entry_effect" ? 20_000 : kind === "room_background" ? 5_000 : meta.durationMs;
    const shouldTrim = meta.durationMs > maxDurationMs + 150;
    const shouldTranscode = shouldTrim || kind === "room_background" || (kind === "entry_effect" && !audioEnabled);
    let processed: Blob | File = file;
    let processedDurationMs = meta.durationMs;
    let processedMimeType = file.type || "video/mp4";

    if (shouldTranscode) {
      const trimmed = await trimVideoClip(file, maxDurationMs, kind === "entry_effect" && audioEnabled);
      processed = trimmed.blob;
      processedDurationMs = trimmed.durationMs;
      processedMimeType = trimmed.mimeType;
    }

    const processedFile = processed instanceof File
      ? processed
      : blobToFile(processed, `media.${extensionForMime(processedMimeType)}`);
    const thumbnail = customThumbnail
      ? (await imageToWebp(customThumbnail, 720, 0.9)).blob
      : await makeVideoThumbnail(processedFile);
    const needsProcessor = kind === "entry_effect" && removeBackground;
    return {
      original: file,
      processed,
      processedName: `media.${extensionForMime(processedMimeType)}`,
      thumbnail,
      width: meta.width,
      height: meta.height,
      durationMs: processedDurationMs,
      mediaType: "video",
      mimeType: processedMimeType,
      processingStatus: needsProcessor ? "needs_processor" : "ready",
      processingError: needsProcessor
        ? "تم القص التلقائي عند الحاجة، لكن إزالة خلفية فيديو الدخلة تحتاج معالج الفيديو المتقدم قبل النشر."
        : null,
      metadata: {
        validated_in_browser: true,
        original_name: file.name,
        original_duration_ms: meta.durationMs,
        max_duration_ms: maxDurationMs,
        auto_trimmed: shouldTrim,
        auto_transcoded: shouldTranscode,
        trimmed_duration_ms: shouldTrim ? processedDurationMs : null,
        room_loop: kind === "room_background",
        audio_requested: kind === "entry_effect" && audioEnabled,
        audio_removed_automatically: kind === "room_background" || (kind === "entry_effect" && !audioEnabled),
      },
    };
  }

  const processed = removeBackground && kind !== "room_background"
    ? await removeEdgeBackground(file, kind === "frame")
    : await imageToWebp(file, kind === "room_background" ? 2160 : 2048, 0.94);
  const thumbnail = customThumbnail
    ? (await imageToWebp(customThumbnail, 720, 0.9)).blob
    : await makeImageThumbnail(processed.blob, kind === "frame");
  return {
    original: file,
    processed: processed.blob,
    processedName: "media.webp",
    thumbnail,
    width: processed.width,
    height: processed.height,
    durationMs: null,
    mediaType: "image",
    mimeType: "image/webp",
    processingStatus: "ready",
    processingError: null,
    metadata: {
      validated_in_browser: true,
      original_name: file.name,
      edge_background_cleanup: removeBackground && kind !== "room_background",
    },
  };
}

async function uploadOne(path: string, body: Blob | File, contentType: string) {
  const { error } = await supabase.storage.from(BUCKET).upload(path, body, {
    cacheControl: "31536000",
    contentType,
    upsert: false,
  });
  if (error) throw error;
  return supabase.storage.from(BUCKET).getPublicUrl(path).data.publicUrl;
}

export async function uploadPreparedMedia(prepared: PreparedMedia, kind: MediaAssetKind): Promise<UploadedMedia> {
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const id = crypto.randomUUID();
  const root = `${kind}/${stamp}-${id}`;
  const originalExt = extensionForMime(prepared.original.type || prepared.mimeType);
  const originalPath = `${root}/original-${sanitizeName(prepared.original.name || `source.${originalExt}`)}`;
  const processedPath = `${root}/${prepared.processedName}`;
  const thumbPath = `${root}/thumbnail.webp`;
  const uploaded: string[] = [];
  try {
    const originalUrl = await uploadOne(originalPath, prepared.original, prepared.original.type || "application/octet-stream");
    uploaded.push(originalPath);
    let mediaUrl = originalUrl;
    if (prepared.processed !== prepared.original) {
      mediaUrl = await uploadOne(processedPath, prepared.processed, prepared.mimeType);
      uploaded.push(processedPath);
    }
    const thumbnailUrl = await uploadOne(thumbPath, prepared.thumbnail, "image/webp");
    uploaded.push(thumbPath);
    return { ...prepared, originalUrl, mediaUrl, thumbnailUrl, storagePaths: uploaded };
  } catch (error) {
    if (uploaded.length) await supabase.storage.from(BUCKET).remove(uploaded).catch(() => undefined);
    throw error;
  }
}

export async function removeUploadedMedia(paths: string[]) {
  if (!paths.length) return;
  const { error } = await supabase.storage.from(BUCKET).remove(paths);
  if (error) throw error;
}

export function formatBytes(value: number | null | undefined) {
  const bytes = Number(value ?? 0);
  if (!Number.isFinite(bytes) || bytes <= 0) return "—";
  const units = ["B", "KB", "MB", "GB"];
  let n = bytes;
  let u = 0;
  while (n >= 1024 && u < units.length - 1) { n /= 1024; u += 1; }
  return `${n >= 10 || u === 0 ? n.toFixed(0) : n.toFixed(1)} ${units[u]}`;
}

export function publicFileName(file: File | null) {
  return file ? sanitizeName(file.name) : "لم يتم اختيار ملف";
}


export type AdvancedProcessorJob = {
  accepted: boolean;
  jobId?: string;
  status?: string;
  message?: string;
};

export function advancedVideoProcessorUrl() {
  const saved = typeof window !== "undefined" ? window.localStorage.getItem("yamo_media_processor_url") : null;
  return String(saved || import.meta.env.VITE_YAMO_MEDIA_PROCESSOR_URL || "").trim().replace(/\/+$/, "");
}

export function setAdvancedVideoProcessorUrl(value: string) {
  if (typeof window === "undefined") return;
  const clean = value.trim().replace(/\/+$/, "");
  if (clean) window.localStorage.setItem("yamo_media_processor_url", clean);
  else window.localStorage.removeItem("yamo_media_processor_url");
}

export function advancedVideoProcessorConfigured() {
  return advancedVideoProcessorUrl().length > 0;
}

export async function startAdvancedEntryVideoProcessing(input: {
  assetKey: string;
  sourceUrl: string;
  originalUrl: string;
  thumbnailUrl?: string | null;
  audioEnabled: boolean;
  enabledAfterProcessing: boolean;
  quality: string;
  storagePaths: string[];
  maxDurationMs?: number;
}) {
  const baseUrl = advancedVideoProcessorUrl();
  if (!baseUrl) throw new Error("معالج فيديو الدخلات غير مربوط بعد. أضف VITE_YAMO_MEDIA_PROCESSOR_URL ثم أعد النشر.");
  const { data: { session }, error } = await supabase.auth.getSession();
  if (error) throw error;
  const token = session?.access_token;
  if (!token) throw new Error("انتهت جلسة لوحة التحكم. سجّل الدخول مرة أخرى.");

  const response = await fetch(`${baseUrl}/v1/process-entry`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify({
      asset_key: input.assetKey,
      source_url: input.sourceUrl,
      original_url: input.originalUrl,
      thumbnail_url: input.thumbnailUrl ?? null,
      audio_enabled: input.audioEnabled,
      enabled_after_processing: input.enabledAfterProcessing,
      quality: input.quality,
      storage_paths: input.storagePaths,
      max_duration_ms: Math.min(Math.max(input.maxDurationMs ?? 20_000, 1_000), 20_000),
    }),
  });
  const payload = await response.json().catch(() => ({})) as AdvancedProcessorJob & { detail?: string };
  if (!response.ok) throw new Error(payload.detail || payload.message || `فشل تشغيل معالج الفيديو (${response.status})`);
  if (!payload.accepted) throw new Error(payload.message || "معالج الفيديو لم يقبل المهمة");
  return payload;
}
