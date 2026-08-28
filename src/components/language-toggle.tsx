import { Languages } from "lucide-react";
import { Button } from "@/components/ui/button";
import { setAdminLanguage, useAdminLanguage } from "@/lib/admin-language";

export function LanguageToggle() {
  const language = useAdminLanguage();
  const next = language === "ar" ? "en" : "ar";
  return (
    <Button
      type="button"
      variant="outline"
      size="sm"
      onClick={() => setAdminLanguage(next)}
      className="h-9 gap-2 rounded-xl border-violet-500/25 px-3 font-black shadow-md shadow-violet-500/10"
      title={language === "ar" ? "Switch to English" : "التبديل إلى العربية"}
    >
      <Languages className="h-4 w-4" />
      <span>{language === "ar" ? "English" : "العربية"}</span>
    </Button>
  );
}
