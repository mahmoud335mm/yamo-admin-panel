from __future__ import annotations

import asyncio
import json
import os
import shutil
import subprocess
import tempfile
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.parse import quote

import cv2
import httpx
import numpy as np
from fastapi import BackgroundTasks, FastAPI, Header, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field, HttpUrl
from PIL import Image, ImageDraw
from rembg import new_session, remove

APP_NAME = "Yamo Advanced Entry Processor"
BUCKET = "yamo-media-assets"
SUPABASE_URL = os.getenv("SUPABASE_URL", "").rstrip("/")
SUPABASE_ANON_KEY = os.getenv("SUPABASE_ANON_KEY", "")
MODEL_NAME = os.getenv("REMBG_MODEL", "u2net")
MAX_CONCURRENT_JOBS = max(1, int(os.getenv("MAX_CONCURRENT_JOBS", "1")))
MAX_DOWNLOAD_BYTES = int(os.getenv("MAX_DOWNLOAD_BYTES", str(60 * 1024 * 1024)))
OUTPUT_FPS = max(10, min(20, int(os.getenv("OUTPUT_FPS", "15"))))
MAX_FRAME_SIDE = max(480, min(960, int(os.getenv("MAX_FRAME_SIDE", "720"))))

if not SUPABASE_URL or not SUPABASE_ANON_KEY:
    # Fail loudly at startup in real deployments, but keep module importable for syntax checks.
    CONFIG_ERROR = "SUPABASE_URL and SUPABASE_ANON_KEY are required"
else:
    CONFIG_ERROR = ""

origins_env = os.getenv("ALLOWED_ORIGINS", "*")
allowed_origins = [x.strip() for x in origins_env.split(",") if x.strip()] or ["*"]

app = FastAPI(title=APP_NAME, version="1.0.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_credentials=False,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type"],
)

_job_semaphore = asyncio.Semaphore(MAX_CONCURRENT_JOBS)
_jobs: dict[str, dict[str, Any]] = {}
_session = None
_session_lock = asyncio.Lock()


class EntryProcessRequest(BaseModel):
    asset_key: str = Field(min_length=3, max_length=64)
    source_url: HttpUrl
    original_url: HttpUrl
    thumbnail_url: HttpUrl | None = None
    audio_enabled: bool = False
    enabled_after_processing: bool = True
    quality: str = "auto"
    storage_paths: list[str] = Field(default_factory=list)
    max_duration_ms: int = Field(default=20_000, ge=1_000, le=20_000)


@dataclass
class ProcessResult:
    animation: Path
    audio: Path | None
    thumbnail: Path
    width: int
    height: int
    duration_ms: int
    file_size: int
    fps: int
    frame_count: int


async def get_rembg_session():
    global _session
    if _session is not None:
        return _session
    async with _session_lock:
        if _session is None:
            # Loading the ONNX model is expensive, so keep one session hot.
            try:
                _session = await asyncio.to_thread(new_session, MODEL_NAME)
            except Exception:
                if MODEL_NAME != "u2net":
                    _session = await asyncio.to_thread(new_session, "u2net")
                else:
                    raise
    return _session


def auth_headers(token: str) -> dict[str, str]:
    return {
        "apikey": SUPABASE_ANON_KEY,
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }


async def verify_catalog_admin(token: str) -> None:
    if CONFIG_ERROR:
        raise HTTPException(status_code=500, detail=CONFIG_ERROR)
    async with httpx.AsyncClient(timeout=20) as client:
        response = await client.post(
            f"{SUPABASE_URL}/rest/v1/rpc/yamo_admin_has_permission",
            headers=auth_headers(token),
            json={"p_permission": "catalog.manage"},
        )
        if response.status_code >= 400:
            raise HTTPException(status_code=401, detail="invalid_admin_session")
        try:
            allowed = bool(response.json())
        except Exception as exc:
            raise HTTPException(status_code=401, detail="invalid_admin_session") from exc
        if not allowed:
            raise HTTPException(status_code=403, detail="catalog_manage_required")


async def download_source(url: str, destination: Path) -> None:
    total = 0
    async with httpx.AsyncClient(timeout=httpx.Timeout(120.0, connect=20.0), follow_redirects=True) as client:
        async with client.stream("GET", url) as response:
            response.raise_for_status()
            with destination.open("wb") as handle:
                async for chunk in response.aiter_bytes(1024 * 1024):
                    total += len(chunk)
                    if total > MAX_DOWNLOAD_BYTES:
                        raise RuntimeError("source_file_too_large")
                    handle.write(chunk)
    if total <= 0:
        raise RuntimeError("empty_source_file")


def run_command(command: list[str], cwd: Path | None = None) -> None:
    process = subprocess.run(
        command,
        cwd=str(cwd) if cwd else None,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if process.returncode != 0:
        error = process.stderr.strip().splitlines()[-12:]
        raise RuntimeError("ffmpeg_failed: " + " | ".join(error))


def probe_video(path: Path) -> dict[str, float]:
    cmd = [
        "ffprobe", "-v", "error", "-select_streams", "v:0",
        "-show_entries", "stream=width,height,r_frame_rate:format=duration",
        "-of", "json", str(path),
    ]
    process = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if process.returncode != 0:
        raise RuntimeError("invalid_video")
    data = json.loads(process.stdout or "{}")
    streams = data.get("streams") or []
    if not streams:
        raise RuntimeError("video_stream_missing")
    stream = streams[0]
    rate = str(stream.get("r_frame_rate") or "0/1")
    try:
        a, b = rate.split("/", 1)
        fps = float(a) / max(float(b), 1.0)
    except Exception:
        fps = 25.0
    return {
        "width": float(stream.get("width") or 0),
        "height": float(stream.get("height") or 0),
        "fps": fps if fps > 0 else 25.0,
        "duration": float((data.get("format") or {}).get("duration") or 0),
    }


def resize_frame(frame: np.ndarray, max_side: int) -> np.ndarray:
    h, w = frame.shape[:2]
    scale = min(1.0, max_side / max(h, w))
    if scale >= 0.999:
        return frame
    return cv2.resize(frame, (max(1, round(w * scale)), max(1, round(h * scale))), interpolation=cv2.INTER_AREA)


def soften_mask(mask: np.ndarray, previous: np.ndarray | None) -> np.ndarray:
    if mask.ndim == 3:
        mask = cv2.cvtColor(mask, cv2.COLOR_BGR2GRAY)
    mask = mask.astype(np.float32)
    if mask.max() <= 1.5:
        mask *= 255.0
    # A small dilation preserves glow/hair/particle edges that would otherwise be cut.
    mask = cv2.dilate(mask.astype(np.uint8), np.ones((3, 3), np.uint8), iterations=1).astype(np.float32)
    mask = cv2.GaussianBlur(mask, (0, 0), sigmaX=1.2, sigmaY=1.2)
    if previous is not None and previous.shape == mask.shape:
        mask = mask * 0.72 + previous * 0.28
    return np.clip(mask, 0, 255).astype(np.uint8)


def bbox_from_mask(mask: np.ndarray) -> tuple[int, int, int, int] | None:
    ys, xs = np.where(mask > 18)
    if len(xs) == 0 or len(ys) == 0:
        return None
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def union_bbox(current: tuple[int, int, int, int] | None, new: tuple[int, int, int, int] | None):
    if new is None:
        return current
    if current is None:
        return new
    return min(current[0], new[0]), min(current[1], new[1]), max(current[2], new[2]), max(current[3], new[3])


def padded_bbox(box: tuple[int, int, int, int], width: int, height: int):
    x1, y1, x2, y2 = box
    pad_x = max(10, int((x2 - x1) * 0.08))
    pad_y = max(10, int((y2 - y1) * 0.08))
    return max(0, x1 - pad_x), max(0, y1 - pad_y), min(width, x2 + pad_x), min(height, y2 + pad_y)


def make_checker_thumbnail(frame_path: Path, output: Path) -> None:
    image = Image.open(frame_path).convert("RGBA")
    canvas = Image.new("RGBA", (640, 640), (17, 24, 39, 255))
    draw = ImageDraw.Draw(canvas)
    tile = 40
    c1 = (17, 24, 39, 255)
    c2 = (31, 41, 55, 255)
    for y in range(0, 640, tile):
        for x in range(0, 640, tile):
            draw.rectangle((x, y, x + tile, y + tile), fill=c1 if ((x // tile + y // tile) % 2 == 0) else c2)
    image.thumbnail((590, 590), Image.Resampling.LANCZOS)
    canvas.alpha_composite(image, ((640 - image.width) // 2, (640 - image.height) // 2))
    canvas.convert("RGB").save(output, "WEBP", quality=88, method=6)


def process_video_sync(source: Path, work: Path, max_duration_ms: int, keep_audio: bool, session: Any) -> ProcessResult:
    meta = probe_video(source)
    source_fps = max(1.0, min(meta["fps"], 60.0))
    target_fps = max(10, min(OUTPUT_FPS, round(source_fps)))
    duration_ms = int(min(max_duration_ms, max(1000.0, meta["duration"] * 1000.0)))
    duration_s = duration_ms / 1000.0

    # Produce a stable frame cadence before AI segmentation. This also trims at 20s.
    decoded = work / "decoded"
    decoded.mkdir(parents=True, exist_ok=True)
    run_command([
        "ffmpeg", "-y", "-i", str(source), "-t", f"{duration_s:.3f}",
        "-vf", f"fps={target_fps}", "-vsync", "0", str(decoded / "frame_%06d.png")
    ])
    frame_paths = sorted(decoded.glob("frame_*.png"))
    if not frame_paths:
        raise RuntimeError("no_video_frames")

    rgba_dir = work / "rgba"
    rgba_dir.mkdir(parents=True, exist_ok=True)
    previous_mask: np.ndarray | None = None
    union: tuple[int, int, int, int] | None = None
    output_size: tuple[int, int] | None = None

    for index, frame_path in enumerate(frame_paths, start=1):
        bgr = cv2.imread(str(frame_path), cv2.IMREAD_COLOR)
        if bgr is None:
            raise RuntimeError("frame_decode_failed")
        bgr = resize_frame(bgr, MAX_FRAME_SIDE)
        rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)

        # rembg's generic U2Net-style mask handles people, vehicles and decorative
        # salient objects better than person-only segmentation.
        mask_result = remove(rgb, session=session, only_mask=True)
        if isinstance(mask_result, Image.Image):
            mask = np.array(mask_result.convert("L"))
        elif isinstance(mask_result, bytes):
            mask = np.array(Image.open(__import__("io").BytesIO(mask_result)).convert("L"))
        else:
            mask = np.asarray(mask_result)
        if mask.shape[:2] != rgb.shape[:2]:
            mask = cv2.resize(mask, (rgb.shape[1], rgb.shape[0]), interpolation=cv2.INTER_LINEAR)
        mask = soften_mask(mask, previous_mask)
        previous_mask = mask
        box = bbox_from_mask(mask)
        union = union_bbox(union, box)
        rgba = np.dstack([rgb, mask])
        Image.fromarray(rgba, "RGBA").save(rgba_dir / f"frame_{index:06d}.png", optimize=True)
        output_size = (rgb.shape[1], rgb.shape[0])

    if output_size is None:
        raise RuntimeError("processor_output_missing")
    width, height = output_size
    if union is None:
        raise RuntimeError("background_removal_found_no_foreground")
    crop = padded_bbox(union, width, height)
    cx1, cy1, cx2, cy2 = crop

    cropped_dir = work / "cropped"
    cropped_dir.mkdir(parents=True, exist_ok=True)
    cropped_paths: list[Path] = []
    for path in sorted(rgba_dir.glob("frame_*.png")):
        image = Image.open(path).convert("RGBA")
        image = image.crop((cx1, cy1, cx2, cy2))
        out = cropped_dir / path.name
        image.save(out, optimize=True)
        cropped_paths.append(out)

    out_width = max(1, cx2 - cx1)
    out_height = max(1, cy2 - cy1)
    animation = work / "media.webp"
    # Animated WebP keeps real alpha and is significantly safer for Android UI
    # overlays than a normal MP4 with a black/white fake background.
    run_command([
        "ffmpeg", "-y", "-framerate", str(target_fps), "-i", str(cropped_dir / "frame_%06d.png"),
        "-c:v", "libwebp_anim", "-loop", "0", "-lossless", "0", "-q:v", "74",
        "-preset", "picture", "-an", str(animation)
    ])

    # Stay below the Supabase 50 MB bucket limit. Re-encode more aggressively if needed.
    if animation.stat().st_size > 45 * 1024 * 1024:
        run_command([
            "ffmpeg", "-y", "-framerate", str(target_fps), "-i", str(cropped_dir / "frame_%06d.png"),
            "-vf", "scale='min(540,iw)':-2:flags=lanczos", "-c:v", "libwebp_anim", "-loop", "0",
            "-lossless", "0", "-q:v", "60", "-preset", "picture", "-an", str(animation)
        ])
        probe_img = Image.open(cropped_paths[0])
        scale = min(1.0, 540 / probe_img.width)
        out_width = max(1, round(probe_img.width * scale))
        out_height = max(1, round(probe_img.height * scale))

    if animation.stat().st_size > 49 * 1024 * 1024:
        raise RuntimeError("processed_animation_exceeds_50mb")

    thumb_source = cropped_paths[min(len(cropped_paths) - 1, max(0, len(cropped_paths) // 5))]
    thumbnail = work / "thumbnail.webp"
    make_checker_thumbnail(thumb_source, thumbnail)

    audio: Path | None = None
    if keep_audio:
        audio = work / "audio.m4a"
        try:
            run_command([
                "ffmpeg", "-y", "-i", str(source), "-t", f"{duration_s:.3f}",
                "-vn", "-c:a", "aac", "-b:a", "128k", str(audio)
            ])
            if not audio.exists() or audio.stat().st_size < 1024:
                audio = None
        except Exception:
            # A silent source should not fail the whole visual entrance.
            audio = None

    return ProcessResult(
        animation=animation,
        audio=audio,
        thumbnail=thumbnail,
        width=out_width,
        height=out_height,
        duration_ms=duration_ms,
        file_size=animation.stat().st_size,
        fps=target_fps,
        frame_count=len(cropped_paths),
    )


async def upload_storage(path: str, file_path: Path, content_type: str, token: str) -> str:
    encoded = "/".join(quote(part, safe="") for part in path.split("/"))
    url = f"{SUPABASE_URL}/storage/v1/object/{BUCKET}/{encoded}"
    headers = {
        "apikey": SUPABASE_ANON_KEY,
        "Authorization": f"Bearer {token}",
        "Content-Type": content_type,
        "x-upsert": "true",
    }
    async with httpx.AsyncClient(timeout=httpx.Timeout(120.0, connect=20.0)) as client:
        response = await client.post(url, headers=headers, content=file_path.read_bytes())
        if response.status_code >= 300:
            raise RuntimeError(f"storage_upload_failed:{response.status_code}:{response.text[:240]}")
    return f"{SUPABASE_URL}/storage/v1/object/public/{BUCKET}/{encoded}"


async def update_asset(asset_key: str, payload: dict[str, Any], token: str) -> None:
    async with httpx.AsyncClient(timeout=30) as client:
        response = await client.post(
            f"{SUPABASE_URL}/rest/v1/rpc/admin_update_yamo_media_asset",
            headers=auth_headers(token),
            json={"p_asset_kind": "entry_effect", "p_asset_key": asset_key, "p_payload": payload},
        )
        if response.status_code >= 300:
            raise RuntimeError(f"asset_update_failed:{response.status_code}:{response.text[:240]}")


async def process_job(job_id: str, request: EntryProcessRequest, token: str) -> None:
    _jobs[job_id] = {"status": "processing", "asset_key": request.asset_key, "progress": 3}
    async with _job_semaphore:
        work_dir = Path(tempfile.mkdtemp(prefix=f"yamo-{request.asset_key}-"))
        try:
            source = work_dir / "source.bin"
            _jobs[job_id]["progress"] = 8
            await download_source(str(request.source_url), source)
            _jobs[job_id]["progress"] = 15
            session = await get_rembg_session()
            _jobs[job_id]["progress"] = 20
            result = await asyncio.to_thread(
                process_video_sync,
                source,
                work_dir,
                request.max_duration_ms,
                request.audio_enabled,
                session,
            )
            _jobs[job_id]["progress"] = 82

            root = f"entry_effect/{request.asset_key}/processor-{job_id}"
            media_path = f"{root}/media.webp"
            thumb_path = f"{root}/thumbnail.webp"
            media_url = await upload_storage(media_path, result.animation, "image/webp", token)
            thumb_url = await upload_storage(thumb_path, result.thumbnail, "image/webp", token)
            storage_paths = list(dict.fromkeys([*request.storage_paths, media_path, thumb_path]))

            audio_url: str | None = None
            if result.audio is not None:
                audio_path = f"{root}/audio.m4a"
                audio_url = await upload_storage(audio_path, result.audio, "audio/mp4", token)
                storage_paths.append(audio_path)

            _jobs[job_id]["progress"] = 92
            metadata = {
                "processor": "yamo-ai-background-v1",
                "background_removed": True,
                "transparent_animation": True,
                "render_format": "animated_webp",
                "audio_url": audio_url,
                "audio_separate_track": bool(audio_url),
                "fps": result.fps,
                "frame_count": result.frame_count,
                "max_duration_ms": request.max_duration_ms,
                "source_url": str(request.source_url),
                "original_url": str(request.original_url),
                "storage_paths": storage_paths,
                "edge_feathered": True,
                "temporal_mask_smoothing": True,
                "auto_cropped_to_foreground": True,
            }
            await update_asset(
                request.asset_key,
                {
                    "media_url": media_url,
                    "thumbnail_url": thumb_url,
                    "preview_url": thumb_url,
                    "media_type": "image",
                    "mime_type": "image/webp",
                    "processing_status": "ready",
                    "processing_error": "",
                    "audio_enabled": bool(audio_url) and request.audio_enabled,
                    "remove_background": True,
                    "width": result.width,
                    "height": result.height,
                    "duration_ms": result.duration_ms,
                    "file_size_bytes": result.file_size,
                    "quality": request.quality,
                    "enabled": request.enabled_after_processing,
                    "metadata": metadata,
                },
                token,
            )
            _jobs[job_id] = {
                "status": "ready",
                "asset_key": request.asset_key,
                "progress": 100,
                "media_url": media_url,
                "thumbnail_url": thumb_url,
                "audio_url": audio_url,
            }
        except Exception as exc:
            message = str(exc)[:800]
            _jobs[job_id] = {"status": "failed", "asset_key": request.asset_key, "progress": 100, "error": message}
            try:
                await update_asset(
                    request.asset_key,
                    {
                        "processing_status": "failed",
                        "processing_error": message,
                        "enabled": False,
                    },
                    token,
                )
            except Exception:
                pass
        finally:
            shutil.rmtree(work_dir, ignore_errors=True)


@app.get("/health")
async def health():
    return {
        "ok": not bool(CONFIG_ERROR),
        "service": APP_NAME,
        "model": MODEL_NAME,
        "max_concurrent_jobs": MAX_CONCURRENT_JOBS,
        "output_fps": OUTPUT_FPS,
        "max_frame_side": MAX_FRAME_SIDE,
        "config_error": CONFIG_ERROR or None,
    }


@app.get("/v1/jobs/{job_id}")
async def job_status(job_id: str, authorization: str | None = Header(default=None)):
    token = bearer_token(authorization)
    await verify_catalog_admin(token)
    job = _jobs.get(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="job_not_found")
    return job


def bearer_token(value: str | None) -> str:
    if not value or not value.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="authorization_required")
    token = value.split(" ", 1)[1].strip()
    if not token:
        raise HTTPException(status_code=401, detail="authorization_required")
    return token


@app.post("/v1/process-entry", status_code=202)
async def process_entry(
    request: EntryProcessRequest,
    background_tasks: BackgroundTasks,
    authorization: str | None = Header(default=None),
):
    token = bearer_token(authorization)
    await verify_catalog_admin(token)
    if not request.asset_key.upper().startswith("ENT-"):
        raise HTTPException(status_code=400, detail="entry_asset_key_required")
    job_id = uuid.uuid4().hex
    _jobs[job_id] = {"status": "queued", "asset_key": request.asset_key, "progress": 0}
    background_tasks.add_task(process_job, job_id, request, token)
    return {
        "accepted": True,
        "jobId": job_id,
        "status": "queued",
        "message": "Yamo AI video processing queued",
    }
