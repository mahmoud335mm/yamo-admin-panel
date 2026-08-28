import { useSyncExternalStore } from "react";

export type AdminLanguage = "ar" | "en";
const eventName = "yamo-admin-language";

export function getAdminLanguage(): AdminLanguage {
  if (typeof window === "undefined") return "ar";
  return window.localStorage.getItem("yamo-admin-language") === "en" ? "en" : "ar";
}

export function setAdminLanguage(language: AdminLanguage) {
  window.localStorage.setItem("yamo-admin-language", language);
  document.documentElement.lang = language;
  document.documentElement.dir = language === "ar" ? "rtl" : "ltr";
  document.body.dataset.adminLanguage = language;
  window.dispatchEvent(new Event(eventName));
}

export function useAdminLanguage() {
  return useSyncExternalStore(
    (notify) => {
      window.addEventListener(eventName, notify);
      window.addEventListener("storage", notify);
      return () => {
        window.removeEventListener(eventName, notify);
        window.removeEventListener("storage", notify);
      };
    },
    getAdminLanguage,
    () => "ar" as AdminLanguage,
  );
}
