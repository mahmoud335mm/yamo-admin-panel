import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { ImageIcon, Loader2, Save, Sparkles } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { yamoRpc } from "@/lib/yamo-admin";

export type CommandField = {
  key: string;
  label: string;
  type?: "text" | "number" | "datetime-local" | "checkbox";
  placeholder?: string;
  required?: boolean;
  initial?: string | boolean;
};

type Props = {
  title: string;
  description: string;
  rpc: string;
  fields: CommandField[];
  refreshSource?: string;
  refreshSources?: string[];
  submitLabel?: string;
  buildArgs: (values: Record<string, string | boolean>) => Record<string, unknown>;
};

export function YamoCommandCard({
  title,
  description,
  rpc,
  fields,
  refreshSource,
  refreshSources = [],
  submitLabel = "حفظ وتنفيذ",
  buildArgs,
}: Props) {
  const initial = Object.fromEntries(
    fields.map((field) => [field.key, field.initial ?? (field.type === "checkbox" ? true : "")]),
  ) as Record<string, string | boolean>;
  const [values, setValues] = useState(initial);
  const client = useQueryClient();
  const command = useMutation({
    mutationFn: () => yamoRpc(rpc, buildArgs(values)),
    onSuccess: async () => {
      toast.success("تم تنفيذ العملية وتسجيلها في سجل العمليات");
      if (refreshSource)
        await client.invalidateQueries({ queryKey: ["yamo-admin", refreshSource] });
      for (const source of refreshSources)
        await client.invalidateQueries({ queryKey: ["yamo-admin", source] });
    },
    onError: (error: Error) => toast.error(error.message),
  });

  return (
    <Card className="overflow-hidden border-violet-500/15 bg-card/90 shadow-sm backdrop-blur-xl">
      <CardHeader className="border-b bg-gradient-to-l from-violet-500/10 via-transparent to-orange-500/5">
        <CardTitle className="flex items-center gap-2 text-base"><Sparkles className="h-4 w-4 text-violet-500" />{title}</CardTitle>
        <CardDescription>{description}</CardDescription>
      </CardHeader>
      <CardContent>
        <form
          className="grid gap-4 md:grid-cols-2 xl:grid-cols-3"
          onSubmit={(event) => {
            event.preventDefault();
            command.mutate();
          }}
        >
          {fields.map((field) =>
            field.type === "checkbox" ? (
              <label
                key={field.key}
                className="flex h-10 items-center gap-3 rounded-md border px-3 text-sm"
              >
                <input
                  type="checkbox"
                  checked={Boolean(values[field.key])}
                  onChange={(event) =>
                    setValues((old) => ({ ...old, [field.key]: event.target.checked }))
                  }
                />
                {field.label}
              </label>
            ) : (
              <div key={field.key} className="space-y-1.5">
                <Label htmlFor={`${rpc}-${field.key}`}>{field.label}</Label>
                <Input
                  id={`${rpc}-${field.key}`}
                  type={field.type ?? "text"}
                  required={field.required}
                  placeholder={field.placeholder}
                  value={String(values[field.key] ?? "")}
                  onChange={(event) =>
                    setValues((old) => ({ ...old, [field.key]: event.target.value }))
                  }
                />
                {/(image|avatar|banner|cover|icon)/i.test(field.key) && /^https?:\/\//.test(String(values[field.key] ?? "")) && (
                  <div className="flex items-center gap-2 rounded-xl border bg-muted/30 p-2">
                    <img src={String(values[field.key])} alt={field.label} className="h-14 w-14 rounded-xl border bg-muted object-cover" />
                    <span className="flex items-center gap-1 text-xs text-muted-foreground"><ImageIcon className="h-3.5 w-3.5" />معاينة الملف قبل الحفظ</span>
                  </div>
                )}
              </div>
            ),
          )}
          <div className="flex items-end">
            <Button className="w-full rounded-xl bg-gradient-to-l from-violet-600 to-fuchsia-600 shadow-lg shadow-violet-950/20" disabled={command.isPending} type="submit">
              {command.isPending ? (
                <Loader2 className="ml-2 h-4 w-4 animate-spin" />
              ) : (
                <Save className="ml-2 h-4 w-4" />
              )}
              {submitLabel}
            </Button>
          </div>
        </form>
      </CardContent>
    </Card>
  );
}
