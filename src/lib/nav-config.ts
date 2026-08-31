import {
  LayoutDashboard,
  Users,
  Building2,
  Mic,
  Megaphone,
  DoorOpen,
  ArrowRightLeft,
  MessageSquare,
  FileText,
  Wallet,
  ArrowDownUp,
  Gift,
  Gamepad2,
  Calendar,
  Image as ImageIcon,
  CalendarCheck,
  Bell,
  Flag,
  Bot,
  BarChart3,
  Settings,
  ShieldCheck,
  ScrollText,
  Mail,
  Lock,
  Zap,
  UserCog,
  Coins,
  Sparkle,
  ShoppingBag,
  Repeat,
  SlidersHorizontal,
  DollarSign,
  Package,
  CreditCard,
  Landmark,
  Receipt,
  LineChart,
  Scale,
  BookOpen,
  HandCoins,
  Crown,
  BadgeCheck,
  HeartHandshake,
  UsersRound,
  UserRoundX,
  ScanFace,
  Headphones,
  Gavel,
  Smartphone,
  Activity,
  Network,
  UserCheck,
} from "lucide-react";

export type NavChild = {
  to: string;
  labelAr: string;
  labelEn: string;
  icon: typeof LayoutDashboard;
  permission?: string;
};

export type NavItem = NavChild & {
  children?: NavChild[];
};

/**
 * لوحة تحكم Yamo Chat — القائمة الجانبية النهائية (23 قسمًا رئيسيًا).
 * الأقسام المكررة تم دمجها كـ children تحت قسم واحد.
 */
export const navItems: NavItem[] = [
  {
    to: "/dashboard",
    labelAr: "الرئيسية",
    labelEn: "Dashboard",
    icon: LayoutDashboard,
    permission: "dashboard.view",
  },
  { to: "/users", labelAr: "المستخدمون", labelEn: "Users", icon: Users, permission: "users.read" },
  {
    to: "/account-deletions",
    labelAr: "طلبات حذف الحساب",
    labelEn: "Account Deletions",
    icon: UserRoundX,
    permission: "users.read",
  },
  {
    to: "/verifications",
    labelAr: "التحقق من الهوية",
    labelEn: "Verification",
    icon: ScanFace,
    permission: "verification.manage",
  },
  {
    to: "/moderation",
    labelAr: "العقوبات والحظر",
    labelEn: "Moderation",
    icon: Gavel,
    permission: "users.moderate",
  },
  {
    to: "/vip-levels",
    labelAr: "VIP والمستويات",
    labelEn: "VIP & Levels",
    icon: Crown,
    permission: "gifts.read",
  },
  {
    to: "/distinctive-ids",
    labelAr: "الـ ID المميز",
    labelEn: "Distinctive ID",
    icon: BadgeCheck,
    permission: "gifts.read",
  },
  {
    to: "/relationships",
    labelAr: "علاقات CP والأخوة",
    labelEn: "Relationships",
    icon: HeartHandshake,
    permission: "users.read",
  },
  {
    to: "/families",
    labelAr: "العائلات",
    labelEn: "Families",
    icon: UsersRound,
    permission: "users.read",
  },

  // 3. إدارة الوكالات
  {
    to: "/agencies",
    labelAr: "إدارة الوكالات",
    labelEn: "Agencies Management",
    icon: Building2,
    permission: "agencies.read",
    children: [
      {
        to: "/agencies",
        labelAr: "الوكالات",
        labelEn: "Agencies",
        icon: Building2,
        permission: "agencies.read",
      },
      { to: "/hosts", labelAr: "المضيفون", labelEn: "Hosts", icon: Mic, permission: "hosts.read" },
    ],
  },

  { to: "/rooms", labelAr: "الغرف", labelEn: "Rooms", icon: DoorOpen, permission: "rooms.read" },
  {
    to: "/messages",
    labelAr: "الرسائل والمكالمات",
    labelEn: "Messages",
    icon: MessageSquare,
    permission: "messages.read",
  },
  {
    to: "/posts",
    labelAr: "المنشورات",
    labelEn: "Posts",
    icon: FileText,
    permission: "posts.read",
  },

  // 8. الاقتصاد والمحافظ
  {
    to: "/economy",
    labelAr: "الاقتصاد والمحافظ",
    labelEn: "Economy",
    icon: Wallet,
    permission: "economy.read",
    children: [
      {
        to: "/economy",
        labelAr: "المحافظ ودفتر القيود",
        labelEn: "Wallets & Ledger",
        icon: BookOpen,
        permission: "economy.read",
      },
      {
        to: "/wallet-adjustments",
        labelAr: "تعديلات الأرصدة",
        labelEn: "Adjustments",
        icon: SlidersHorizontal,
        permission: "wallets.coins.credit",
      },
    ],
  },

  // 9. الشحن والسحب
  {
    to: "/finance",
    labelAr: "الشحن والسحب",
    labelEn: "Recharge & Withdrawal",
    icon: ArrowDownUp,
    permission: "economy.read",
    children: [
      {
        to: "/finance",
        labelAr: "نظرة عامة",
        labelEn: "Overview",
        icon: LineChart,
        permission: "economy.read",
      },
      {
        to: "/finance/packages",
        labelAr: "باقات الشحن",
        labelEn: "Recharge Packages",
        icon: Package,
        permission: "economy.read",
      },
      {
        to: "/finance/coin-prices",
        labelAr: "أسعار الكوينز",
        labelEn: "Coin Prices",
        icon: Coins,
        permission: "economy.read",
      },
      {
        to: "/finance/payment-methods",
        labelAr: "وسائل الدفع",
        labelEn: "Payment Methods",
        icon: CreditCard,
        permission: "economy.read",
      },
      {
        to: "/finance/recharge-requests",
        labelAr: "طلبات الشحن",
        labelEn: "Recharge Requests",
        icon: Receipt,
        permission: "economy.read",
      },
      {
        to: "/finance/withdrawal-requests",
        labelAr: "طلبات السحب",
        labelEn: "Withdrawal Requests",
        icon: HandCoins,
        permission: "economy.read",
      },
      {
        to: "/finance/pearl-prices",
        labelAr: "أسعار اللؤلؤ والورد",
        labelEn: "Pearl Prices",
        icon: Sparkle,
        permission: "economy.read",
      },
      {
        to: "/finance/withdrawal-settings",
        labelAr: "إعدادات السحب",
        labelEn: "Withdrawal Settings",
        icon: Scale,
        permission: "economy.read",
      },
      {
        to: "/finance/reports",
        labelAr: "تقارير الشحن والسحب",
        labelEn: "Finance Reports",
        icon: BarChart3,
        permission: "economy.read",
      },
    ],
  },

  {
    to: "/charging-agencies",
    labelAr: "منظومة وكلاء الشحن",
    labelEn: "Charging Network",
    icon: Network,
    permission: "charging_agencies.read",
    children: [
      { to: "/charging-agencies", labelAr: "وكالات الشحن", labelEn: "Charging Agencies", icon: Building2, permission: "charging_agencies.read" },
      { to: "/charging-agents", labelAr: "وكلاء الشحن", labelEn: "Charging Agents", icon: UserCheck, permission: "charging_agents.read" },
      { to: "/charging-pricing", labelAr: "تسعير وهوامش الشحن", labelEn: "Pricing & Margins", icon: DollarSign, permission: "charging_pricing.read" },
      { to: "/charging-coin-transfers", labelAr: "تحويلات الكوينز", labelEn: "Coin Transfers", icon: Coins, permission: "charging_transfers.read" },
      { to: "/charging-pearl-transfers", labelAr: "تحويلات اللؤلؤ", labelEn: "Pearl Transfers", icon: Sparkle, permission: "charging_transfers.read" },
      { to: "/bd", labelAr: "مديرو تطوير الأعمال", labelEn: "Business Development", icon: HandCoins, permission: "bd.read" },
    ],
  },

  {
    to: "/gifts",
    labelAr: "الهدايا والمتجر والمقتنيات",
    labelEn: "Gifts, Store & Inventory",
    icon: Gift,
    permission: "gifts.read",
    children: [
      { to: "/gifts", labelAr: "الهدايا", labelEn: "Gifts", icon: Gift, permission: "gifts.read" },
      {
        to: "/inventory",
        labelAr: "المقتنيات والمؤثرات",
        labelEn: "Media Inventory",
        icon: Package,
        permission: "gifts.read",
      },
    ],
  },
  { to: "/games", labelAr: "الألعاب", labelEn: "Games", icon: Gamepad2, permission: "games.read" },
  {
    to: "/events",
    labelAr: "الفعاليات",
    labelEn: "Events",
    icon: Calendar,
    permission: "events.read",
  },
  {
    to: "/banners",
    labelAr: "البنرات والرسائل الفورية",
    labelEn: "Banners & Instant Messages",
    icon: ImageIcon,
    permission: "banners.read",
  },
  {
    to: "/daily-login",
    labelAr: "جوائز تسجيل الدخول",
    labelEn: "Daily Login",
    icon: CalendarCheck,
    permission: "daily_login.read",
  },
  {
    to: "/notifications",
    labelAr: "الإشعارات",
    labelEn: "Notifications",
    icon: Bell,
    permission: "notifications.read",
  },
  {
    to: "/support-tickets",
    labelAr: "تذاكر الدعم",
    labelEn: "Support Tickets",
    icon: Headphones,
    permission: "support.manage",
  },
  {
    to: "/reports",
    labelAr: "البلاغات",
    labelEn: "Reports",
    icon: Flag,
    permission: "reports.read",
  },
  {
    to: "/analytics",
    labelAr: "التقارير والتحليلات",
    labelEn: "Analytics",
    icon: BarChart3,
    permission: "analytics.read",
  },
  {
    to: "/settings",
    labelAr: "الإعدادات",
    labelEn: "Settings",
    icon: Settings,
    permission: "settings.read",
  },
  {
    to: "/app-releases",
    labelAr: "نسخ التطبيق والتحديث",
    labelEn: "App Releases",
    icon: Smartphone,
    permission: "releases.manage",
  },
  {
    to: "/operations",
    labelAr: "مراقبة التشغيل",
    labelEn: "Operations",
    icon: Activity,
    permission: "notifications.send",
  },
  {
    to: "/admins",
    labelAr: "مسؤولو اللوحة",
    labelEn: "Admins",
    icon: ShieldCheck,
    permission: "admin.users.read",
  },
  {
    to: "/admins/invites",
    labelAr: "دعوات المسؤولين",
    labelEn: "Invites",
    icon: Mail,
    permission: "admin.users.write",
  },
  {
    to: "/security-check",
    labelAr: "فحص الأمان",
    labelEn: "Security Check",
    icon: Lock,
    permission: "admin.users.read",
  },
  {
    to: "/audit",
    labelAr: "سجل العمليات",
    labelEn: "Audit Log",
    icon: ScrollText,
    permission: "audit.read",
  },
];

/** Flat list of all nav entries (parents + children) for search / breadcrumbs. */
export const flatNavItems: NavChild[] = navItems.flatMap((n) =>
  n.children && n.children.length > 0
    ? n.children
    : [
        {
          to: n.to,
          labelAr: n.labelAr,
          labelEn: n.labelEn,
          icon: n.icon,
          permission: n.permission,
        },
      ],
);
