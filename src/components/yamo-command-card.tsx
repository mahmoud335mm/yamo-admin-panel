import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Loader2, Save } from "lucide-react";
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
    <Card>
      <CardHeader>
        <CardTitle className="text-base">{title}</CardTitle>
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
              </div>
            ),
          )}
          <div className="flex items-end">
            <Button className="w-full" disabled={command.isPending} type="submit">
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
