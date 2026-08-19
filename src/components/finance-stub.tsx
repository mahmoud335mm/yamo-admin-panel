import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Wrench } from "lucide-react";

/**
 * لوحة مؤقتة لصفحات قسم "الشحن والسحب" بينما تُنشأ جداولها في المرحلة B.
 * لا تنفّذ أي عمليات مالية — تعرض فقط هيكل القسم والصلاحيات المرتبطة به.
 */
export function FinanceStub({ title, description, features }: { title: string; description: string; features: string[] }) {
  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold">{title}</h1>
        <p className="text-sm text-muted-foreground">{description}</p>
      </div>
      <Card className="border-dashed">
        <CardHeader className="flex flex-row items-start gap-3">
          <Wrench className="mt-1 h-5 w-5 text-orange-500" />
          <div>
            <CardTitle>قيد الإنشاء — المرحلة B</CardTitle>
            <CardDescription>
              الواجهة جاهزة، وجداول قاعدة البيانات ستُنشأ في Migration واحدة كبيرة عند الانتقال إلى المرحلة B.
              لا تُنفَّذ أي عمليات مالية من هذه الصفحة قبل ذلك.
            </CardDescription>
          </div>
        </CardHeader>
        <CardContent>
          <ul className="list-inside list-disc space-y-1 text-sm text-muted-foreground">
            {features.map((f) => <li key={f}>{f}</li>)}
          </ul>
        </CardContent>
      </Card>
    </div>
  );
}
