import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Construction } from "lucide-react";

export function ModulePlaceholder({ title, description, phase }: { title: string; description: string; phase: string }) {
  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold">{title}</h1>
        <p className="text-sm text-muted-foreground">{description}</p>
      </div>
      <Card className="border-dashed">
        <CardHeader className="text-center">
          <Construction className="mx-auto h-10 w-10 text-orange-500" />
          <CardTitle className="mt-3">هذه الوحدة قيد التنفيذ</CardTitle>
          <CardDescription>سيتم بناء الشاشات الكاملة ضمن {phase}. الصلاحيات و RLS و Route جاهزة الآن.</CardDescription>
        </CardHeader>
        <CardContent className="text-center text-xs text-muted-foreground">
          راجع <code className="rounded bg-muted px-1.5 py-0.5">docs/07-implementation-phases.md</code> لمعرفة تفاصيل المرحلة.
        </CardContent>
      </Card>
    </div>
  );
}
