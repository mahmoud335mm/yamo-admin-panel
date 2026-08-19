import { createFileRoute, useNavigate, useSearch } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { lovable } from "@/integrations/lovable";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Sparkles, Loader2, Mail, ShieldCheck } from "lucide-react";
import { logAudit } from "@/lib/audit";
import { Badge } from "@/components/ui/badge";

type Search = { invite?: string };

export const Route = createFileRoute("/auth")({
  validateSearch: (s: Record<string, unknown>): Search => ({ invite: typeof s.invite === "string" ? s.invite : undefined }),
  component: AuthPage,
});

const INVITE_ERRORS: Record<string, string> = {
  revoked: "تم إلغاء هذه الدعوة.",
  accepted: "هذه الدعوة مستخدمة بالفعل.",
  expired: "انتهت صلاحية هذه الدعوة.",
  invalid: "رابط الدعوة غير صالح.",
};

function AuthPage() {
  const navigate = useNavigate();
  const { invite: inviteToken } = useSearch({ from: "/auth" });
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [fullName, setFullName] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [info, setInfo] = useState<string | null>(null);
  const [invitePreview, setInvitePreview] = useState<{ email: string; role: string; status: string } | null>(null);
  const [inviteError, setInviteError] = useState<string | null>(null);
  const [tab, setTab] = useState<"signin" | "signup">(inviteToken ? "signup" : "signin");

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      if (data.session && !inviteToken) navigate({ to: "/dashboard", replace: true });
    });
  }, [navigate, inviteToken]);

  // Preview invite
  useEffect(() => {
    if (!inviteToken) return;
    (async () => {
      const { data, error } = await supabase.rpc("preview_admin_invite", { _token: inviteToken });
      if (error || !data || data.length === 0) {
        setInviteError(INVITE_ERRORS.invalid);
        return;
      }
      const row = data[0];
      setInvitePreview({ email: row.email, role: row.role, status: row.status });
      setEmail(row.email);
      if (row.status !== "pending") setInviteError(INVITE_ERRORS[row.status] ?? INVITE_ERRORS.invalid);
    })();
  }, [inviteToken]);

  const acceptInviteIfPresent = async () => {
    if (!inviteToken) return;
    const { error } = await supabase.rpc("accept_admin_invite", { _token: inviteToken });
    if (error) {
      const msg = error.message ?? "";
      if (msg.includes("EMAIL_MISMATCH")) throw new Error("البريد المستخدم لا يطابق بريد الدعوة.");
      if (msg.includes("INVITE_ALREADY_USED")) throw new Error(INVITE_ERRORS.accepted);
      if (msg.includes("INVITE_REVOKED")) throw new Error(INVITE_ERRORS.revoked);
      if (msg.includes("INVITE_EXPIRED")) throw new Error(INVITE_ERRORS.expired);
      throw new Error(INVITE_ERRORS.invalid);
    }
  };

  const signIn = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true); setError(null); setInfo(null);
    try {
      const { error } = await supabase.auth.signInWithPassword({ email, password });
      if (error) throw new Error(error.message);
      await acceptInviteIfPresent();
      await logAudit("auth.signin", "admin_users", undefined, { method: "password", via_invite: !!inviteToken });
      navigate({ to: "/dashboard", replace: true });
    } catch (e) {
      setError(e instanceof Error ? e.message : "خطأ");
    } finally { setLoading(false); }
  };

  const signUp = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true); setError(null); setInfo(null);
    if (inviteToken && invitePreview && email.toLowerCase() !== invitePreview.email.toLowerCase()) {
      setLoading(false);
      return setError("يجب استخدام نفس بريد الدعوة: " + invitePreview.email);
    }
    try {
      const { error, data } = await supabase.auth.signUp({
        email, password,
        options: {
          emailRedirectTo: `${window.location.origin}/dashboard`,
          data: { full_name: fullName, ...(inviteToken ? { invite_token: inviteToken } : {}) },
        },
      });
      if (error) throw new Error(error.message);
      if (data.session) {
        await acceptInviteIfPresent();
        navigate({ to: "/dashboard", replace: true });
      } else {
        setInfo("تم إنشاء الحساب. تحقق من بريدك لتفعيله ثم عد لتسجيل الدخول.");
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : "خطأ");
    } finally { setLoading(false); }
  };

  const google = async () => {
    setLoading(true); setError(null);
    // Persist token so callback can accept after OAuth
    if (inviteToken) sessionStorage.setItem("pending_invite_token", inviteToken);
    const res = await lovable.auth.signInWithOAuth("google", { redirect_uri: window.location.origin });
    setLoading(false);
    if (res.error) setError(res.error.message ?? "فشل تسجيل الدخول بجوجل");
  };

  const inviteBlocked = !!inviteError;

  return (
    <div dir="rtl" className="grid min-h-screen place-items-center bg-gradient-to-br from-orange-50 via-background to-purple-50 p-6 dark:from-slate-950 dark:via-background dark:to-slate-900">
      <Card className="w-full max-w-md border-orange-200/60 shadow-xl dark:border-slate-800">
        <CardHeader className="text-center">
          <div className="mx-auto mb-3 grid h-14 w-14 place-items-center rounded-2xl bg-gradient-to-br from-orange-500 to-purple-600 text-white shadow-lg">
            <Sparkles className="h-6 w-6" />
          </div>
          <CardTitle className="text-2xl">لوحة تحكم يامو شات</CardTitle>
          <CardDescription>Yamo Chat Admin Console — تسجيل دخول المسؤولين</CardDescription>
        </CardHeader>
        <CardContent>
          {invitePreview && !inviteError && (
            <Alert className="mb-4">
              <ShieldCheck className="h-4 w-4" />
              <AlertDescription className="space-y-1">
                <div className="font-semibold">دعوة إدارية</div>
                <div className="flex items-center gap-2 text-xs">
                  <Mail className="h-3.5 w-3.5" /> {invitePreview.email}
                  <Badge variant="secondary">{invitePreview.role}</Badge>
                </div>
              </AlertDescription>
            </Alert>
          )}
          {inviteError && (
            <Alert variant="destructive" className="mb-4"><AlertDescription>{inviteError}</AlertDescription></Alert>
          )}

          <Tabs value={tab} onValueChange={(v) => setTab(v as "signin"|"signup")} className="w-full">
            <TabsList className="grid w-full grid-cols-2">
              <TabsTrigger value="signin">دخول</TabsTrigger>
              <TabsTrigger value="signup">حساب جديد</TabsTrigger>
            </TabsList>

            <TabsContent value="signin">
              <form onSubmit={signIn} className="space-y-4 pt-4">
                <div className="space-y-2">
                  <Label htmlFor="email">البريد الإلكتروني</Label>
                  <Input id="email" type="email" required value={email} onChange={(e) => setEmail(e.target.value)} dir="ltr" />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="password">كلمة المرور</Label>
                  <Input id="password" type="password" required value={password} onChange={(e) => setPassword(e.target.value)} dir="ltr" />
                </div>
                <Button type="submit" className="w-full" disabled={loading || inviteBlocked}>
                  {loading && <Loader2 className="ml-2 h-4 w-4 animate-spin" />}
                  {inviteToken ? "دخول وقبول الدعوة" : "تسجيل الدخول"}
                </Button>
              </form>
            </TabsContent>

            <TabsContent value="signup">
              <form onSubmit={signUp} className="space-y-4 pt-4">
                <div className="space-y-2">
                  <Label htmlFor="fn">الاسم الكامل</Label>
                  <Input id="fn" value={fullName} onChange={(e) => setFullName(e.target.value)} required />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="email2">البريد الإلكتروني</Label>
                  <Input id="email2" type="email" required value={email} onChange={(e) => setEmail(e.target.value)} dir="ltr" disabled={!!invitePreview} />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="password2">كلمة المرور</Label>
                  <Input id="password2" type="password" required minLength={6} value={password} onChange={(e) => setPassword(e.target.value)} dir="ltr" />
                </div>
                <Button type="submit" className="w-full" disabled={loading || inviteBlocked}>
                  {loading && <Loader2 className="ml-2 h-4 w-4 animate-spin" />}
                  {inviteToken ? "إنشاء الحساب وقبول الدعوة" : "إنشاء حساب"}
                </Button>
                {!inviteToken && (
                  <p className="text-center text-[11px] text-muted-foreground">
                    التسجيل العام مغلق. أول حساب فقط يصبح Super Admin. لاحقًا يجب استخدام دعوة.
                  </p>
                )}
              </form>
            </TabsContent>
          </Tabs>

          <div className="relative my-4">
            <div className="absolute inset-0 flex items-center"><span className="w-full border-t" /></div>
            <div className="relative flex justify-center text-xs"><span className="bg-card px-2 text-muted-foreground">أو</span></div>
          </div>

          <Button variant="outline" className="w-full" onClick={google} disabled={loading || inviteBlocked}>
            <svg className="ml-2 h-4 w-4" viewBox="0 0 24 24"><path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/><path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/><path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"/><path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/></svg>
            المتابعة عبر Google
          </Button>

          {error && <Alert variant="destructive" className="mt-4"><AlertDescription>{error}</AlertDescription></Alert>}
          {info && <Alert className="mt-4"><AlertDescription>{info}</AlertDescription></Alert>}
        </CardContent>
      </Card>
    </div>
  );
}
