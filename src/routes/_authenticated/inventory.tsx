import { useMemo, useState, type ReactNode } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  BadgeCheck,
  CirclePlay,
  Clock3,
  Copy,
  Eye,
  Gift,
  Image as ImageIcon,
  Layers3,
  Loader2,
  Pencil,
  Plus,
  RefreshCw,
  Search,
  Send,
  ShieldCheck,
  Sparkles,
  Trash2,
  Upload,
  Undo2,
  Users,
  WandSparkles,
  Volume2,
  VolumeX,
} from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Switch } from "@/components/ui/switch";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Textarea } from "@/components/ui/textarea";
import { searchYamoAdminUsers, yamoRows, yamoRpc, type YamoAdminUserLookup } from "@/lib/yamo-admin";
import {
  advancedVideoProcessorConfigured,
  cancelAdvancedEntryVideoProcessing,
  formatBytes,
  prepareMediaAsset,
  publicFileName,
  removeUploadedMedia,
  startAdvancedEntryVideoProcessing,
  setAdvancedVideoProcessorUrl,
  advancedVideoProcessorUrl,
  uploadPreparedMedia,
  type EntryProcessingMode,
  type MediaAssetKind,
} from "@/lib/media-assets";

export const Route = createFileRoute("/_authenticated/inventory")({ component: InventoryCenter });

type AssetRow = Record<string, unknown> & {
  asset_kind: MediaAssetKind;
  asset_key: string;
  name_ar?: string;
  preview_url?: string;
  thumbnail_url?: string;
  media_url?: string;
  original_url?: string;
  price_coins?: number;
  duration_days?: number | null;
  enabled?: boolean;
  sort_order?: number;
  media_type?: "image" | "video";
  mime_type?: string;
  quality?: string;
  processing_status?: string;
  processing_error?: string | null;
  audio_enabled?: boolean;
  remove_background?: boolean;
  width?: number | null;
  height?: number | null;
  duration_ms?: number | null;
  file_size_bytes?: number | null;
  owner_count?: number;
  metadata?: Record<string, unknown> | string | null;
};

type RewardItem = { asset_kind: MediaAssetKind; asset_key: string; grant_days?: number | null; sort_order?: number };
type RewardRule = Record<string, unknown> & {
  id: string;
  name_ar: string;
  trigger_type: string;
  trigger_key?: string | null;
  trigger_value: number;
  window_type: string;
  delay_mode: string;
  delay_hours: number;
  enabled: boolean;
  items?: RewardItem[] | string;
};

const kindLabel: Record<MediaAssetKind, string> = {
  entry_effect: "دخلة",
  frame: "إطار",
  room_background: "خلفية روم",
};
const kindCode: Record<MediaAssetKind, string> = {
  entry_effect: "ENT-000001",
  frame: "FRM-000001",
  room_background: "BG-000001",
};

const entryModeLabel: Record<EntryProcessingMode, string> = {
  source: "زي ما هي",
  edges: "تنعيم الحواف",
  ai: "إزالة الخلفية AI",
};

function InventoryCenter() {
  const qc = useQueryClient();
  const [mainTab, setMainTab] = useState("effects");
  const [effectFilter, setEffectFilter] = useState<"all" | "entry_effect" | "frame">("all");
  const [query, setQuery] = useState("");
  const [assetDialog, setAssetDialog] = useState<{ open: boolean; asset?: AssetRow; initialKind?: MediaAssetKind }>({ open: false });
  const [grantAsset, setGrantAsset] = useState<AssetRow | null>(null);
  const [previewAsset, setPreviewAsset] = useState<AssetRow | null>(null);
  const [rewardDialog, setRewardDialog] = useState<{ open: boolean; rule?: RewardRule }>({ open: false });

  const assetsQ = useQuery({
    queryKey: ["admin_media_assets"],
    queryFn: () => yamoRows("admin_media_assets", 800) as Promise<AssetRow[]>,
    refetchInterval: 5_000,
  });
  const rulesQ = useQuery({
    queryKey: ["admin_asset_reward_rules"],
    queryFn: () => yamoRows("admin_asset_reward_rules", 300) as Promise<RewardRule[]>,
    refetchInterval: 60_000,
  });
  const queueQ = useQuery({
    queryKey: ["admin_asset_reward_queue"],
    queryFn: () => yamoRows("admin_asset_reward_queue", 500),
    refetchInterval: 60_000,
  });

  const assets = assetsQ.data ?? [];
  const searched = useMemo(() => {
    const needle = query.trim().toLowerCase();
    return assets.filter((asset) => {
      const hay = `${asset.name_ar ?? ""} ${asset.asset_key ?? ""} ${asset.asset_kind ?? ""}`.toLowerCase();
      return !needle || hay.includes(needle);
    });
  }, [assets, query]);
  const effects = searched.filter((a) => a.asset_kind === "entry_effect" || a.asset_kind === "frame");
  const visibleEffects = effectFilter === "all" ? effects : effects.filter((a) => a.asset_kind === effectFilter);
  const backgrounds = searched.filter((a) => a.asset_kind === "room_background");
  const readyCount = assets.filter((a) => a.processing_status === "ready").length;
  const pendingRewards = (queueQ.data ?? []).filter((r) => !r.granted_at).length;

  const refreshAll = () => {
    void qc.invalidateQueries({ queryKey: ["admin_media_assets"] });
    void qc.invalidateQueries({ queryKey: ["admin_asset_reward_rules"] });
    void qc.invalidateQueries({ queryKey: ["admin_asset_reward_queue"] });
  };

  const useOriginalEntry = async (asset: AssetRow) => {
    if (asset.asset_kind !== "entry_effect") return;
    const meta = parseMetadata(asset.metadata);
    const jobId = String(meta.processor_job_id || "").trim();
    try {
      if (jobId) await cancelAdvancedEntryVideoProcessing(jobId).catch(() => undefined);
      await yamoRpc("admin_update_yamo_media_asset", {
        p_asset_kind: "entry_effect",
        p_asset_key: asset.asset_key,
        p_payload: {
          processing_status: "ready",
          processing_error: "",
          remove_background: false,
          enabled: meta.enabled_after_processing !== false,
          metadata: {
            ...meta,
            entry_processing_mode: "source",
            processor_job_id: "",
            processor_cancelled_at: new Date().toISOString(),
            auto_decision: "use_source",
            presentation: { anchor: "room_center", fit: "contain", crop: false, preserve_aspect_ratio: true, max_duration_ms: 20_000 },
          },
        },
      });
      toast.success("تم اعتماد النسخة الأصلية وإيقاف انتظار المعالجة.");
      refreshAll();
    } catch (error) { toast.error(errorMessage(error)); }
  };

  const retryEntryProcessing = async (asset: AssetRow) => {
    if (asset.asset_kind !== "entry_effect") return;
    const meta = parseMetadata(asset.metadata);
    const rawMode = String(meta.entry_processing_mode || (meta.advanced_background_removal ? "ai" : "edges"));
    const processingMode: EntryProcessingMode = rawMode === "ai" ? "ai" : "edges";
    const sourceUrl = String(asset.media_url || asset.original_url || "");
    if (!sourceUrl) return toast.error("لا يوجد ملف أصل صالح لإعادة المعالجة.");
    if (!advancedVideoProcessorConfigured()) return toast.error("اربط معالج الفيديو أولًا.");
    try {
      await yamoRpc("admin_update_yamo_media_asset", {
        p_asset_kind: "entry_effect",
        p_asset_key: asset.asset_key,
        p_payload: {
          processing_status: "processing",
          processing_error: processingMode === "edges" ? "إعادة محاولة تنعيم الحواف بدون إزالة الخلفية." : "إعادة محاولة إزالة الخلفية AI.",
          enabled: false,
          metadata: { ...meta, entry_processing_mode: processingMode, processor_job_id: "" },
        },
      });
      const job = await startAdvancedEntryVideoProcessing({
        assetKey: asset.asset_key,
        sourceUrl,
        originalUrl: String(asset.original_url || sourceUrl),
        thumbnailUrl: String(asset.thumbnail_url || asset.preview_url || "") || null,
        audioEnabled: Boolean(asset.audio_enabled),
        enabledAfterProcessing: meta.enabled_after_processing !== false,
        quality: String(asset.quality || "auto"),
        storagePaths: readStoragePaths(asset.metadata),
        maxDurationMs: 20_000,
        processingMode,
      });
      await yamoRpc("admin_update_yamo_media_asset", {
        p_asset_kind: "entry_effect",
        p_asset_key: asset.asset_key,
        p_payload: { metadata: { ...meta, entry_processing_mode: processingMode, processor_job_id: job.jobId || "" } },
      });
      toast.success("بدأت إعادة المعالجة.");
      refreshAll();
    } catch (error) {
      await yamoRpc("admin_update_yamo_media_asset", {
        p_asset_kind: "entry_effect", p_asset_key: asset.asset_key,
        p_payload: { processing_status: "failed", processing_error: errorMessage(error), enabled: false, metadata: meta },
      }).catch(() => undefined);
      toast.error(errorMessage(error));
      refreshAll();
    }
  };

  return (
    <div className="space-y-6" dir="rtl">
      <section className="relative overflow-hidden rounded-[28px] border bg-gradient-to-l from-violet-950/70 via-card to-orange-950/30 p-5 shadow-xl md:p-7">
        <div className="pointer-events-none absolute -left-16 -top-20 h-56 w-56 rounded-full bg-orange-500/10 blur-3xl" />
        <div className="pointer-events-none absolute -bottom-24 right-8 h-64 w-64 rounded-full bg-violet-500/15 blur-3xl" />
        <div className="relative flex flex-wrap items-start justify-between gap-4">
          <div>
            <div className="mb-2 flex flex-wrap items-center gap-2">
              <Badge className="rounded-full bg-violet-500/15 text-violet-200 hover:bg-violet-500/15">YAMO MEDIA CENTER</Badge>
              <Badge variant="outline" className="gap-1 rounded-full border-emerald-500/30 bg-emerald-500/10 text-emerald-400">
                <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-emerald-400" /> متصل بالسيرفر
              </Badge>
              <Badge variant="outline" className={`gap-1 rounded-full ${advancedVideoProcessorConfigured() ? "border-cyan-500/30 bg-cyan-500/10 text-cyan-300" : "border-amber-500/30 bg-amber-500/10 text-amber-300"}`}>
                <WandSparkles className="h-3 w-3" /> {advancedVideoProcessorConfigured() ? "معالج الفيديو AI جاهز" : "معالج الفيديو يحتاج ربط"}
              </Badge>
            </div>
            <h1 className="text-2xl font-black tracking-tight md:text-4xl">المقتنيات والمؤثرات</h1>
            <p className="mt-2 max-w-3xl text-sm leading-7 text-muted-foreground">
              إدارة الدخلات والإطارات وخلفيات الرومات من مكان واحد، بكود تلقائي ومعاينة مصغرة ومعالجة قبل النشر.
            </p>
          </div>
          <div className="flex flex-wrap gap-2">
            <Button variant="outline" className="rounded-xl" onClick={refreshAll}>
              <RefreshCw className="ml-2 h-4 w-4" /> تحديث الكتالوج
            </Button>
            <Button variant="outline" className="rounded-xl" onClick={() => {
              const next = window.prompt("رابط معالج فيديو Yamo (HTTPS)", advancedVideoProcessorUrl());
              if (next === null) return;
              setAdvancedVideoProcessorUrl(next);
              toast.success(next.trim() ? "تم حفظ رابط معالج الفيديو" : "تم مسح رابط معالج الفيديو");
              window.location.reload();
            }}>
              <WandSparkles className="ml-2 h-4 w-4" /> إعداد معالج الفيديو
            </Button>
            <Button className="rounded-xl bg-gradient-to-l from-violet-600 to-orange-500 font-bold" onClick={() => setAssetDialog({ open: true, initialKind: mainTab === "backgrounds" ? "room_background" : "entry_effect" })}>
              <Plus className="ml-2 h-4 w-4" /> رفع عنصر جديد
            </Button>
          </div>
        </div>
      </section>

      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard icon={CirclePlay} label="الدخلات" value={assets.filter((a) => a.asset_kind === "entry_effect").length} note="حركة دخول الغرفة" />
        <StatCard icon={Layers3} label="الإطارات" value={assets.filter((a) => a.asset_kind === "frame").length} note="إطارات المستخدمين" />
        <StatCard icon={ImageIcon} label="الخلفيات" value={backgrounds.length} note="ثابتة أو متحركة" />
        <StatCard icon={BadgeCheck} label="جاهز للنشر" value={readyCount} note={`${pendingRewards} مكافأة معلّقة`} />
      </div>

      <Tabs value={mainTab} onValueChange={setMainTab} className="space-y-4">
        <TabsList className="grid h-auto w-full grid-cols-1 gap-2 rounded-2xl border bg-card/80 p-2 sm:grid-cols-3">
          <TabsTrigger value="effects" className="gap-2 rounded-xl py-3 data-[state=active]:bg-violet-600 data-[state=active]:text-white">
            <Sparkles className="h-4 w-4" /> الدخلات والإطارات
          </TabsTrigger>
          <TabsTrigger value="backgrounds" className="gap-2 rounded-xl py-3 data-[state=active]:bg-orange-500 data-[state=active]:text-white">
            <ImageIcon className="h-4 w-4" /> الخلفيات
          </TabsTrigger>
          <TabsTrigger value="rewards" className="gap-2 rounded-xl py-3 data-[state=active]:bg-emerald-600 data-[state=active]:text-white">
            <Gift className="h-4 w-4" /> المكافآت التلقائية
          </TabsTrigger>
        </TabsList>

        <TabsContent value="effects" className="space-y-4">
          <Toolbar
            query={query}
            setQuery={setQuery}
            filter={effectFilter}
            setFilter={setEffectFilter}
            onAdd={(kind) => setAssetDialog({ open: true, initialKind: kind })}
          />
          <AssetGrid
            rows={visibleEffects}
            loading={assetsQ.isLoading}
            error={assetsQ.error as Error | null}
            onPreview={setPreviewAsset}
            onEdit={(asset) => setAssetDialog({ open: true, asset })}
            onGrant={setGrantAsset}
            onUseOriginal={useOriginalEntry}
            onRetryProcessing={retryEntryProcessing}
            onDelete={async (asset) => {
              if (!window.confirm(`حذف ${kindLabel[asset.asset_kind]} «${asset.name_ar ?? asset.asset_key}»؟ سيتم سحبها من المستخدمين أيضًا.`)) return;
              try {
                await yamoRpc("admin_delete_yamo_media_asset", { p_asset_kind: asset.asset_kind, p_asset_key: asset.asset_key, p_reason: "حذف من مركز المقتنيات" });
                const paths = readStoragePaths(asset.metadata);
                if (paths.length) await removeUploadedMedia(paths).catch(() => undefined);
                toast.success("تم حذف العنصر");
                refreshAll();
              } catch (error) { toast.error(errorMessage(error)); }
            }}
          />
        </TabsContent>

        <TabsContent value="backgrounds" className="space-y-4">
          <div className="flex flex-wrap items-center justify-between gap-3 rounded-2xl border bg-card/70 p-4">
            <div>
              <h2 className="font-black">خلفيات الرومات</h2>
              <p className="text-xs text-muted-foreground">الصورة المصغرة تتولد تلقائيًا، والفيديو يظل بدون صوت افتراضيًا داخل الروم.</p>
            </div>
            <div className="flex flex-1 justify-end gap-2 sm:flex-none">
              <SearchBox value={query} onChange={setQuery} />
              <Button className="rounded-xl bg-orange-500 hover:bg-orange-600" onClick={() => setAssetDialog({ open: true, initialKind: "room_background" })}>
                <Plus className="ml-2 h-4 w-4" /> خلفية جديدة
              </Button>
            </div>
          </div>
          <AssetGrid
            rows={backgrounds}
            loading={assetsQ.isLoading}
            error={assetsQ.error as Error | null}
            onPreview={setPreviewAsset}
            onEdit={(asset) => setAssetDialog({ open: true, asset })}
            onGrant={setGrantAsset}
            onUseOriginal={useOriginalEntry}
            onRetryProcessing={retryEntryProcessing}
            onDelete={async (asset) => {
              if (!window.confirm(`حذف الخلفية «${asset.name_ar ?? asset.asset_key}»؟`)) return;
              try {
                await yamoRpc("admin_delete_yamo_media_asset", { p_asset_kind: asset.asset_kind, p_asset_key: asset.asset_key, p_reason: "حذف خلفية من مركز المقتنيات" });
                const paths = readStoragePaths(asset.metadata);
                if (paths.length) await removeUploadedMedia(paths).catch(() => undefined);
                toast.success("تم حذف الخلفية");
                refreshAll();
              } catch (error) { toast.error(errorMessage(error)); }
            }}
          />
        </TabsContent>

        <TabsContent value="rewards" className="space-y-4">
          <RewardsPanel
            rules={rulesQ.data ?? []}
            queue={queueQ.data ?? []}
            loading={rulesQ.isLoading}
            assets={assets.filter((a) => a.processing_status === "ready")}
            onAdd={() => setRewardDialog({ open: true })}
            onEdit={(rule) => setRewardDialog({ open: true, rule })}
            onRefresh={refreshAll}
          />
        </TabsContent>
      </Tabs>

      <AssetEditorDialog
        key={`${assetDialog.open}:${assetDialog.asset?.asset_key ?? assetDialog.initialKind ?? "new"}`}
        open={assetDialog.open}
        asset={assetDialog.asset}
        initialKind={assetDialog.initialKind}
        onOpenChange={(open) => setAssetDialog((s) => ({ ...s, open }))}
        onSaved={() => { setAssetDialog({ open: false }); refreshAll(); }}
      />
      <GrantDialog asset={grantAsset} onClose={() => setGrantAsset(null)} onSaved={refreshAll} />
      <PreviewDialog asset={previewAsset} onClose={() => setPreviewAsset(null)} />
      <RewardRuleDialog
        key={`${rewardDialog.open}:${rewardDialog.rule?.id ?? "new"}`}
        open={rewardDialog.open}
        rule={rewardDialog.rule}
        assets={assets.filter((a) => a.processing_status === "ready")}
        onOpenChange={(open) => setRewardDialog((s) => ({ ...s, open }))}
        onSaved={() => { setRewardDialog({ open: false }); refreshAll(); }}
      />
    </div>
  );
}

function StatCard({ icon: Icon, label, value, note }: { icon: typeof Sparkles; label: string; value: number; note: string }) {
  return (
    <Card className="overflow-hidden border-border/70 bg-card/85 shadow-sm">
      <CardContent className="flex items-center justify-between p-4">
        <div>
          <p className="text-xs text-muted-foreground">{label}</p>
          <p className="mt-1 text-3xl font-black tabular-nums">{value.toLocaleString("en-US")}</p>
          <p className="mt-1 text-[11px] text-muted-foreground">{note}</p>
        </div>
        <div className="rounded-2xl bg-gradient-to-br from-violet-500/20 to-orange-500/20 p-3 text-violet-400">
          <Icon className="h-6 w-6" />
        </div>
      </CardContent>
    </Card>
  );
}

function Toolbar({ query, setQuery, filter, setFilter, onAdd }: {
  query: string;
  setQuery: (v: string) => void;
  filter: "all" | "entry_effect" | "frame";
  setFilter: (v: "all" | "entry_effect" | "frame") => void;
  onAdd: (kind: MediaAssetKind) => void;
}) {
  return (
    <div className="flex flex-wrap items-center justify-between gap-3 rounded-2xl border bg-card/70 p-4">
      <div className="flex flex-wrap gap-2">
        {(["all", "entry_effect", "frame"] as const).map((value) => (
          <Button key={value} size="sm" variant={filter === value ? "default" : "outline"} className="rounded-xl" onClick={() => setFilter(value)}>
            {value === "all" ? "الكل" : value === "entry_effect" ? "الدخلات" : "الإطارات"}
          </Button>
        ))}
      </div>
      <div className="flex flex-1 flex-wrap justify-end gap-2 sm:flex-none">
        <SearchBox value={query} onChange={setQuery} />
        <Button variant="outline" className="rounded-xl" onClick={() => onAdd("frame")}><Layers3 className="ml-2 h-4 w-4" /> إطار جديد</Button>
        <Button className="rounded-xl bg-violet-600 hover:bg-violet-700" onClick={() => onAdd("entry_effect")}><Sparkles className="ml-2 h-4 w-4" /> دخلة جديدة</Button>
      </div>
    </div>
  );
}

function SearchBox({ value, onChange }: { value: string; onChange: (v: string) => void }) {
  return (
    <div className="relative min-w-60 flex-1 sm:flex-none">
      <Search className="absolute right-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
      <Input value={value} onChange={(e) => onChange(e.target.value)} placeholder="بحث بالاسم أو الكود…" className="rounded-xl pr-9 sm:w-72" />
    </div>
  );
}

function AssetGrid({ rows, loading, error, onPreview, onEdit, onGrant, onUseOriginal, onRetryProcessing, onDelete }: {
  rows: AssetRow[];
  loading: boolean;
  error: Error | null;
  onPreview: (row: AssetRow) => void;
  onEdit: (row: AssetRow) => void;
  onGrant: (row: AssetRow) => void;
  onUseOriginal: (row: AssetRow) => void | Promise<void>;
  onRetryProcessing: (row: AssetRow) => void | Promise<void>;
  onDelete: (row: AssetRow) => void | Promise<void>;
}) {
  if (loading) return <div className="grid min-h-64 place-items-center rounded-2xl border bg-card/60"><Loader2 className="h-7 w-7 animate-spin" /></div>;
  if (error) return <div className="rounded-2xl border border-destructive/30 bg-destructive/5 p-6 text-sm text-destructive">{error.message}</div>;
  if (!rows.length) return <div className="grid min-h-56 place-items-center rounded-2xl border border-dashed bg-card/50 text-sm text-muted-foreground">لا توجد عناصر في هذا القسم حتى الآن.</div>;
  return (
    <div className="grid gap-4 md:grid-cols-2 2xl:grid-cols-3">
      {rows.map((asset) => <AssetCard key={`${asset.asset_kind}:${asset.asset_key}`} asset={asset} onPreview={onPreview} onEdit={onEdit} onGrant={onGrant} onUseOriginal={onUseOriginal} onRetryProcessing={onRetryProcessing} onDelete={onDelete} />)}
    </div>
  );
}

function AssetCard({ asset, onPreview, onEdit, onGrant, onUseOriginal, onRetryProcessing, onDelete }: {
  asset: AssetRow;
  onPreview: (row: AssetRow) => void;
  onEdit: (row: AssetRow) => void;
  onGrant: (row: AssetRow) => void;
  onUseOriginal: (row: AssetRow) => void | Promise<void>;
  onRetryProcessing: (row: AssetRow) => void | Promise<void>;
  onDelete: (row: AssetRow) => void | Promise<void>;
}) {
  const thumb = String(asset.thumbnail_url || asset.preview_url || "");
  const status = String(asset.processing_status || "ready");
  const ready = status === "ready";
  const meta = parseMetadata(asset.metadata);
  const mode = String(meta.entry_processing_mode || (asset.remove_background ? "ai" : "source")) as EntryProcessingMode;
  const recoverableEntry = asset.asset_kind === "entry_effect" && status !== "ready";
  return (
    <Card className="group overflow-hidden border-border/70 bg-card/90 shadow-sm transition-all hover:-translate-y-0.5 hover:shadow-xl">
      <div className="relative aspect-[16/9] overflow-hidden bg-gradient-to-br from-violet-950/60 to-orange-950/30">
        {thumb ? <img src={thumb} alt={asset.name_ar ?? asset.asset_key} loading="lazy" className="h-full w-full object-cover transition-transform duration-300 group-hover:scale-[1.025]" /> : <div className="grid h-full place-items-center"><ImageIcon className="h-10 w-10 text-muted-foreground" /></div>}
        <div className="absolute inset-x-0 top-0 flex items-start justify-between gap-2 p-3">
          <Badge className="rounded-full bg-black/60 text-white backdrop-blur">{kindLabel[asset.asset_kind]}</Badge>
          <StatusBadge status={status} enabled={asset.enabled} />
        </div>
        {asset.media_type === "video" && <div className="absolute bottom-3 right-3 rounded-full bg-black/60 p-2 text-white backdrop-blur"><CirclePlay className="h-5 w-5" /></div>}
      </div>
      <CardContent className="space-y-4 p-4">
        <div className="flex items-start justify-between gap-3">
          <div className="min-w-0">
            <h3 className="truncate text-base font-black">{asset.name_ar || asset.asset_key}</h3>
            <button type="button" className="mt-1 flex items-center gap-1 text-xs font-semibold text-violet-400" onClick={() => { void navigator.clipboard.writeText(asset.asset_key); toast.success("تم نسخ الكود"); }}>
              <Copy className="h-3 w-3" /><span dir="ltr">{asset.asset_key}</span>
            </button>
          </div>
          <div className="text-left text-xs text-muted-foreground">
            <div className="font-bold text-foreground">{Number(asset.owner_count ?? 0).toLocaleString("en-US")}</div>
            <div>مالك</div>
          </div>
        </div>
        <div className="grid grid-cols-3 gap-2 text-center text-[11px]">
          <MiniMeta label="الجودة" value={String(asset.quality || "Auto").toUpperCase()} />
          <MiniMeta label="المقاس" value={asset.width && asset.height ? `${asset.width}×${asset.height}` : "تلقائي"} />
          <MiniMeta label="الحجم" value={formatBytes(Number(asset.file_size_bytes ?? 0))} />
        </div>
        {asset.asset_kind === "entry_effect" && <div className="flex flex-wrap items-center gap-2 text-[11px]"><Badge variant="outline" className="rounded-full">{entryModeLabel[mode] || entryModeLabel.source}</Badge><span className="text-muted-foreground">العرض: منتصف الروم • Fit بدون قص</span></div>}
        {asset.processing_error && <div className="rounded-xl border border-amber-500/25 bg-amber-500/8 p-2.5 text-[11px] leading-5 text-amber-300">{asset.processing_error}</div>}
        {recoverableEntry && <div className="flex flex-wrap gap-2 rounded-xl border border-violet-500/15 bg-violet-500/5 p-2.5"><Button size="sm" className="rounded-xl bg-emerald-600 hover:bg-emerald-700" onClick={() => void onUseOriginal(asset)}><Undo2 className="ml-1 h-3.5 w-3.5" /> استخدام الأصل الآن</Button>{status !== "processing" && <Button size="sm" variant="outline" className="rounded-xl" onClick={() => void onRetryProcessing(asset)}><RefreshCw className="ml-1 h-3.5 w-3.5" /> إعادة المعالجة</Button>}</div>}
        <div className="flex flex-wrap gap-2 border-t pt-3">
          <Button size="sm" variant="outline" className="flex-1 rounded-xl" onClick={() => onPreview(asset)}><Eye className="ml-1 h-3.5 w-3.5" /> معاينة</Button>
          <Button size="sm" variant="outline" className="rounded-xl" onClick={() => onEdit(asset)}><Pencil className="h-3.5 w-3.5" /></Button>
          <Button size="sm" variant="outline" className="rounded-xl" disabled={!ready} onClick={() => onGrant(asset)} title={!ready ? "لا يمكن المنح قبل اكتمال المعالجة" : "منح لمستخدم"}><Send className="h-3.5 w-3.5" /></Button>
          <Button size="sm" variant="outline" className="rounded-xl text-destructive hover:text-destructive" onClick={() => void onDelete(asset)}><Trash2 className="h-3.5 w-3.5" /></Button>
        </div>
      </CardContent>
    </Card>
  );
}

function MiniMeta({ label, value }: { label: string; value: string }) {
  return <div className="rounded-xl bg-muted/50 px-2 py-2"><div className="truncate font-bold text-foreground" dir="ltr">{value}</div><div className="mt-0.5 text-muted-foreground">{label}</div></div>;
}

function StatusBadge({ status, enabled }: { status: string; enabled?: boolean }) {
  const map: Record<string, { label: string; cls: string }> = {
    ready: { label: enabled === false ? "متوقف" : "جاهز", cls: enabled === false ? "bg-zinc-700/80 text-zinc-100" : "bg-emerald-600/85 text-white" },
    uploading: { label: "جاري الرفع", cls: "bg-blue-600/85 text-white" },
    processing: { label: "جاري المعالجة", cls: "bg-violet-600/85 text-white" },
    needs_processor: { label: "يحتاج معالجة", cls: "bg-amber-500/90 text-black" },
    failed: { label: "فشل", cls: "bg-red-600/90 text-white" },
    disabled: { label: "متوقف", cls: "bg-zinc-700/80 text-white" },
  };
  const item = map[status] ?? map.ready;
  return <Badge className={`rounded-full border-0 backdrop-blur ${item.cls}`}>{item.label}</Badge>;
}

function AssetEditorDialog({ open, onOpenChange, asset, initialKind, onSaved }: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  asset?: AssetRow;
  initialKind?: MediaAssetKind;
  onSaved: () => void;
}) {
  const editing = Boolean(asset);
  const [kind, setKind] = useState<MediaAssetKind>(asset?.asset_kind ?? initialKind ?? "entry_effect");
  const [name, setName] = useState(asset?.name_ar ?? "");
  const [price, setPrice] = useState(String(asset?.price_coins ?? 1));
  const [days, setDays] = useState(asset?.duration_days ? String(asset.duration_days) : "");
  const [quality, setQuality] = useState(asset?.quality ?? "auto");
  const [sortOrder, setSortOrder] = useState(String(asset?.sort_order ?? 0));
  const [enabled, setEnabled] = useState(asset?.enabled ?? true);
  const [audio, setAudio] = useState(asset?.audio_enabled ?? false);
  const savedMeta = parseMetadata(asset?.metadata);
  const savedEntryMode = String(savedMeta.entry_processing_mode || "") as EntryProcessingMode;
  const [entryMode, setEntryMode] = useState<EntryProcessingMode>(
    savedEntryMode === "source" || savedEntryMode === "auto" || savedEntryMode === "ai"
      ? savedEntryMode
      : asset?.remove_background ? "ai" : "source",
  );
  const [removeBg, setRemoveBg] = useState(asset?.remove_background ?? (kind === "frame"));
  const [file, setFile] = useState<File | null>(null);
  const [thumbnail, setThumbnail] = useState<File | null>(null);
  const [busyText, setBusyText] = useState("");

  // Dialog components remain mounted. Reset fields when a different asset/opening arrives.
  const identity = `${open}:${asset?.asset_kind ?? initialKind ?? "entry_effect"}:${asset?.asset_key ?? "new"}`;
  return <AssetEditorInner key={identity} {...{
    open,onOpenChange,asset,initialKind,onSaved,editing,kind,setKind,name,setName,price,setPrice,days,setDays,quality,setQuality,sortOrder,setSortOrder,
    enabled,setEnabled,audio,setAudio,entryMode,setEntryMode,removeBg,setRemoveBg,file,setFile,thumbnail,setThumbnail,busyText,setBusyText,
  }} />;
}

function AssetEditorInner(props: {
  open: boolean; onOpenChange: (v: boolean) => void; asset?: AssetRow; initialKind?: MediaAssetKind; onSaved: () => void; editing: boolean;
  kind: MediaAssetKind; setKind: (v: MediaAssetKind) => void; name: string; setName: (v: string) => void; price: string; setPrice: (v: string) => void;
  days: string; setDays: (v: string) => void; quality: string; setQuality: (v: string) => void; sortOrder: string; setSortOrder: (v: string) => void;
  enabled: boolean; setEnabled: (v: boolean) => void; audio: boolean; setAudio: (v: boolean) => void; entryMode: EntryProcessingMode; setEntryMode: (v: EntryProcessingMode) => void; removeBg: boolean; setRemoveBg: (v: boolean) => void;
  file: File | null; setFile: (v: File | null) => void; thumbnail: File | null; setThumbnail: (v: File | null) => void; busyText: string; setBusyText: (v: string) => void;
}) {
  const { open,onOpenChange,asset,onSaved,editing,kind,setKind,name,setName,price,setPrice,days,setDays,quality,setQuality,sortOrder,setSortOrder,enabled,setEnabled,audio,setAudio,entryMode,setEntryMode,removeBg,setRemoveBg,file,setFile,thumbnail,setThumbnail,busyText,setBusyText } = props;
  const mutation = useMutation({
    mutationFn: async () => {
      if (!name.trim()) throw new Error("اكتب اسم العنصر");
      if (!editing && !file) throw new Error("اختر ملف العنصر أولًا");
      let uploaded: Awaited<ReturnType<typeof uploadPreparedMedia>> | null = null;
      let saved = false;
      let code = asset?.asset_key ?? "";
      const advancedVideo = Boolean(file && kind === "entry_effect" && file.type.startsWith("video/") && entryMode !== "source");
      const processorReady = advancedVideoProcessorConfigured();
      try {
        if (file) {
          setBusyText(advancedVideo ? "قص الدخلة وتجهيز النسخة الأصلية الآمنة…" : "تحليل الملف والقص التلقائي وإنشاء الصورة المصغرة…");
          // "زي ما هي" لا تدخل المعالج إطلاقًا.
          // "تنعيم الحواف" يحافظ على الخلفية ويعالج الحواف فقط، وAI هو الوحيد الذي يزيل الخلفية.
          const localRemoveBackground = kind === "frame" ? removeBg : kind === "entry_effect" && file.type.startsWith("image/") ? entryMode === "ai" : false;
          const prepared = await prepareMediaAsset(file, kind, localRemoveBackground, thumbnail, audio);
          prepared.metadata = {
            ...prepared.metadata,
            entry_processing_mode: kind === "entry_effect" ? entryMode : undefined,
            presentation: kind === "entry_effect" ? { anchor: "room_center", fit: "contain", crop: false, preserve_aspect_ratio: true, max_duration_ms: 20_000 } : undefined,
          };
          if (advancedVideo) {
            prepared.processingStatus = processorReady ? "processing" : "needs_processor";
            prepared.processingError = processorReady
              ? entryMode === "edges"
                ? "جاري تنعيم الحواف فقط بدون إزالة الخلفية."
                : "جاري إزالة الخلفية AI. النسخة الأصلية محفوظة ويمكن الرجوع لها."
              : "تم تجهيز الملف، لكن رابط معالج الفيديو غير مضبوط بعد.";
            prepared.metadata = { ...prepared.metadata, advanced_background_removal: entryMode === "ai", edge_smoothing_only: entryMode === "edges", processor_required: true };
          }
          setBusyText("رفع الأصل وملفات المعاينة…");
          uploaded = await uploadPreparedMedia(prepared, kind);
        }
        const priorMeta = parseMetadata(asset?.metadata);
        const payload: Record<string, unknown> = {
          name_ar: name.trim(),
          price_coins: Math.max(1, Number(price || 1)),
          duration_days: days.trim() ? Math.max(1, Number(days)) : "",
          quality,
          sort_order: Number(sortOrder || 0),
          enabled: advancedVideo ? false : enabled,
          audio_enabled: kind === "entry_effect" ? audio : false,
          remove_background: kind === "frame" ? removeBg : false,
        };
        if (uploaded) Object.assign(payload, {
          media_url: uploaded.mediaUrl,
          original_url: uploaded.originalUrl,
          thumbnail_url: uploaded.thumbnailUrl,
          preview_url: uploaded.thumbnailUrl,
          media_type: uploaded.mediaType,
          mime_type: uploaded.mimeType,
          processing_status: uploaded.processingStatus,
          processing_error: uploaded.processingError ?? "",
          width: uploaded.width,
          height: uploaded.height,
          duration_ms: uploaded.durationMs ?? "",
          file_size_bytes: uploaded.processed.size,
          metadata: {
            ...priorMeta,
            ...uploaded.metadata,
            storage_paths: uploaded.storagePaths,
            enabled_after_processing: enabled,
            entry_processing_mode: kind === "entry_effect" ? entryMode : undefined,
            presentation: kind === "entry_effect" ? { anchor: "room_center", fit: "contain", crop: false, preserve_aspect_ratio: true, max_duration_ms: 20_000 } : undefined,
          },
        });
        setBusyText(editing ? "حفظ التعديلات…" : "إنشاء الكود التلقائي وحفظ العنصر…");
        if (editing && asset) {
          await yamoRpc("admin_update_yamo_media_asset", { p_asset_kind: asset.asset_kind, p_asset_key: asset.asset_key, p_payload: payload });
          code = asset.asset_key;
          saved = true;
        } else {
          const result = await yamoRpc<{ asset_key?: string }>("admin_create_yamo_media_asset", { p_asset_kind: kind, p_payload: payload });
          code = String(result?.asset_key ?? "");
          saved = true;
        }

        if (advancedVideo && uploaded && processorReady) {
          setBusyText(entryMode === "edges" ? "إرسال الدخلة لتنعيم الحواف…" : "إرسال الدخلة لمعالج إزالة الخلفية…");
          try {
            const job = await startAdvancedEntryVideoProcessing({
              assetKey: code,
              sourceUrl: uploaded.mediaUrl,
              originalUrl: uploaded.originalUrl,
              thumbnailUrl: uploaded.thumbnailUrl,
              audioEnabled: audio,
              enabledAfterProcessing: enabled,
              quality,
              storagePaths: uploaded.storagePaths,
              maxDurationMs: 20_000,
              processingMode: entryMode,
            });
            const currentMeta = {
              ...priorMeta,
              ...uploaded.metadata,
              storage_paths: uploaded.storagePaths,
              enabled_after_processing: enabled,
              entry_processing_mode: entryMode,
              processor_job_id: job.jobId || "",
              presentation: { anchor: "room_center", fit: "contain", crop: false, preserve_aspect_ratio: true, max_duration_ms: 20_000 },
            };
            await yamoRpc("admin_update_yamo_media_asset", {
              p_asset_kind: "entry_effect",
              p_asset_key: code,
              p_payload: { metadata: currentMeta },
            });
          } catch (processorError) {
            await yamoRpc("admin_update_yamo_media_asset", {
              p_asset_kind: "entry_effect",
              p_asset_key: code,
              p_payload: {
                processing_status: "failed",
                processing_error: errorMessage(processorError),
                enabled: false,
              },
            }).catch(() => undefined);
            throw processorError;
          }
        }

        if (editing && uploaded && !advancedVideo) {
          const oldPaths = readStoragePaths(asset?.metadata);
          if (oldPaths.length) await removeUploadedMedia(oldPaths).catch(() => undefined);
        }
        return { code, advancedVideo, processorReady, entryMode };
      } catch (error) {
        if (!saved && uploaded?.storagePaths?.length) await removeUploadedMedia(uploaded.storagePaths).catch(() => undefined);
        throw error;
      } finally { setBusyText(""); }
    },
    onSuccess: ({ code, advancedVideo, processorReady, entryMode: savedMode }) => {
      if (advancedVideo && processorReady) toast.success(savedMode === "edges" ? `تم رفع ${code} وبدأ تنعيم الحواف بدون إزالة الخلفية.` : `تم رفع ${code} وبدأت إزالة الخلفية AI. الأصل محفوظ ويمكن الرجوع له.`);
      else if (advancedVideo) toast.warning(`تم حفظ ${code} لكنه ينتظر ربط معالج الفيديو.`);
      else toast.success(editing ? "تم حفظ التعديلات" : `تمت إضافة العنصر بالكود ${code}`);
      onSaved();
    },
    onError: (error) => toast.error(errorMessage(error)),
  });

  const preview = file ? URL.createObjectURL(file) : String(asset?.media_url || asset?.preview_url || "");
  return (
    <Dialog open={open} onOpenChange={(value) => !mutation.isPending && onOpenChange(value)}>
      <DialogContent className="max-h-[92vh] max-w-4xl overflow-y-auto border-violet-500/20 bg-card" dir="rtl">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2 text-xl"><WandSparkles className="h-5 w-5 text-violet-400" /> {editing ? "تعديل العنصر" : "إضافة عنصر جديد"}</DialogTitle>
          <DialogDescription>الكود يتولد تلقائيًا ولا يمكن تكراره. الصورة المصغرة تتولد من الملف إلا لو رفعت صورة مخصصة.</DialogDescription>
        </DialogHeader>
        <div className="grid gap-5 lg:grid-cols-[1.15fr_.85fr]">
          <div className="space-y-4">
            <div className="grid gap-4 sm:grid-cols-2">
              <Field label="نوع العنصر">
                <Select value={kind} disabled={editing} onValueChange={(v) => { const k=v as MediaAssetKind; setKind(k); setEntryMode("source"); setRemoveBg(k === "frame"); }}>
                  <SelectTrigger className="rounded-xl"><SelectValue /></SelectTrigger>
                  <SelectContent><SelectItem value="entry_effect">دخلة</SelectItem><SelectItem value="frame">إطار</SelectItem><SelectItem value="room_background">خلفية روم</SelectItem></SelectContent>
                </Select>
              </Field>
              <Field label="الكود">
                <Input value={editing ? asset?.asset_key : kindCode[kind]} disabled className="rounded-xl font-mono opacity-80" dir="ltr" />
                {!editing && <p className="mt-1 text-[10px] text-muted-foreground">المثال فقط — الرقم الحقيقي يُحجز لحظة الحفظ.</p>}
              </Field>
            </div>
            <div className="grid gap-4 sm:grid-cols-2">
              <Field label="اسم العنصر"><Input value={name} onChange={(e) => setName(e.target.value)} placeholder="مثال: دخول الملك" className="rounded-xl" /></Field>
              <Field label="الجودة">
                <Select value={quality} onValueChange={setQuality}><SelectTrigger className="rounded-xl"><SelectValue /></SelectTrigger><SelectContent><SelectItem value="auto">تلقائي</SelectItem><SelectItem value="hd">HD</SelectItem><SelectItem value="fhd">FHD</SelectItem><SelectItem value="4k">4K</SelectItem></SelectContent></Select>
              </Field>
            </div>
            <div className="grid gap-4 sm:grid-cols-2">
              <Field label="السعر بالكوينز"><Input type="number" min={0} value={price} onChange={(e) => setPrice(e.target.value)} className="rounded-xl font-mono" dir="ltr" /></Field>
              <Field label="ترتيب الظهور"><Input type="number" value={sortOrder} onChange={(e) => setSortOrder(e.target.value)} className="rounded-xl font-mono" dir="ltr" /></Field>
            </div>
            <DurationDaysPicker label="صلاحية العنصر" value={days} onChange={setDays} />

            <UploadBox title={editing ? "استبدال ملف العنصر (اختياري)" : "ملف العنصر"} description={kind === "frame" ? "PNG / WebP / JPG — ستُحافظ المعالجة على الشفافية." : kind === "entry_effect" ? "MP4 / WebM أو صورة — الدخلة حتى 20 ثانية، والأطول يُقص تلقائيًا إلى 20 ثانية." : "صورة أو MP4/WebM — الخلفية المتحركة حتى 5 ثوانٍ، والأطول يُقص تلقائيًا إلى 5 ثوانٍ ثم يعمل Loop."} file={file} onChange={setFile} accept={kind === "frame" ? "image/png,image/webp,image/jpeg" : "image/*,video/mp4,video/webm,video/quicktime"} />
            <UploadBox title="صورة مصغرة مخصصة — اختياري" description="لو سيبتها فارغة، اللوحة تنشئ Thumbnail تلقائيًا من الصورة أو لقطة من الفيديو." file={thumbnail} onChange={setThumbnail} accept="image/*" compact />

            {kind === "entry_effect" && (
              <div className="space-y-2 rounded-2xl border border-violet-500/15 bg-violet-500/[0.04] p-3">
                <div>
                  <Label>طريقة تجهيز الدخلة</Label>
                  <p className="mt-1 text-[10px] leading-5 text-muted-foreground">اختار بالظبط المطلوب للدخلة: تفضل كما هي، تنعيم الحواف فقط، أو إزالة الخلفية بالذكاء الاصطناعي.</p>
                </div>
                <Select value={entryMode} onValueChange={(v) => setEntryMode(v as EntryProcessingMode)}>
                  <SelectTrigger className="rounded-xl"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="source">زي ما هي — بدون تعديل</SelectItem>
                    <SelectItem value="edges">تنعيم الحواف — بدون إزالة الخلفية</SelectItem>
                    <SelectItem value="ai">إزالة الخلفية AI</SelectItem>
                  </SelectContent>
                </Select>
                <div className="rounded-xl border bg-background/50 p-2.5 text-[11px] leading-5 text-muted-foreground">
                  {entryMode === "source" && "سيتم القص عند 20 ثانية وتجهيز الملف فقط، بدون تغيير الخلفية أو الحواف أو المؤثرات."}
                  {entryMode === "edges" && "سيتم تنعيم الحواف وتقليل التكسير حول التفاصيل مع الحفاظ على الخلفية كاملة كما هي."}
                  {entryMode === "ai" && "سيحاول إزالة الخلفية وإنشاء نسخة شفافة. النسخة الأصلية تظل محفوظة ويمكن الرجوع لها من بطاقة الدخلة."}
                </div>
              </div>
            )}
            <div className="grid gap-3 sm:grid-cols-2">
              {kind === "frame" && <ToggleCard icon={WandSparkles} title="تنظيف خلفية الإطار" description="ينظف الخلفية المتصلة بالحواف ويحافظ على الرسم الداخلي." checked={removeBg} onCheckedChange={setRemoveBg} />}
              {kind === "entry_effect" && <ToggleCard icon={audio ? Volume2 : VolumeX} title="تشغيل صوت الدخلة" description="لو مقفول، التطبيق يعرض الدخلة بدون صوت." checked={audio} onCheckedChange={setAudio} />}
              <ToggleCard icon={ShieldCheck} title="متاح للمستخدمين" description="لن يصبح متاحًا فعليًا إلا بعد حالة «جاهز»." checked={enabled} onCheckedChange={setEnabled} />
            </div>
          </div>
          <div className="space-y-3">
            <div className="flex items-center justify-between gap-2"><Label>معاينة داخل الروم</Label>{kind === "entry_effect" && <Badge variant="outline" className="rounded-full">منتصف الروم • Center + Fit</Badge>}</div>
            <div className="relative grid min-h-[360px] place-items-center overflow-hidden rounded-3xl border bg-gradient-to-br from-violet-950/55 via-slate-950/80 to-orange-950/25 p-4">
              {kind === "entry_effect" && <><div className="pointer-events-none absolute inset-x-4 top-4 flex justify-between"><div className="h-8 w-24 rounded-full border border-white/10 bg-black/20"/><div className="h-8 w-20 rounded-full border border-white/10 bg-black/20"/></div><div className="pointer-events-none absolute inset-x-6 bottom-5 grid grid-cols-4 gap-4 opacity-35">{[1,2,3,4].map((n)=><div key={n} className="mx-auto h-10 w-10 rounded-full border border-white/25 bg-black/25"/>)}</div></>}
              {preview ? (file?.type.startsWith("video/") || (!file && asset?.media_type === "video") ? <video src={preview} controls muted={!audio} loop className="max-h-[430px] max-w-full rounded-2xl object-contain" /> : <img src={preview} alt="معاينة" className="max-h-[430px] max-w-full rounded-2xl object-contain" />) : <div className="text-center text-muted-foreground"><Upload className="mx-auto mb-3 h-10 w-10" /><div className="font-bold">المعاينة تظهر هنا</div><div className="mt-1 text-xs">ارفع الملف فقط، ولا تحتاج صورة مصغرة منفصلة.</div></div>}
              <Badge className="absolute left-3 top-3 rounded-full bg-black/55 text-white">{kindLabel[kind]}</Badge>
            </div>
            <div className="rounded-2xl border border-violet-500/15 bg-violet-500/5 p-3 text-xs leading-6 text-muted-foreground">
              <strong className="text-foreground">المعالجة الآمنة:</strong> الدخلة تظهر في منتصف الروم بنظام Center + Fit بدون قص أو مطّ وتحافظ على نسبة الأبعاد. «زي ما هي» لا تعدّل الصورة، «تنعيم الحواف» يحافظ على الخلفية، و«إزالة الخلفية AI» هو الوحيد الذي ينشئ شفافية. الحد الأقصى 20 ثانية والصوت اختياري.
            </div>
          </div>
        </div>
        <DialogFooter className="gap-2 sm:justify-start">
          <Button disabled={mutation.isPending} className="min-w-36 rounded-xl bg-gradient-to-l from-violet-600 to-orange-500 font-bold" onClick={() => mutation.mutate()}>{mutation.isPending ? <><Loader2 className="ml-2 h-4 w-4 animate-spin" />{busyText || "جاري الحفظ…"}</> : editing ? "حفظ التعديلات" : "معالجة وحفظ"}</Button>
          <Button variant="outline" className="rounded-xl" disabled={mutation.isPending} onClick={() => onOpenChange(false)}>إلغاء</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function Field({ label, children }: { label: string; children: ReactNode }) { return <div className="space-y-1.5"><Label>{label}</Label>{children}</div>; }


const durationPresets = [1, 3, 7, 15, 30, 90, 180, 365] as const;

function DurationDaysPicker({ label, value, onChange }: { label: string; value: string; onChange: (value: string) => void }) {
  const days = Number(value);
  const hasDays = value.trim() !== "" && Number.isFinite(days) && days > 0;
  const normalized = hasDays ? String(Math.floor(days)) : "";
  const expiry = hasDays
    ? new Intl.DateTimeFormat("ar-EG-u-nu-latn", { year: "numeric", month: "short", day: "2-digit" }).format(new Date(Date.now() + Math.floor(days) * 86_400_000))
    : null;

  return (
    <div className="space-y-2.5 rounded-2xl border border-violet-500/15 bg-violet-500/[0.04] p-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <Label>{label}</Label>
        <Badge variant="outline" className={`rounded-full ${hasDays ? "border-violet-500/30 text-violet-300" : "border-emerald-500/30 text-emerald-400"}`}>
          {hasDays ? `${normalized} يوم` : "دائم"}
        </Badge>
      </div>
      <div className="flex flex-wrap gap-2" dir="ltr">
        <Button type="button" size="sm" variant={!hasDays ? "default" : "outline"} className="h-8 rounded-xl px-3" onClick={() => onChange("")}>دائم</Button>
        {durationPresets.map((preset) => (
          <Button
            key={preset}
            type="button"
            size="sm"
            variant={normalized === String(preset) ? "default" : "outline"}
            className="h-8 rounded-xl px-3 tabular-nums"
            onClick={() => onChange(String(preset))}
          >
            {preset} يوم
          </Button>
        ))}
      </div>
      <div className="grid gap-2 sm:grid-cols-[1fr_auto] sm:items-center">
        <Input
          type="number"
          min={1}
          step={1}
          value={value}
          onChange={(e) => onChange(e.target.value)}
          placeholder="عدد أيام مخصص"
          className="rounded-xl font-mono tabular-nums"
          dir="ltr"
        />
        <div className="min-w-44 text-[11px] leading-5 text-muted-foreground">
          {expiry ? <>تاريخ الانتهاء المتوقع: <span dir="ltr" className="font-semibold text-foreground">{expiry}</span></> : "بدون تاريخ انتهاء حتى يتم تغييره."}
        </div>
      </div>
    </div>
  );
}

function UploadBox({ title, description, file, onChange, accept, compact=false }: { title: string; description: string; file: File | null; onChange: (f: File | null) => void; accept: string; compact?: boolean }) {
  return (
    <label className={`block cursor-pointer rounded-2xl border border-dashed border-violet-500/30 bg-violet-500/5 transition hover:bg-violet-500/10 ${compact ? "p-3" : "p-4"}`}>
      <input type="file" accept={accept} className="hidden" onChange={(e) => onChange(e.target.files?.[0] ?? null)} />
      <div className="flex items-center gap-3">
        <div className="rounded-xl bg-violet-500/15 p-2.5 text-violet-400"><Upload className="h-5 w-5" /></div>
        <div className="min-w-0 flex-1"><div className="font-bold">{title}</div><div className="mt-0.5 text-[11px] leading-5 text-muted-foreground">{description}</div><div className="mt-1 truncate text-xs font-semibold text-orange-400">{publicFileName(file)}</div></div>
      </div>
    </label>
  );
}

function ToggleCard({ icon: Icon, title, description, checked, onCheckedChange }: { icon: typeof Sparkles; title: string; description: string; checked: boolean; onCheckedChange: (v: boolean) => void }) {
  return <div className="flex items-start gap-3 rounded-2xl border bg-muted/25 p-3"><div className="rounded-xl bg-background p-2"><Icon className="h-4 w-4 text-violet-400" /></div><div className="min-w-0 flex-1"><div className="text-sm font-bold">{title}</div><div className="mt-1 text-[10px] leading-4 text-muted-foreground">{description}</div></div><Switch checked={checked} onCheckedChange={onCheckedChange} /></div>;
}

function GrantDialog({ asset, onClose, onSaved }: { asset: AssetRow | null; onClose: () => void; onSaved: () => void }) {
  const [userId, setUserId] = useState("");
  const [selectedUser, setSelectedUser] = useState<YamoAdminUserLookup | null>(null);
  const [days, setDays] = useState("");
  const [reason, setReason] = useState("منح من لوحة التحكم");
  const lookupTerm = userId.trim();
  const lookupQ = useQuery({
    queryKey: ["admin-user-grant-lookup", lookupTerm],
    queryFn: () => searchYamoAdminUsers(lookupTerm, 6),
    enabled: Boolean(asset) && !selectedUser && lookupTerm.length > 0,
    staleTime: 10_000,
  });

  const resetAndClose = () => {
    setUserId("");
    setSelectedUser(null);
    setDays("");
    setReason("منح من لوحة التحكم");
    onClose();
  };

  const chooseUser = (user: YamoAdminUserLookup) => {
    setSelectedUser(user);
    setUserId(user.legacy_id);
  };

  const mutation = useMutation({
    mutationFn: () => yamoRpc("admin_grant_user_asset", { p_legacy_id: selectedUser?.legacy_id, p_asset_kind: asset?.asset_kind, p_asset_key: asset?.asset_key, p_days: days.trim() ? Number(days) : null, p_reason: reason.trim() || null }),
    onSuccess: () => { toast.success(`تم إرسال المقتنى إلى ${selectedUser?.display_name || selectedUser?.legacy_id || "المستخدم"}`); onSaved(); resetAndClose(); },
    onError: (e) => toast.error(errorMessage(e)),
  });

  return (
    <Dialog open={Boolean(asset)} onOpenChange={(v) => !v && resetAndClose()}>
      <DialogContent dir="rtl" className="max-w-lg">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2"><Send className="h-5 w-5 text-violet-400" /> منح لمستخدم</DialogTitle>
          <DialogDescription>{asset ? `${asset.name_ar ?? asset.asset_key} — ${asset.asset_key}` : ""}</DialogDescription>
        </DialogHeader>
        <div className="space-y-4">
          <Field label="ID المستخدم">
            {selectedUser ? (
              <SelectedGrantUser user={selectedUser} onChange={() => { setSelectedUser(null); setUserId(""); }} />
            ) : (
              <div className="space-y-2">
                <div className="relative">
                  <Search className="pointer-events-none absolute right-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
                  <Input
                    value={userId}
                    onChange={(e) => setUserId(e.target.value)}
                    placeholder="اكتب ID المستخدم، مثال 100025"
                    className="rounded-xl pr-9"
                    dir="ltr"
                    autoComplete="off"
                  />
                </div>
                {lookupQ.isFetching && <div className="flex items-center gap-2 rounded-xl border bg-muted/25 px-3 py-2 text-xs text-muted-foreground"><Loader2 className="h-3.5 w-3.5 animate-spin" /> جاري البحث عن الحساب…</div>}
                {!lookupQ.isFetching && lookupTerm && lookupQ.isError && <div className="rounded-xl border border-destructive/30 bg-destructive/5 px-3 py-2 text-xs text-destructive">تعذر البحث عن المستخدم. حاول مرة أخرى.</div>}
                {!lookupQ.isFetching && lookupTerm && !lookupQ.isError && (lookupQ.data?.length ?? 0) === 0 && <div className="rounded-xl border border-dashed px-3 py-2 text-xs text-muted-foreground">لا يوجد حساب بهذا الـID.</div>}
                {(lookupQ.data?.length ?? 0) > 0 && (
                  <div className="max-h-64 space-y-2 overflow-y-auto rounded-2xl border bg-card/80 p-2 shadow-lg">
                    {lookupQ.data!.map((user) => <GrantUserSearchResult key={user.id} user={user} onSelect={() => chooseUser(user)} />)}
                  </div>
                )}
              </div>
            )}
          </Field>
          <DurationDaysPicker label="مدة المنح" value={days} onChange={setDays} />
          <Field label="سبب المنح"><Textarea value={reason} onChange={(e) => setReason(e.target.value)} className="rounded-xl" /></Field>
        </div>
        <DialogFooter className="gap-2 sm:justify-start">
          <Button disabled={!selectedUser || mutation.isPending} onClick={() => mutation.mutate()} className="rounded-xl">{mutation.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : "إرسال للمستخدم"}</Button>
          <Button variant="outline" className="rounded-xl" onClick={resetAndClose}>إلغاء</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function GrantUserSearchResult({ user, onSelect }: { user: YamoAdminUserLookup; onSelect: () => void }) {
  return (
    <button type="button" onClick={onSelect} className="flex w-full items-center gap-3 rounded-xl border border-transparent p-2.5 text-right transition hover:border-violet-500/30 hover:bg-violet-500/10">
      <UserAvatar user={user} />
      <div className="min-w-0 flex-1">
        <div className="truncate text-sm font-black">{user.display_name || "بدون اسم"}</div>
        <div className="mt-0.5 flex flex-wrap items-center gap-2 text-[11px] text-muted-foreground">
          <span dir="ltr" className="font-mono font-bold text-violet-300">ID: {user.legacy_id}</span>
          {user.level != null && <span>LVL {user.level}</span>}
          {(user.vip_level ?? 0) > 0 && <span className="text-orange-400">VIP {user.vip_level}</span>}
        </div>
      </div>
      <BadgeCheck className="h-5 w-5 shrink-0 text-violet-400" />
    </button>
  );
}

function SelectedGrantUser({ user, onChange }: { user: YamoAdminUserLookup; onChange: () => void }) {
  return (
    <div className="flex items-center gap-3 rounded-2xl border border-emerald-500/30 bg-emerald-500/5 p-3">
      <UserAvatar user={user} />
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2"><span className="truncate text-sm font-black">{user.display_name || "بدون اسم"}</span><Badge className="rounded-full bg-emerald-500/15 text-emerald-400 hover:bg-emerald-500/15">تم الاختيار</Badge></div>
        <div className="mt-1 flex flex-wrap items-center gap-2 text-[11px] text-muted-foreground"><span dir="ltr" className="font-mono font-bold text-foreground">ID: {user.legacy_id}</span>{user.level != null && <span>LVL {user.level}</span>}{(user.vip_level ?? 0) > 0 && <span className="text-orange-400">VIP {user.vip_level}</span>}{user.account_status && <span>{user.account_status}</span>}</div>
      </div>
      <Button type="button" size="sm" variant="outline" className="shrink-0 rounded-xl" onClick={onChange}>تغيير</Button>
    </div>
  );
}

function UserAvatar({ user }: { user: YamoAdminUserLookup }) {
  if (user.avatar_url) return <img src={user.avatar_url} alt={user.display_name} className="h-11 w-11 shrink-0 rounded-full border object-cover" />;
  return <div className="grid h-11 w-11 shrink-0 place-items-center rounded-full border bg-gradient-to-br from-violet-500/20 to-orange-500/20 text-sm font-black">{(user.display_name || user.legacy_id || "?").slice(0, 1).toUpperCase()}</div>;
}

function PreviewDialog({ asset, onClose }: { asset: AssetRow | null; onClose: () => void }) {
  const url = String(asset?.media_url || asset?.preview_url || "");
  const meta = parseMetadata(asset?.metadata);
  const audioUrl = typeof meta.audio_url === "string" ? meta.audio_url : "";
  return <Dialog open={Boolean(asset)} onOpenChange={(v) => !v && onClose()}><DialogContent dir="rtl" className="max-w-3xl"><DialogHeader><DialogTitle>{asset?.name_ar ?? asset?.asset_key}</DialogTitle><DialogDescription><span dir="ltr">{asset?.asset_key}</span> — {asset ? kindLabel[asset.asset_kind] : ""}</DialogDescription></DialogHeader><div className="grid min-h-96 place-items-center overflow-hidden rounded-3xl border bg-[linear-gradient(45deg,#111827_25%,#1f2937_25%,#1f2937_50%,#111827_50%,#111827_75%,#1f2937_75%)] bg-[length:28px_28px] p-4">{url ? asset?.media_type === "video" ? <video src={url} controls autoPlay loop muted={!asset.audio_enabled} className="max-h-[65vh] max-w-full object-contain" /> : <img src={url} alt="معاينة" className="max-h-[65vh] max-w-full object-contain" /> : <div className="text-muted-foreground">لا توجد معاينة</div>}</div>{audioUrl && asset?.audio_enabled && <audio src={audioUrl} controls className="mt-3 w-full" />}</DialogContent></Dialog>;
}

function RewardsPanel({ rules, queue, loading, assets, onAdd, onEdit, onRefresh }: { rules: RewardRule[]; queue: Record<string, unknown>[]; loading: boolean; assets: AssetRow[]; onAdd: () => void; onEdit: (r: RewardRule) => void; onRefresh: () => void }) {
  const pending = queue.filter((q) => !q.granted_at);
  return <div className="space-y-4"><div className="flex flex-wrap items-center justify-between gap-3 rounded-2xl border bg-card/70 p-4"><div><h2 className="font-black">المكافآت التلقائية</h2><p className="text-xs leading-6 text-muted-foreground">اربط دخلة أو إطار أو خلفية بـLevel أو Event أو مهمة أو إنفاق كوينز. القاعدة الواحدة تقدر تمنح أكثر من عنصر معًا.</p></div><Button className="rounded-xl bg-emerald-600 hover:bg-emerald-700" onClick={onAdd}><Plus className="ml-2 h-4 w-4" /> قاعدة جديدة</Button></div><div className="grid gap-3 md:grid-cols-3"><StatCard icon={Gift} label="القواعد" value={rules.length} note="قواعد المنح التلقائي" /><StatCard icon={Clock3} label="في الانتظار" value={pending.length} note="مكافآت لم يحن موعدها" /><StatCard icon={Users} label="العناصر الجاهزة" value={assets.length} note="صالحة للربط بالمكافآت" /></div>{loading ? <div className="grid min-h-48 place-items-center"><Loader2 className="h-6 w-6 animate-spin" /></div> : <div className="grid gap-4 xl:grid-cols-2">{rules.map((rule) => <RewardRuleCard key={rule.id} rule={rule} onEdit={() => onEdit(rule)} onDeleted={onRefresh} />)}{!rules.length && <div className="col-span-full grid min-h-52 place-items-center rounded-2xl border border-dashed text-sm text-muted-foreground">لم تُنشأ قواعد مكافآت بعد.</div>}</div>}</div>;
}

function RewardRuleCard({ rule, onEdit, onDeleted }: { rule: RewardRule; onEdit: () => void; onDeleted: () => void }) {
  const items = readRuleItems(rule.items);
  const trigger = rule.trigger_type === "game_spend" ? `لعب بـ ${Number(rule.trigger_value).toLocaleString("en-US")} كوينز` : rule.trigger_type === "level" ? `الوصول إلى Level ${rule.trigger_value}` : rule.trigger_type === "event" ? `فعالية: ${rule.trigger_key ?? "—"}` : rule.trigger_type === "task" ? `مهمة: ${rule.trigger_key ?? "—"}` : `${rule.trigger_value} أيام دخول`;
  const delay = rule.delay_mode === "next_day" ? "اليوم التالي" : rule.delay_mode === "hours" ? `بعد ${rule.delay_hours} ساعة` : "فورًا";
  return <Card className="border-emerald-500/15 bg-card/90"><CardContent className="space-y-4 p-4"><div className="flex items-start justify-between gap-3"><div><div className="flex items-center gap-2"><h3 className="font-black">{rule.name_ar}</h3><Badge variant="outline" className={rule.enabled ? "border-emerald-500/30 text-emerald-400" : "text-muted-foreground"}>{rule.enabled ? "مفعلة" : "متوقفة"}</Badge></div><p className="mt-1 text-xs text-muted-foreground">{trigger} • {delay}</p></div><Gift className="h-5 w-5 text-emerald-400" /></div><div className="flex flex-wrap gap-2">{items.map((i) => <Badge key={`${i.asset_kind}:${i.asset_key}`} className="rounded-full bg-violet-500/10 text-violet-300 hover:bg-violet-500/10"><span dir="ltr">{i.asset_key}</span> · {kindLabel[i.asset_kind]}</Badge>)}</div><div className="flex gap-2 border-t pt-3"><Button size="sm" variant="outline" className="rounded-xl" onClick={onEdit}><Pencil className="ml-1 h-3.5 w-3.5" /> تعديل</Button><Button size="sm" variant="outline" className="rounded-xl text-destructive hover:text-destructive" onClick={async () => { if (!window.confirm("حذف قاعدة المكافأة؟")) return; try { await yamoRpc("admin_delete_asset_reward_rule", { p_rule_id: rule.id }); toast.success("تم حذف القاعدة"); onDeleted(); } catch (e) { toast.error(errorMessage(e)); } }}><Trash2 className="ml-1 h-3.5 w-3.5" /> حذف</Button></div></CardContent></Card>;
}

function RewardRuleDialog({ open, onOpenChange, rule, assets, onSaved }: { open: boolean; onOpenChange: (v: boolean) => void; rule?: RewardRule; assets: AssetRow[]; onSaved: () => void }) {
  const existing = readRuleItems(rule?.items);
  const [name, setName] = useState(rule?.name_ar ?? "");
  const [triggerType, setTriggerType] = useState(rule?.trigger_type ?? "game_spend");
  const [triggerKey, setTriggerKey] = useState(rule?.trigger_key ?? "GAME_SPEND_COINS");
  const [triggerValue, setTriggerValue] = useState(String(rule?.trigger_value ?? 50000));
  const [delayMode, setDelayMode] = useState(rule?.delay_mode ?? "next_day");
  const [delayHours, setDelayHours] = useState(String(rule?.delay_hours ?? 0));
  const [enabled, setEnabled] = useState(rule?.enabled ?? true);
  const [reward1, setReward1] = useState(existing[0] ? `${existing[0].asset_kind}:${existing[0].asset_key}` : "");
  const [reward2, setReward2] = useState(existing[1] ? `${existing[1].asset_kind}:${existing[1].asset_key}` : "none");
  const [rewardDays, setRewardDays] = useState(existing[0]?.grant_days ? String(existing[0].grant_days) : "");
  const mutation = useMutation({
    mutationFn: async () => {
      if (!name.trim()) throw new Error("اكتب اسم قاعدة المكافأة");
      if (!reward1) throw new Error("اختر المكافأة الأولى");
      const selected = [reward1, reward2 !== "none" ? reward2 : ""].filter(Boolean).map((value, index) => {
        const [asset_kind, asset_key] = value.split(":") as [MediaAssetKind, string];
        return { asset_kind, asset_key, grant_days: rewardDays.trim() ? Number(rewardDays) : null, sort_order: index };
      });
      await yamoRpc("admin_upsert_asset_reward_rule", {
        p_rule_id: rule?.id ?? null,
        p_payload: {
          name_ar: name.trim(), trigger_type: triggerType, trigger_key: triggerType === "game_spend" ? "GAME_SPEND_COINS" : triggerKey.trim() || null,
          trigger_value: triggerType === "event" ? 1 : Math.max(1, Number(triggerValue || 1)), window_type: triggerType === "game_spend" ? "daily" : triggerType === "event" ? "event" : "lifetime",
          delay_mode: delayMode, delay_hours: delayMode === "hours" ? Math.max(0, Number(delayHours || 0)) : 0, enabled,
        },
        p_items: selected,
      });
    },
    onSuccess: () => { toast.success("تم حفظ قاعدة المكافأة"); onSaved(); },
    onError: (e) => toast.error(errorMessage(e)),
  });
  const identity = `${open}:${rule?.id ?? "new"}`;
  return <RewardDialogInner key={identity} {...{ open,onOpenChange,rule,assets,onSaved,name,setName,triggerType,setTriggerType,triggerKey,setTriggerKey,triggerValue,setTriggerValue,delayMode,setDelayMode,delayHours,setDelayHours,enabled,setEnabled,reward1,setReward1,reward2,setReward2,rewardDays,setRewardDays,mutation }} />;
}

function RewardDialogInner({ open,onOpenChange,assets,name,setName,triggerType,setTriggerType,triggerKey,setTriggerKey,triggerValue,setTriggerValue,delayMode,setDelayMode,delayHours,setDelayHours,enabled,setEnabled,reward1,setReward1,reward2,setReward2,rewardDays,setRewardDays,mutation }: any) {
  return <Dialog open={open} onOpenChange={(v) => !mutation.isPending && onOpenChange(v)}><DialogContent dir="rtl" className="max-w-2xl"><DialogHeader><DialogTitle className="flex items-center gap-2"><Gift className="h-5 w-5 text-emerald-400" /> قاعدة مكافأة تلقائية</DialogTitle><DialogDescription>مثال: إنفاق 50,000 كوينز اليوم → دخلة + إطار في اليوم التالي.</DialogDescription></DialogHeader><div className="grid gap-4 sm:grid-cols-2"><Field label="اسم القاعدة"><Input value={name} onChange={(e) => setName(e.target.value)} placeholder="مكافأة 50 ألف كوينز" className="rounded-xl" /></Field><Field label="نوع الشرط"><Select value={triggerType} onValueChange={(v) => { setTriggerType(v); if (v === "game_spend") { setTriggerKey("GAME_SPEND_COINS"); setTriggerValue("50000"); setDelayMode("next_day"); } }}><SelectTrigger className="rounded-xl"><SelectValue /></SelectTrigger><SelectContent><SelectItem value="game_spend">لعب / إنفاق كوينز</SelectItem><SelectItem value="level">Level</SelectItem><SelectItem value="event">فعالية</SelectItem></SelectContent></Select></Field><Field label={triggerType === "level" ? "رقم الـLevel" : triggerType === "game_spend" ? "إجمالي الكوينز" : "كود الفعالية"}>{triggerType === "event" ? <Input value={triggerKey} onChange={(e) => setTriggerKey(e.target.value)} className="rounded-xl" /> : <Input type="number" min={1} value={triggerValue} onChange={(e) => setTriggerValue(e.target.value)} className="rounded-xl font-mono" dir="ltr" />}</Field><Field label="موعد النزول"><Select value={delayMode} onValueChange={setDelayMode}><SelectTrigger className="rounded-xl"><SelectValue /></SelectTrigger><SelectContent><SelectItem value="immediate">فورًا</SelectItem><SelectItem value="next_day">اليوم التالي</SelectItem><SelectItem value="hours">بعد عدد ساعات</SelectItem></SelectContent></Select></Field>{delayMode === "hours" && <Field label="عدد الساعات"><Input type="number" min={0} value={delayHours} onChange={(e) => setDelayHours(e.target.value)} className="rounded-xl font-mono" dir="ltr" /></Field>}<Field label="المكافأة الأولى"><AssetSelect value={reward1} onChange={setReward1} assets={assets} allowNone={false} /></Field><Field label="المكافأة الثانية — اختياري"><AssetSelect value={reward2} onChange={setReward2} assets={assets} allowNone /></Field><div className="sm:col-span-2"><DurationDaysPicker label="صلاحية المكافأة" value={rewardDays} onChange={setRewardDays} /></div><div className="sm:col-span-2"><ToggleCard icon={ShieldCheck} title="القاعدة مفعلة" description="عند الإيقاف لن تُنشأ مكافآت جديدة من هذه القاعدة." checked={enabled} onCheckedChange={setEnabled} /></div></div>{triggerType === "game_spend" && <div className="rounded-xl border border-amber-500/20 bg-amber-500/5 p-3 text-xs leading-6 text-amber-200">الحساب آمن: قيمة اللعب لا تأتي من الموبايل. يجب أن يسجل Backend اللعبة الإنفاق الحقيقي في <span dir="ltr" className="font-mono">yamo_record_reward_metric(..., 'GAME_SPEND_COINS', amount)</span>.</div>}<DialogFooter className="gap-2 sm:justify-start"><Button disabled={mutation.isPending} className="rounded-xl bg-emerald-600 hover:bg-emerald-700" onClick={() => mutation.mutate()}>{mutation.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : "حفظ القاعدة"}</Button><Button variant="outline" className="rounded-xl" onClick={() => onOpenChange(false)}>إلغاء</Button></DialogFooter></DialogContent></Dialog>;
}

function AssetSelect({ value, onChange, assets, allowNone }: { value: string; onChange: (v: string) => void; assets: AssetRow[]; allowNone: boolean }) {
  return <Select value={value || (allowNone ? "none" : undefined)} onValueChange={onChange}><SelectTrigger className="rounded-xl"><SelectValue placeholder="اختر المقتنى" /></SelectTrigger><SelectContent>{allowNone && <SelectItem value="none">بدون مكافأة ثانية</SelectItem>}{assets.map((a) => <SelectItem key={`${a.asset_kind}:${a.asset_key}`} value={`${a.asset_kind}:${a.asset_key}`}><span dir="ltr">{a.asset_key}</span> — {a.name_ar ?? kindLabel[a.asset_kind]}</SelectItem>)}</SelectContent></Select>;
}

function parseMetadata(value: AssetRow["metadata"]) {
  if (!value) return {} as Record<string, unknown>;
  if (typeof value === "string") { try { return JSON.parse(value) as Record<string, unknown>; } catch { return {}; } }
  return value as Record<string, unknown>;
}
function readStoragePaths(value: AssetRow["metadata"]) {
  const meta = parseMetadata(value);
  return Array.isArray(meta.storage_paths) ? meta.storage_paths.map(String) : [];
}
function readRuleItems(value: RewardRule["items"] | undefined): RewardItem[] {
  if (!value) return [];
  if (Array.isArray(value)) return value as RewardItem[];
  if (typeof value === "string") { try { const v=JSON.parse(value); return Array.isArray(v) ? v as RewardItem[] : []; } catch { return []; } }
  return [];
}
function errorMessage(error: unknown) { return error instanceof Error ? error.message : String(error ?? "حدث خطأ غير متوقع"); }
