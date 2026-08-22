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
): Promise<PreparedMedia> {
  if (file.size <= 0) throw new Error("الملف فارغ");
  if (file.size > MAX_UPLOAD_BYTES) throw new Error("حجم الملف أكبر من 50 MB");
  const isVideo = file.type.startsWith("video/");
  const isImage = file.type.startsWith("image/");
  if (!isVideo && !isImage) throw new Error("استخدم صورة أو فيديو فقط");
  if (kind === "frame" && !isImage) throw new Error("الإطار يجب أن يكون صورة PNG/WebP/JPG");

  if (isVideo) {
    const meta = await readVideoMetadata(file);
    const seconds = meta.durationMs / 1000;
    if (kind === "entry_effect" && seconds > 5.5) throw new Error("الدخلة أطول من 5 ثوانٍ. قصّرها قبل الاعتماد");
    if (kind === "room_background" && seconds > 20) throw new Error("فيديو الخلفية أطول من 20 ثانية؛ استخدم Loop أقصر وأخف");
    const thumbnail = customThumbnail ? (await imageToWebp(customThumbnail, 720, 0.9)).blob : await makeVideoThumbnail(file);
    const needsProcessor = kind === "entry_effect" && removeBackground;
    return {
      original: file,
      processed: file,
      processedName: `media.${extensionForMime(file.type)}`,
      thumbnail,
      width: meta.width,
      height: meta.height,
      durationMs: meta.durationMs,
      mediaType: "video",
      mimeType: file.type || "video/mp4",
      processingStatus: needsProcessor ? "needs_processor" : "ready",
      processingError: needsProcessor
        ? "إزالة خلفية الفيديو تحتاج عامل معالجة الفيديو؛ تم حفظ الأصل والمعاينة ولن يُنشر العنصر قبل اكتمال المعالجة."
        : null,
      metadata: { validated_in_browser: true, original_name: file.name },
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
