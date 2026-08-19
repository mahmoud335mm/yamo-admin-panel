export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      admin_invites: {
        Row: {
          accepted_at: string | null
          accepted_by: string | null
          created_at: string
          email: string
          expires_at: string
          id: string
          invited_by: string | null
          revoked_at: string | null
          revoked_by: string | null
          role: Database["public"]["Enums"]["admin_role"]
          token_hash: string | null
        }
        Insert: {
          accepted_at?: string | null
          accepted_by?: string | null
          created_at?: string
          email: string
          expires_at?: string
          id?: string
          invited_by?: string | null
          revoked_at?: string | null
          revoked_by?: string | null
          role: Database["public"]["Enums"]["admin_role"]
          token_hash?: string | null
        }
        Update: {
          accepted_at?: string | null
          accepted_by?: string | null
          created_at?: string
          email?: string
          expires_at?: string
          id?: string
          invited_by?: string | null
          revoked_at?: string | null
          revoked_by?: string | null
          role?: Database["public"]["Enums"]["admin_role"]
          token_hash?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "admin_invites_accepted_by_fkey"
            columns: ["accepted_by"]
            isOneToOne: false
            referencedRelation: "admin_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "admin_invites_invited_by_fkey"
            columns: ["invited_by"]
            isOneToOne: false
            referencedRelation: "admin_users"
            referencedColumns: ["id"]
          },
        ]
      }
      admin_notes: {
        Row: {
          author_id: string
          body: string
          created_at: string
          entity_id: string
          entity_type: string
          id: string
        }
        Insert: {
          author_id: string
          body: string
          created_at?: string
          entity_id: string
          entity_type: string
          id?: string
        }
        Update: {
          author_id?: string
          body?: string
          created_at?: string
          entity_id?: string
          entity_type?: string
          id?: string
        }
        Relationships: [
          {
            foreignKeyName: "admin_notes_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "admin_users"
            referencedColumns: ["id"]
          },
        ]
      }
      admin_role_assignments: {
        Row: {
          admin_user_id: string
          created_at: string
          granted_by: string | null
          id: string
          role: Database["public"]["Enums"]["admin_role"]
        }
        Insert: {
          admin_user_id: string
          created_at?: string
          granted_by?: string | null
          id?: string
          role: Database["public"]["Enums"]["admin_role"]
        }
        Update: {
          admin_user_id?: string
          created_at?: string
          granted_by?: string | null
          id?: string
          role?: Database["public"]["Enums"]["admin_role"]
        }
        Relationships: [
          {
            foreignKeyName: "admin_role_assignments_admin_user_id_fkey"
            columns: ["admin_user_id"]
            isOneToOne: false
            referencedRelation: "admin_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "admin_role_assignments_granted_by_fkey"
            columns: ["granted_by"]
            isOneToOne: false
            referencedRelation: "admin_users"
            referencedColumns: ["id"]
          },
        ]
      }
      admin_users: {
        Row: {
          avatar_url: string | null
          created_at: string
          email: string
          full_name: string | null
          id: string
          is_active: boolean
          last_login_at: string | null
          phone: string | null
          updated_at: string
        }
        Insert: {
          avatar_url?: string | null
          created_at?: string
          email: string
          full_name?: string | null
          id: string
          is_active?: boolean
          last_login_at?: string | null
          phone?: string | null
          updated_at?: string
        }
        Update: {
          avatar_url?: string | null
          created_at?: string
          email?: string
          full_name?: string | null
          id?: string
          is_active?: boolean
          last_login_at?: string | null
          phone?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      agencies: {
        Row: {
          active_hosts: number
          bd_id: string | null
          bio: string | null
          close_reason: string | null
          closed_at: string | null
          closed_by: string | null
          code: string
          country: string | null
          cover_url: string | null
          created_at: string
          created_by: string | null
          deputy_user_id: string | null
          id: string
          join_policy: string
          language: string | null
          level_id: number | null
          logo_url: string | null
          monthly_coins: number
          monthly_hours: number
          name: string
          owner_user_id: string | null
          status: string
          total_hosts: number
          updated_at: string
        }
        Insert: {
          active_hosts?: number
          bd_id?: string | null
          bio?: string | null
          close_reason?: string | null
          closed_at?: string | null
          closed_by?: string | null
          code: string
          country?: string | null
          cover_url?: string | null
          created_at?: string
          created_by?: string | null
          deputy_user_id?: string | null
          id?: string
          join_policy?: string
          language?: string | null
          level_id?: number | null
          logo_url?: string | null
          monthly_coins?: number
          monthly_hours?: number
          name: string
          owner_user_id?: string | null
          status?: string
          total_hosts?: number
          updated_at?: string
        }
        Update: {
          active_hosts?: number
          bd_id?: string | null
          bio?: string | null
          close_reason?: string | null
          closed_at?: string | null
          closed_by?: string | null
          code?: string
          country?: string | null
          cover_url?: string | null
          created_at?: string
          created_by?: string | null
          deputy_user_id?: string | null
          id?: string
          join_policy?: string
          language?: string | null
          level_id?: number | null
          logo_url?: string | null
          monthly_coins?: number
          monthly_hours?: number
          name?: string
          owner_user_id?: string | null
          status?: string
          total_hosts?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "agencies_bd_id_fkey"
            columns: ["bd_id"]
            isOneToOne: false
            referencedRelation: "bd_managers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "agencies_level_id_fkey"
            columns: ["level_id"]
            isOneToOne: false
            referencedRelation: "agency_levels"
            referencedColumns: ["id"]
          },
        ]
      }
      agency_host_transfer_requests: {
        Row: {
          admin_decided_at: string | null
          admin_decided_by: string | null
          admin_decision: string | null
          admin_note: string | null
          bd_decided_at: string | null
          bd_decided_by: string | null
          bd_decision: string | null
          bd_note: string | null
          created_at: string
          created_by: string | null
          executed_at: string | null
          from_agency_id: string | null
          host_user_id: string
          id: string
          idempotency_key: string | null
          reason: string
          source_decided_at: string | null
          source_decided_by: string | null
          source_decision: string | null
          source_note: string | null
          status: string
          target_decided_at: string | null
          target_decided_by: string | null
          target_decision: string | null
          target_note: string | null
          to_agency_id: string
        }
        Insert: {
          admin_decided_at?: string | null
          admin_decided_by?: string | null
          admin_decision?: string | null
          admin_note?: string | null
          bd_decided_at?: string | null
          bd_decided_by?: string | null
          bd_decision?: string | null
          bd_note?: string | null
          created_at?: string
          created_by?: string | null
          executed_at?: string | null
          from_agency_id?: string | null
          host_user_id: string
          id?: string
          idempotency_key?: string | null
          reason: string
          source_decided_at?: string | null
          source_decided_by?: string | null
          source_decision?: string | null
          source_note?: string | null
          status?: string
          target_decided_at?: string | null
          target_decided_by?: string | null
          target_decision?: string | null
          target_note?: string | null
          to_agency_id: string
        }
        Update: {
          admin_decided_at?: string | null
          admin_decided_by?: string | null
          admin_decision?: string | null
          admin_note?: string | null
          bd_decided_at?: string | null
          bd_decided_by?: string | null
          bd_decision?: string | null
          bd_note?: string | null
          created_at?: string
          created_by?: string | null
          executed_at?: string | null
          from_agency_id?: string | null
          host_user_id?: string
          id?: string
          idempotency_key?: string | null
          reason?: string
          source_decided_at?: string | null
          source_decided_by?: string | null
          source_decision?: string | null
          source_note?: string | null
          status?: string
          target_decided_at?: string | null
          target_decided_by?: string | null
          target_decision?: string | null
          target_note?: string | null
          to_agency_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "agency_host_transfer_requests_from_agency_id_fkey"
            columns: ["from_agency_id"]
            isOneToOne: false
            referencedRelation: "agencies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "agency_host_transfer_requests_to_agency_id_fkey"
            columns: ["to_agency_id"]
            isOneToOne: false
            referencedRelation: "agencies"
            referencedColumns: ["id"]
          },
        ]
      }
      agency_join_requests: {
        Row: {
          agency_id: string
          created_at: string
          id: string
          message: string | null
          review_note: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          status: string
          user_id: string
        }
        Insert: {
          agency_id: string
          created_at?: string
          id?: string
          message?: string | null
          review_note?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
          user_id: string
        }
        Update: {
          agency_id?: string
          created_at?: string
          id?: string
          message?: string | null
          review_note?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "agency_join_requests_agency_id_fkey"
            columns: ["agency_id"]
            isOneToOne: false
            referencedRelation: "agencies"
            referencedColumns: ["id"]
          },
        ]
      }
      agency_level_history: {
        Row: {
          agency_id: string
          changed_by: string | null
          created_at: string
          id: string
          new_level: number | null
          old_level: number | null
          reason: string | null
        }
        Insert: {
          agency_id: string
          changed_by?: string | null
          created_at?: string
          id?: string
          new_level?: number | null
          old_level?: number | null
          reason?: string | null
        }
        Update: {
          agency_id?: string
          changed_by?: string | null
          created_at?: string
          id?: string
          new_level?: number | null
          old_level?: number | null
          reason?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "agency_level_history_agency_id_fkey"
            columns: ["agency_id"]
            isOneToOne: false
            referencedRelation: "agencies"
            referencedColumns: ["id"]
          },
        ]
      }
      agency_levels: {
        Row: {
          commission_pct: number
          created_at: string
          id: number
          min_active_hosts: number
          min_monthly_coins: number
          name: string
          perks: Json
        }
        Insert: {
          commission_pct?: number
          created_at?: string
          id: number
          min_active_hosts?: number
          min_monthly_coins?: number
          name: string
          perks?: Json
        }
        Update: {
          commission_pct?: number
          created_at?: string
          id?: number
          min_active_hosts?: number
          min_monthly_coins?: number
          name?: string
          perks?: Json
        }
        Relationships: []
      }
      agency_members: {
        Row: {
          agency_id: string
          assigned_by: string | null
          created_at: string
          id: string
          member_role: string
          user_id: string
        }
        Insert: {
          agency_id: string
          assigned_by?: string | null
          created_at?: string
          id?: string
          member_role: string
          user_id: string
        }
        Update: {
          agency_id?: string
          assigned_by?: string | null
          created_at?: string
          id?: string
          member_role?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "agency_members_agency_id_fkey"
            columns: ["agency_id"]
            isOneToOne: false
            referencedRelation: "agencies"
            referencedColumns: ["id"]
          },
        ]
      }
      agency_tasks: {
        Row: {
          agency_id: string
          created_at: string
          id: string
          period_month: number
          period_year: number
          progress_value: number
          status: string
          target_type: string
          target_value: number
        }
        Insert: {
          agency_id: string
          created_at?: string
          id?: string
          period_month: number
          period_year: number
          progress_value?: number
          status?: string
          target_type: string
          target_value: number
        }
        Update: {
          agency_id?: string
          created_at?: string
          id?: string
          period_month?: number
          period_year?: number
          progress_value?: number
          status?: string
          target_type?: string
          target_value?: number
        }
        Relationships: [
          {
            foreignKeyName: "agency_tasks_agency_id_fkey"
            columns: ["agency_id"]
            isOneToOne: false
            referencedRelation: "agencies"
            referencedColumns: ["id"]
          },
        ]
      }
      agency_violations: {
        Row: {
          agency_id: string
          created_at: string
          created_by: string | null
          id: string
          penalty: Json
          reason: string
          severity: string
          type: string
        }
        Insert: {
          agency_id: string
          created_at?: string
          created_by?: string | null
          id?: string
          penalty?: Json
          reason: string
          severity?: string
          type: string
        }
        Update: {
          agency_id?: string
          created_at?: string
          created_by?: string | null
          id?: string
          penalty?: Json
          reason?: string
          severity?: string
          type?: string
        }
        Relationships: [
          {
            foreignKeyName: "agency_violations_agency_id_fkey"
            columns: ["agency_id"]
            isOneToOne: false
            referencedRelation: "agencies"
            referencedColumns: ["id"]
          },
        ]
      }
      audit_logs: {
        Row: {
          action: string
          actor_email: string | null
          actor_id: string | null
          created_at: string
          entity_id: string | null
          entity_type: string | null
          id: number
          ip_address: string | null
          metadata: Json
          user_agent: string | null
        }
        Insert: {
          action: string
          actor_email?: string | null
          actor_id?: string | null
          created_at?: string
          entity_id?: string | null
          entity_type?: string | null
          id?: number
          ip_address?: string | null
          metadata?: Json
          user_agent?: string | null
        }
        Update: {
          action?: string
          actor_email?: string | null
          actor_id?: string | null
          created_at?: string
          entity_id?: string | null
          entity_type?: string | null
          id?: number
          ip_address?: string | null
          metadata?: Json
          user_agent?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "audit_logs_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "admin_users"
            referencedColumns: ["id"]
          },
        ]
      }
      bd_agencies: {
        Row: {
          agency_id: string
          assigned_at: string
          assigned_by: string | null
          bd_id: string
          id: string
          released_at: string | null
        }
        Insert: {
          agency_id: string
          assigned_at?: string
          assigned_by?: string | null
          bd_id: string
          id?: string
          released_at?: string | null
        }
        Update: {
          agency_id?: string
          assigned_at?: string
          assigned_by?: string | null
          bd_id?: string
          id?: string
          released_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "bd_agencies_agency_id_fkey"
            columns: ["agency_id"]
            isOneToOne: false
            referencedRelation: "agencies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bd_agencies_bd_id_fkey"
            columns: ["bd_id"]
            isOneToOne: false
            referencedRelation: "bd_managers"
            referencedColumns: ["id"]
          },
        ]
      }
      bd_commissions: {
        Row: {
          agency_id: string | null
          bd_id: string
          commission_coins: number
          commission_pct: number
          created_at: string
          gross_coins: number
          id: string
          period_month: number
          period_year: number
          status: string
        }
        Insert: {
          agency_id?: string | null
          bd_id: string
          commission_coins?: number
          commission_pct: number
          created_at?: string
          gross_coins?: number
          id?: string
          period_month: number
          period_year: number
          status?: string
        }
        Update: {
          agency_id?: string | null
          bd_id?: string
          commission_coins?: number
          commission_pct?: number
          created_at?: string
          gross_coins?: number
          id?: string
          period_month?: number
          period_year?: number
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "bd_commissions_agency_id_fkey"
            columns: ["agency_id"]
            isOneToOne: false
            referencedRelation: "agencies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bd_commissions_bd_id_fkey"
            columns: ["bd_id"]
            isOneToOne: false
            referencedRelation: "bd_managers"
            referencedColumns: ["id"]
          },
        ]
      }
      bd_levels: {
        Row: {
          commission_pct: number
          created_at: string
          id: number
          min_agencies: number
          name: string
          perks: Json
        }
        Insert: {
          commission_pct?: number
          created_at?: string
          id: number
          min_agencies?: number
          name: string
          perks?: Json
        }
        Update: {
          commission_pct?: number
          created_at?: string
          id?: number
          min_agencies?: number
          name?: string
          perks?: Json
        }
        Relationships: []
      }
      bd_managers: {
        Row: {
          admin_user_id: string | null
          code: string
          country: string | null
          created_at: string
          created_by: string | null
          display_name: string
          email: string | null
          id: string
          level_id: number | null
          notes: string | null
          phone: string | null
          status: string
          updated_at: string
          user_id: string | null
        }
        Insert: {
          admin_user_id?: string | null
          code: string
          country?: string | null
          created_at?: string
          created_by?: string | null
          display_name: string
          email?: string | null
          id?: string
          level_id?: number | null
          notes?: string | null
          phone?: string | null
          status?: string
          updated_at?: string
          user_id?: string | null
        }
        Update: {
          admin_user_id?: string | null
          code?: string
          country?: string | null
          created_at?: string
          created_by?: string | null
          display_name?: string
          email?: string | null
          id?: string
          level_id?: number | null
          notes?: string | null
          phone?: string | null
          status?: string
          updated_at?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "bd_managers_admin_user_id_fkey"
            columns: ["admin_user_id"]
            isOneToOne: false
            referencedRelation: "admin_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bd_managers_level_id_fkey"
            columns: ["level_id"]
            isOneToOne: false
            referencedRelation: "bd_levels"
            referencedColumns: ["id"]
          },
        ]
      }
      charging_agencies: {
        Row: {
          admin_notes: string | null
          can_buy_pearls: boolean
          can_exchange_pearls_to_coins: boolean
          can_receive_from_agents: boolean
          can_sell_coins: boolean
          can_transfer_to_agents: boolean
          city: string | null
          commission_rate: number | null
          country: string | null
          cover_url: string | null
          created_at: string
          created_by: string | null
          daily_coin_transfer_limit: number | null
          daily_pearl_transfer_limit: number | null
          default_currency: string | null
          deleted_at: string | null
          deputy_user_id: string | null
          display_id: string
          email: string | null
          id: string
          level_id: number | null
          logo_url: string | null
          max_coin_transfer: number | null
          max_pearl_transfer: number | null
          min_coin_transfer: number | null
          min_pearl_transfer: number | null
          monthly_coin_transfer_limit: number | null
          monthly_pearl_transfer_limit: number | null
          name: string
          owner_user_id: string | null
          phone: string | null
          status: Database["public"]["Enums"]["charging_agency_status"]
          supported_payment_methods: Json
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          admin_notes?: string | null
          can_buy_pearls?: boolean
          can_exchange_pearls_to_coins?: boolean
          can_receive_from_agents?: boolean
          can_sell_coins?: boolean
          can_transfer_to_agents?: boolean
          city?: string | null
          commission_rate?: number | null
          country?: string | null
          cover_url?: string | null
          created_at?: string
          created_by?: string | null
          daily_coin_transfer_limit?: number | null
          daily_pearl_transfer_limit?: number | null
          default_currency?: string | null
          deleted_at?: string | null
          deputy_user_id?: string | null
          display_id?: string
          email?: string | null
          id?: string
          level_id?: number | null
          logo_url?: string | null
          max_coin_transfer?: number | null
          max_pearl_transfer?: number | null
          min_coin_transfer?: number | null
          min_pearl_transfer?: number | null
          monthly_coin_transfer_limit?: number | null
          monthly_pearl_transfer_limit?: number | null
          name: string
          owner_user_id?: string | null
          phone?: string | null
          status?: Database["public"]["Enums"]["charging_agency_status"]
          supported_payment_methods?: Json
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          admin_notes?: string | null
          can_buy_pearls?: boolean
          can_exchange_pearls_to_coins?: boolean
          can_receive_from_agents?: boolean
          can_sell_coins?: boolean
          can_transfer_to_agents?: boolean
          city?: string | null
          commission_rate?: number | null
          country?: string | null
          cover_url?: string | null
          created_at?: string
          created_by?: string | null
          daily_coin_transfer_limit?: number | null
          daily_pearl_transfer_limit?: number | null
          default_currency?: string | null
          deleted_at?: string | null
          deputy_user_id?: string | null
          display_id?: string
          email?: string | null
          id?: string
          level_id?: number | null
          logo_url?: string | null
          max_coin_transfer?: number | null
          max_pearl_transfer?: number | null
          min_coin_transfer?: number | null
          min_pearl_transfer?: number | null
          monthly_coin_transfer_limit?: number | null
          monthly_pearl_transfer_limit?: number | null
          name?: string
          owner_user_id?: string | null
          phone?: string | null
          status?: Database["public"]["Enums"]["charging_agency_status"]
          supported_payment_methods?: Json
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "charging_agencies_deputy_user_id_fkey"
            columns: ["deputy_user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "charging_agencies_owner_user_id_fkey"
            columns: ["owner_user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      charging_agency_daily_stats: {
        Row: {
          agency_id: string
          coins_sent: number | null
          day: string
          pearls_bought: number | null
          pearls_exchanged: number | null
          pearls_sent: number | null
          transfer_count: number | null
          updated_at: string
        }
        Insert: {
          agency_id: string
          coins_sent?: number | null
          day: string
          pearls_bought?: number | null
          pearls_exchanged?: number | null
          pearls_sent?: number | null
          transfer_count?: number | null
          updated_at?: string
        }
        Update: {
          agency_id?: string
          coins_sent?: number | null
          day?: string
          pearls_bought?: number | null
          pearls_exchanged?: number | null
          pearls_sent?: number | null
          transfer_count?: number | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "charging_agency_daily_stats_agency_id_fkey"
            columns: ["agency_id"]
            isOneToOne: false
            referencedRelation: "charging_agencies"
            referencedColumns: ["id"]
          },
        ]
      }
      charging_agency_members: {
        Row: {
          agency_id: string
          assigned_at: string
          assigned_by: string | null
          id: string
          member_role: Database["public"]["Enums"]["charging_agent_role"]
          removed_at: string | null
          status: Database["public"]["Enums"]["charging_agent_status"]
          user_id: string
        }
        Insert: {
          agency_id: string
          assigned_at?: string
          assigned_by?: string | null
          id?: string
          member_role?: Database["public"]["Enums"]["charging_agent_role"]
          removed_at?: string | null
          status?: Database["public"]["Enums"]["charging_agent_status"]
          user_id: string
        }
        Update: {
          agency_id?: string
          assigned_at?: string
          assigned_by?: string | null
          id?: string
          member_role?: Database["public"]["Enums"]["charging_agent_role"]
          removed_at?: string | null
          status?: Database["public"]["Enums"]["charging_agent_status"]
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "charging_agency_members_agency_id_fkey"
            columns: ["agency_id"]
            isOneToOne: false
            referencedRelation: "charging_agencies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "charging_agency_members_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      charging_agent_daily_stats: {
        Row: {
          agent_user_id: string
          coins_received: number | null
          coins_sent: number | null
          day: string
          pearls_bought: number | null
          pearls_exchanged: number | null
          pearls_received: number | null
          pearls_sent: number | null
          transfer_count: number | null
          updated_at: string
        }
        Insert: {
          agent_user_id: string
          coins_received?: number | null
          coins_sent?: number | null
          day: string
          pearls_bought?: number | null
          pearls_exchanged?: number | null
          pearls_received?: number | null
          pearls_sent?: number | null
          transfer_count?: number | null
          updated_at?: string
        }
        Update: {
          agent_user_id?: string
          coins_received?: number | null
          coins_sent?: number | null
          day?: string
          pearls_bought?: number | null
          pearls_exchanged?: number | null
          pearls_received?: number | null
          pearls_sent?: number | null
          transfer_count?: number | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "charging_agent_daily_stats_agent_user_id_fkey"
            columns: ["agent_user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      charging_agent_settings: {
        Row: {
          activated_at: string
          activated_by: string | null
          agency_id: string | null
          can_buy_pearls: boolean
          can_exchange_pearls_to_coins: boolean
          can_sell_coins: boolean
          can_transfer_to_agents: boolean
          confirmation_pin_hash: string | null
          daily_coin_limit: number | null
          daily_pearl_limit: number | null
          deactivated_at: string | null
          deactivated_by: string | null
          max_coin_transfer: number | null
          max_pearl_transfer: number | null
          min_coin_transfer: number | null
          min_pearl_transfer: number | null
          monthly_coin_limit: number | null
          monthly_pearl_limit: number | null
          status: Database["public"]["Enums"]["charging_agent_status"]
          suspend_reason: string | null
          suspended_at: string | null
          suspended_by: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          activated_at?: string
          activated_by?: string | null
          agency_id?: string | null
          can_buy_pearls?: boolean
          can_exchange_pearls_to_coins?: boolean
          can_sell_coins?: boolean
          can_transfer_to_agents?: boolean
          confirmation_pin_hash?: string | null
          daily_coin_limit?: number | null
          daily_pearl_limit?: number | null
          deactivated_at?: string | null
          deactivated_by?: string | null
          max_coin_transfer?: number | null
          max_pearl_transfer?: number | null
          min_coin_transfer?: number | null
          min_pearl_transfer?: number | null
          monthly_coin_limit?: number | null
          monthly_pearl_limit?: number | null
          status?: Database["public"]["Enums"]["charging_agent_status"]
          suspend_reason?: string | null
          suspended_at?: string | null
          suspended_by?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          activated_at?: string
          activated_by?: string | null
          agency_id?: string | null
          can_buy_pearls?: boolean
          can_exchange_pearls_to_coins?: boolean
          can_sell_coins?: boolean
          can_transfer_to_agents?: boolean
          confirmation_pin_hash?: string | null
          daily_coin_limit?: number | null
          daily_pearl_limit?: number | null
          deactivated_at?: string | null
          deactivated_by?: string | null
          max_coin_transfer?: number | null
          max_pearl_transfer?: number | null
          min_coin_transfer?: number | null
          min_pearl_transfer?: number | null
          monthly_coin_limit?: number | null
          monthly_pearl_limit?: number | null
          status?: Database["public"]["Enums"]["charging_agent_status"]
          suspend_reason?: string | null
          suspended_at?: string | null
          suspended_by?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "charging_agent_settings_agency_id_fkey"
            columns: ["agency_id"]
            isOneToOne: false
            referencedRelation: "charging_agencies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "charging_agent_settings_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      charging_coin_transfer_reversals: {
        Row: {
          id: string
          original_transfer_id: string
          reason: string
          reversed_at: string
          reversed_by: string
        }
        Insert: {
          id?: string
          original_transfer_id: string
          reason: string
          reversed_at?: string
          reversed_by: string
        }
        Update: {
          id?: string
          original_transfer_id?: string
          reason?: string
          reversed_at?: string
          reversed_by?: string
        }
        Relationships: [
          {
            foreignKeyName: "charging_coin_transfer_reversals_original_transfer_id_fkey"
            columns: ["original_transfer_id"]
            isOneToOne: true
            referencedRelation: "charging_coin_transfers"
            referencedColumns: ["id"]
          },
        ]
      }
      charging_coin_transfers: {
        Row: {
          agency_id: string | null
          agent_user_id: string
          amount: number
          commission_amount: number | null
          completed_at: string | null
          created_at: string
          currency: string | null
          id: string
          idempotency_key: string | null
          message_id: string | null
          note: string | null
          payment_method_id: string | null
          payment_reference: string | null
          receipt_url: string | null
          recipient_is_agent: boolean
          recipient_user_id: string
          reference: string
          reversed_by: string | null
          sale_price: number | null
          status: Database["public"]["Enums"]["charging_txn_status"]
        }
        Insert: {
          agency_id?: string | null
          agent_user_id: string
          amount: number
          commission_amount?: number | null
          completed_at?: string | null
          created_at?: string
          currency?: string | null
          id?: string
          idempotency_key?: string | null
          message_id?: string | null
          note?: string | null
          payment_method_id?: string | null
          payment_reference?: string | null
          receipt_url?: string | null
          recipient_is_agent?: boolean
          recipient_user_id: string
          reference?: string
          reversed_by?: string | null
          sale_price?: number | null
          status?: Database["public"]["Enums"]["charging_txn_status"]
        }
        Update: {
          agency_id?: string | null
          agent_user_id?: string
          amount?: number
          commission_amount?: number | null
          completed_at?: string | null
          created_at?: string
          currency?: string | null
          id?: string
          idempotency_key?: string | null
          message_id?: string | null
          note?: string | null
          payment_method_id?: string | null
          payment_reference?: string | null
          receipt_url?: string | null
          recipient_is_agent?: boolean
          recipient_user_id?: string
          reference?: string
          reversed_by?: string | null
          sale_price?: number | null
          status?: Database["public"]["Enums"]["charging_txn_status"]
        }
        Relationships: [
          {
            foreignKeyName: "charging_coin_transfers_agency_id_fkey"
            columns: ["agency_id"]
            isOneToOne: false
            referencedRelation: "charging_agencies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "charging_coin_transfers_agent_user_id_fkey"
            columns: ["agent_user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "charging_coin_transfers_recipient_user_id_fkey"
            columns: ["recipient_user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "charging_coin_transfers_reversed_by_fkey"
            columns: ["reversed_by"]
            isOneToOne: false
            referencedRelation: "charging_coin_transfers"
            referencedColumns: ["id"]
          },
        ]
      }
      charging_customers: {
        Row: {
          agency_id: string | null
          average_order_value: number | null
          coin_purchase_count: number | null
          country: string | null
          created_at: string
          debt_balance: number | null
          id: string
          internal_notes: string | null
          last_transaction_at: string | null
          name: string | null
          pearl_sale_count: number | null
          phone: string | null
          preferred_agent_id: string | null
          total_coin_amount_paid: number | null
          total_coins_purchased: number | null
          total_pearl_amount_received: number | null
          total_pearls_sold: number | null
          updated_at: string
          user_id: string
        }
        Insert: {
          agency_id?: string | null
          average_order_value?: number | null
          coin_purchase_count?: number | null
          country?: string | null
          created_at?: string
          debt_balance?: number | null
          id?: string
          internal_notes?: string | null
          last_transaction_at?: string | null
          name?: string | null
          pearl_sale_count?: number | null
          phone?: string | null
          preferred_agent_id?: string | null
          total_coin_amount_paid?: number | null
          total_coins_purchased?: number | null
          total_pearl_amount_received?: number | null
          total_pearls_sold?: number | null
          updated_at?: string
          user_id: string
        }
        Update: {
          agency_id?: string | null
          average_order_value?: number | null
          coin_purchase_count?: number | null
          country?: string | null
          created_at?: string
          debt_balance?: number | null
          id?: string
          internal_notes?: string | null
          last_transaction_at?: string | null
          name?: string | null
          pearl_sale_count?: number | null
          phone?: string | null
          preferred_agent_id?: string | null
          total_coin_amount_paid?: number | null
          total_coins_purchased?: number | null
          total_pearl_amount_received?: number | null
          total_pearls_sold?: number | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "charging_customers_agency_id_fkey"
            columns: ["agency_id"]
            isOneToOne: false
            referencedRelation: "charging_agencies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "charging_customers_preferred_agent_id_fkey"
            columns: ["preferred_agent_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "charging_customers_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      charging_debt_payments: {
        Row: {
          amount: number
          debt_id: string
          id: string
          method_code: string | null
          paid_at: string
          recorded_by: string | null
          reference: string | null
        }
        Insert: {
          amount: number
          debt_id: string
          id?: string
          method_code?: string | null
          paid_at?: string
          recorded_by?: string | null
          reference?: string | null
        }
        Update: {
          amount?: number
          debt_id?: string
          id?: string
          method_code?: string | null
          paid_at?: string
          recorded_by?: string | null
          reference?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "charging_debt_payments_debt_id_fkey"
            columns: ["debt_id"]
            isOneToOne: false
            referencedRelation: "charging_debts"
            referencedColumns: ["id"]
          },
        ]
      }
      charging_debts: {
        Row: {
          agency_id: string | null
          agent_user_id: string
          amount: number
          created_at: string
          currency: string
          customer_id: string
          due_at: string | null
          id: string
          reason: string | null
          settled_at: string | null
          status: string
        }
        Insert: {
          agency_id?: string | null
          agent_user_id: string
          amount: number
          created_at?: string
          currency?: string
          customer_id: string
          due_at?: string | null
          id?: string
          reason?: string | null
          settled_at?: string | null
          status?: string
        }
        Update: {
          agency_id?: string | null
          agent_user_id?: string
          amount?: number
          created_at?: string
          currency?: string
          customer_id?: string
          due_at?: string | null
          id?: string
          reason?: string | null
          settled_at?: string | null
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "charging_debts_agency_id_fkey"
            columns: ["agency_id"]
            isOneToOne: false
            referencedRelation: "charging_agencies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "charging_debts_agent_user_id_fkey"
            columns: ["agent_user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "charging_debts_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "charging_customers"
            referencedColumns: ["id"]
          },
        ]
      }
      charging_notifications: {
        Row: {
          body: string | null
          created_at: string
          entity_id: string | null
          entity_type: string | null
          event_type: string
          id: string
          read_at: string | null
          title: string
          user_id: string
        }
        Insert: {
          body?: string | null
          created_at?: string
          entity_id?: string | null
          entity_type?: string | null
          event_type: string
          id?: string
          read_at?: string | null
          title: string
          user_id: string
        }
        Update: {
          body?: string | null
          created_at?: string
          entity_id?: string | null
          entity_type?: string | null
          event_type?: string
          id?: string
          read_at?: string | null
          title?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "charging_notifications_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      charging_payment_methods: {
        Row: {
          agency_id: string | null
          agent_user_id: string | null
          created_at: string
          currency: string | null
          details: Json
          display_name: string
          id: string
          is_active: boolean
          method_code: string
        }
        Insert: {
          agency_id?: string | null
          agent_user_id?: string | null
          created_at?: string
          currency?: string | null
          details?: Json
          display_name: string
          id?: string
          is_active?: boolean
          method_code: string
        }
        Update: {
          agency_id?: string | null
          agent_user_id?: string | null
          created_at?: string
          currency?: string | null
          details?: Json
          display_name?: string
          id?: string
          is_active?: boolean
          method_code?: string
        }
        Relationships: [
          {
            foreignKeyName: "charging_payment_methods_agency_id_fkey"
            columns: ["agency_id"]
            isOneToOne: false
            referencedRelation: "charging_agencies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "charging_payment_methods_agent_user_id_fkey"
            columns: ["agent_user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      charging_pearl_transfer_reversals: {
        Row: {
          id: string
          original_transfer_id: string
          reason: string
          reversed_at: string
          reversed_by: string
        }
        Insert: {
          id?: string
          original_transfer_id: string
          reason: string
          reversed_at?: string
          reversed_by: string
        }
        Update: {
          id?: string
          original_transfer_id?: string
          reason?: string
          reversed_at?: string
          reversed_by?: string
        }
        Relationships: [
          {
            foreignKeyName: "charging_pearl_transfer_reversals_original_transfer_id_fkey"
            columns: ["original_transfer_id"]
            isOneToOne: true
            referencedRelation: "charging_pearl_transfers"
            referencedColumns: ["id"]
          },
        ]
      }
      charging_pearl_transfers: {
        Row: {
          amount: number
          completed_at: string | null
          created_at: string
          from_user_id: string
          id: string
          idempotency_key: string | null
          message_id: string | null
          note: string | null
          reference: string
          status: Database["public"]["Enums"]["charging_txn_status"]
          to_user_id: string
        }
        Insert: {
          amount: number
          completed_at?: string | null
          created_at?: string
          from_user_id: string
          id?: string
          idempotency_key?: string | null
          message_id?: string | null
          note?: string | null
          reference?: string
          status?: Database["public"]["Enums"]["charging_txn_status"]
          to_user_id: string
        }
        Update: {
          amount?: number
          completed_at?: string | null
          created_at?: string
          from_user_id?: string
          id?: string
          idempotency_key?: string | null
          message_id?: string | null
          note?: string | null
          reference?: string
          status?: Database["public"]["Enums"]["charging_txn_status"]
          to_user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "charging_pearl_transfers_from_user_id_fkey"
            columns: ["from_user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "charging_pearl_transfers_to_user_id_fkey"
            columns: ["to_user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      charging_price_rules: {
        Row: {
          agency_id: string | null
          agent_level_id: number | null
          commission_percentage: number | null
          country: string | null
          created_at: string
          created_by: string | null
          currency: string
          discount_percentage: number | null
          ends_at: string | null
          fee_percentage: number | null
          id: string
          operation: string
          starts_at: string | null
          status: string
          tier_from: number
          tier_to: number | null
          unit_price: number
          updated_at: string
          version: number
        }
        Insert: {
          agency_id?: string | null
          agent_level_id?: number | null
          commission_percentage?: number | null
          country?: string | null
          created_at?: string
          created_by?: string | null
          currency?: string
          discount_percentage?: number | null
          ends_at?: string | null
          fee_percentage?: number | null
          id?: string
          operation: string
          starts_at?: string | null
          status?: string
          tier_from?: number
          tier_to?: number | null
          unit_price: number
          updated_at?: string
          version?: number
        }
        Update: {
          agency_id?: string | null
          agent_level_id?: number | null
          commission_percentage?: number | null
          country?: string | null
          created_at?: string
          created_by?: string | null
          currency?: string
          discount_percentage?: number | null
          ends_at?: string | null
          fee_percentage?: number | null
          id?: string
          operation?: string
          starts_at?: string | null
          status?: string
          tier_from?: number
          tier_to?: number | null
          unit_price?: number
          updated_at?: string
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "charging_price_rules_agency_id_fkey"
            columns: ["agency_id"]
            isOneToOne: false
            referencedRelation: "charging_agencies"
            referencedColumns: ["id"]
          },
        ]
      }
      coin_price_rules: {
        Row: {
          agency_id: string | null
          base_unit_price: number
          bonus_pct: number
          buy_unit_price: number | null
          charging_agent_user_id: string | null
          code: string
          country_code: string | null
          created_at: string
          created_by: string | null
          currency_code: string
          discount_pct: number
          ends_at: string | null
          fixed_fee: number
          id: string
          max_coin_amount: number | null
          max_user_level: number | null
          max_vip: number | null
          min_coin_amount: number
          min_user_level: number | null
          min_vip: number | null
          name: string
          payment_gateway_id: string | null
          payment_method_id: string | null
          percentage_fee: number
          priority: number
          starts_at: string | null
          status: Database["public"]["Enums"]["coin_price_status"]
          tax_pct: number
          updated_at: string
          updated_by: string | null
          user_type: string | null
          version: number
        }
        Insert: {
          agency_id?: string | null
          base_unit_price: number
          bonus_pct?: number
          buy_unit_price?: number | null
          charging_agent_user_id?: string | null
          code: string
          country_code?: string | null
          created_at?: string
          created_by?: string | null
          currency_code: string
          discount_pct?: number
          ends_at?: string | null
          fixed_fee?: number
          id?: string
          max_coin_amount?: number | null
          max_user_level?: number | null
          max_vip?: number | null
          min_coin_amount?: number
          min_user_level?: number | null
          min_vip?: number | null
          name: string
          payment_gateway_id?: string | null
          payment_method_id?: string | null
          percentage_fee?: number
          priority?: number
          starts_at?: string | null
          status?: Database["public"]["Enums"]["coin_price_status"]
          tax_pct?: number
          updated_at?: string
          updated_by?: string | null
          user_type?: string | null
          version?: number
        }
        Update: {
          agency_id?: string | null
          base_unit_price?: number
          bonus_pct?: number
          buy_unit_price?: number | null
          charging_agent_user_id?: string | null
          code?: string
          country_code?: string | null
          created_at?: string
          created_by?: string | null
          currency_code?: string
          discount_pct?: number
          ends_at?: string | null
          fixed_fee?: number
          id?: string
          max_coin_amount?: number | null
          max_user_level?: number | null
          max_vip?: number | null
          min_coin_amount?: number
          min_user_level?: number | null
          min_vip?: number | null
          name?: string
          payment_gateway_id?: string | null
          payment_method_id?: string | null
          percentage_fee?: number
          priority?: number
          starts_at?: string | null
          status?: Database["public"]["Enums"]["coin_price_status"]
          tax_pct?: number
          updated_at?: string
          updated_by?: string | null
          user_type?: string | null
          version?: number
        }
        Relationships: []
      }
      coin_price_tiers: {
        Row: {
          bonus_pct: number
          created_at: string
          discount_pct: number
          id: string
          max_amount: number | null
          min_amount: number
          rule_id: string
          unit_price: number
          updated_at: string
        }
        Insert: {
          bonus_pct?: number
          created_at?: string
          discount_pct?: number
          id?: string
          max_amount?: number | null
          min_amount: number
          rule_id: string
          unit_price: number
          updated_at?: string
        }
        Update: {
          bonus_pct?: number
          created_at?: string
          discount_pct?: number
          id?: string
          max_amount?: number | null
          min_amount?: number
          rule_id?: string
          unit_price?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "coin_price_tiers_rule_id_fkey"
            columns: ["rule_id"]
            isOneToOne: false
            referencedRelation: "coin_price_rules"
            referencedColumns: ["id"]
          },
        ]
      }
      coin_price_versions: {
        Row: {
          change_note: string | null
          created_at: string
          created_by: string | null
          id: string
          rule_id: string
          snapshot: Json
          version: number
        }
        Insert: {
          change_note?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          rule_id: string
          snapshot: Json
          version: number
        }
        Update: {
          change_note?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          rule_id?: string
          snapshot?: Json
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "coin_price_versions_rule_id_fkey"
            columns: ["rule_id"]
            isOneToOne: false
            referencedRelation: "coin_price_rules"
            referencedColumns: ["id"]
          },
        ]
      }
      dispute_action_idempotency: {
        Row: {
          action_type: string
          actor_id: string
          created_at: string
          decision_version: number | null
          dispute_id: string | null
          id: string
          idempotency_key: string
          input_hash: string
          result_reference: Json | null
          source_cycle: string | null
        }
        Insert: {
          action_type: string
          actor_id: string
          created_at?: string
          decision_version?: number | null
          dispute_id?: string | null
          id?: string
          idempotency_key: string
          input_hash: string
          result_reference?: Json | null
          source_cycle?: string | null
        }
        Update: {
          action_type?: string
          actor_id?: string
          created_at?: string
          decision_version?: number | null
          dispute_id?: string | null
          id?: string
          idempotency_key?: string
          input_hash?: string
          result_reference?: Json | null
          source_cycle?: string | null
        }
        Relationships: []
      }
      financial_read_only_allowlist: {
        Row: {
          function_name: string
          reason: string
          reviewed_at: string
          reviewed_by: string
        }
        Insert: {
          function_name: string
          reason: string
          reviewed_at?: string
          reviewed_by?: string
        }
        Update: {
          function_name?: string
          reason?: string
          reviewed_at?: string
          reviewed_by?: string
        }
        Relationships: []
      }
      host_earnings: {
        Row: {
          agency_cut: number
          agency_id: string | null
          bd_cut: number
          created_at: string
          gross_coins: number
          host_id: string
          id: string
          net_coins: number
          period_month: number
          period_year: number
          platform_cut: number
          status: string
        }
        Insert: {
          agency_cut?: number
          agency_id?: string | null
          bd_cut?: number
          created_at?: string
          gross_coins?: number
          host_id: string
          id?: string
          net_coins?: number
          period_month: number
          period_year: number
          platform_cut?: number
          status?: string
        }
        Update: {
          agency_cut?: number
          agency_id?: string | null
          bd_cut?: number
          created_at?: string
          gross_coins?: number
          host_id?: string
          id?: string
          net_coins?: number
          period_month?: number
          period_year?: number
          platform_cut?: number
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "host_earnings_agency_id_fkey"
            columns: ["agency_id"]
            isOneToOne: false
            referencedRelation: "agencies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "host_earnings_host_id_fkey"
            columns: ["host_id"]
            isOneToOne: false
            referencedRelation: "hosts"
            referencedColumns: ["id"]
          },
        ]
      }
      host_levels: {
        Row: {
          bonus_pct: number
          created_at: string
          id: number
          min_coins: number
          min_hours: number
          name: string
          perks: Json
        }
        Insert: {
          bonus_pct?: number
          created_at?: string
          id: number
          min_coins?: number
          min_hours?: number
          name: string
          perks?: Json
        }
        Update: {
          bonus_pct?: number
          created_at?: string
          id?: number
          min_coins?: number
          min_hours?: number
          name?: string
          perks?: Json
        }
        Relationships: []
      }
      host_shifts: {
        Row: {
          coins_earned: number
          created_at: string
          duration_min: number | null
          ended_at: string | null
          host_id: string
          id: string
          room_id: string | null
          started_at: string
        }
        Insert: {
          coins_earned?: number
          created_at?: string
          duration_min?: number | null
          ended_at?: string | null
          host_id: string
          id?: string
          room_id?: string | null
          started_at: string
        }
        Update: {
          coins_earned?: number
          created_at?: string
          duration_min?: number | null
          ended_at?: string | null
          host_id?: string
          id?: string
          room_id?: string | null
          started_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "host_shifts_host_id_fkey"
            columns: ["host_id"]
            isOneToOne: false
            referencedRelation: "hosts"
            referencedColumns: ["id"]
          },
        ]
      }
      host_targets: {
        Row: {
          achieved_coins: number
          achieved_hours: number
          created_at: string
          host_id: string
          id: string
          period_month: number
          period_year: number
          status: string
          target_coins: number
          target_hours: number
        }
        Insert: {
          achieved_coins?: number
          achieved_hours?: number
          created_at?: string
          host_id: string
          id?: string
          period_month: number
          period_year: number
          status?: string
          target_coins?: number
          target_hours?: number
        }
        Update: {
          achieved_coins?: number
          achieved_hours?: number
          created_at?: string
          host_id?: string
          id?: string
          period_month?: number
          period_year?: number
          status?: string
          target_coins?: number
          target_hours?: number
        }
        Relationships: [
          {
            foreignKeyName: "host_targets_host_id_fkey"
            columns: ["host_id"]
            isOneToOne: false
            referencedRelation: "hosts"
            referencedColumns: ["id"]
          },
        ]
      }
      hosts: {
        Row: {
          agency_id: string | null
          cooldown_until: string | null
          created_at: string
          debt: number
          id: string
          joined_at: string
          left_at: string | null
          level_id: number | null
          monthly_coins: number
          monthly_hours: number
          pending_earnings: number
          status: string
          suspend_reason: string | null
          total_coins: number
          total_hours: number
          updated_at: string
          user_id: string
        }
        Insert: {
          agency_id?: string | null
          cooldown_until?: string | null
          created_at?: string
          debt?: number
          id?: string
          joined_at?: string
          left_at?: string | null
          level_id?: number | null
          monthly_coins?: number
          monthly_hours?: number
          pending_earnings?: number
          status?: string
          suspend_reason?: string | null
          total_coins?: number
          total_hours?: number
          updated_at?: string
          user_id: string
        }
        Update: {
          agency_id?: string | null
          cooldown_until?: string | null
          created_at?: string
          debt?: number
          id?: string
          joined_at?: string
          left_at?: string | null
          level_id?: number | null
          monthly_coins?: number
          monthly_hours?: number
          pending_earnings?: number
          status?: string
          suspend_reason?: string | null
          total_coins?: number
          total_hours?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "hosts_agency_id_fkey"
            columns: ["agency_id"]
            isOneToOne: false
            referencedRelation: "agencies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "hosts_level_id_fkey"
            columns: ["level_id"]
            isOneToOne: false
            referencedRelation: "host_levels"
            referencedColumns: ["id"]
          },
        ]
      }
      message_transaction_metadata: {
        Row: {
          amount: number | null
          created_at: string
          currency_code: string | null
          from_user_id: string | null
          id: string
          message_id: string | null
          metadata: Json
          status: string
          to_user_id: string | null
          txn_reference: string
          txn_type: string
        }
        Insert: {
          amount?: number | null
          created_at?: string
          currency_code?: string | null
          from_user_id?: string | null
          id?: string
          message_id?: string | null
          metadata?: Json
          status?: string
          to_user_id?: string | null
          txn_reference: string
          txn_type: string
        }
        Update: {
          amount?: number | null
          created_at?: string
          currency_code?: string | null
          from_user_id?: string | null
          id?: string
          message_id?: string | null
          metadata?: Json
          status?: string
          to_user_id?: string | null
          txn_reference?: string
          txn_type?: string
        }
        Relationships: []
      }
      payment_failures: {
        Row: {
          created_at: string
          details: Json
          error_code: string | null
          error_message: string | null
          failure_type: string
          gateway_id: string | null
          id: string
          request_id: string | null
          webhook_id: string | null
        }
        Insert: {
          created_at?: string
          details?: Json
          error_code?: string | null
          error_message?: string | null
          failure_type: string
          gateway_id?: string | null
          id?: string
          request_id?: string | null
          webhook_id?: string | null
        }
        Update: {
          created_at?: string
          details?: Json
          error_code?: string | null
          error_message?: string | null
          failure_type?: string
          gateway_id?: string | null
          id?: string
          request_id?: string | null
          webhook_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "payment_failures_gateway_id_fkey"
            columns: ["gateway_id"]
            isOneToOne: false
            referencedRelation: "payment_gateway_stats"
            referencedColumns: ["gateway_id"]
          },
          {
            foreignKeyName: "payment_failures_gateway_id_fkey"
            columns: ["gateway_id"]
            isOneToOne: false
            referencedRelation: "payment_gateways"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payment_failures_webhook_id_fkey"
            columns: ["webhook_id"]
            isOneToOne: false
            referencedRelation: "payment_webhooks"
            referencedColumns: ["id"]
          },
        ]
      }
      payment_gateway_country_configs: {
        Row: {
          active: boolean
          country_code: string
          created_at: string
          fixed_fee: number | null
          gateway_id: string
          id: string
          max_amount: number | null
          min_amount: number | null
          percentage_fee: number | null
          updated_at: string
        }
        Insert: {
          active?: boolean
          country_code: string
          created_at?: string
          fixed_fee?: number | null
          gateway_id: string
          id?: string
          max_amount?: number | null
          min_amount?: number | null
          percentage_fee?: number | null
          updated_at?: string
        }
        Update: {
          active?: boolean
          country_code?: string
          created_at?: string
          fixed_fee?: number | null
          gateway_id?: string
          id?: string
          max_amount?: number | null
          min_amount?: number | null
          percentage_fee?: number | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "payment_gateway_country_configs_gateway_id_fkey"
            columns: ["gateway_id"]
            isOneToOne: false
            referencedRelation: "payment_gateway_stats"
            referencedColumns: ["gateway_id"]
          },
          {
            foreignKeyName: "payment_gateway_country_configs_gateway_id_fkey"
            columns: ["gateway_id"]
            isOneToOne: false
            referencedRelation: "payment_gateways"
            referencedColumns: ["id"]
          },
        ]
      }
      payment_gateway_currencies: {
        Row: {
          active: boolean
          created_at: string
          currency_code: string
          exchange_rate: number | null
          gateway_id: string
          id: string
          updated_at: string
        }
        Insert: {
          active?: boolean
          created_at?: string
          currency_code: string
          exchange_rate?: number | null
          gateway_id: string
          id?: string
          updated_at?: string
        }
        Update: {
          active?: boolean
          created_at?: string
          currency_code?: string
          exchange_rate?: number | null
          gateway_id?: string
          id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "payment_gateway_currencies_gateway_id_fkey"
            columns: ["gateway_id"]
            isOneToOne: false
            referencedRelation: "payment_gateway_stats"
            referencedColumns: ["gateway_id"]
          },
          {
            foreignKeyName: "payment_gateway_currencies_gateway_id_fkey"
            columns: ["gateway_id"]
            isOneToOne: false
            referencedRelation: "payment_gateways"
            referencedColumns: ["id"]
          },
        ]
      }
      payment_gateways: {
        Row: {
          api_key_secret_ref: string | null
          callback_url: string | null
          code: string
          created_at: string
          created_by: string | null
          fixed_fee: number
          health_status: Database["public"]["Enums"]["payment_health_status"]
          id: string
          last_health_check_at: string | null
          logo_url: string | null
          max_amount: number | null
          metadata: Json
          min_amount: number
          mode: Database["public"]["Enums"]["payment_gateway_mode"]
          name: string
          percentage_fee: number
          priority: number
          provider: string
          provider_type: string
          status: Database["public"]["Enums"]["payment_gateway_status"]
          supported_countries: string[]
          supported_currencies: string[]
          updated_at: string
          updated_by: string | null
          webhook_secret_ref: string | null
          webhook_url: string | null
        }
        Insert: {
          api_key_secret_ref?: string | null
          callback_url?: string | null
          code: string
          created_at?: string
          created_by?: string | null
          fixed_fee?: number
          health_status?: Database["public"]["Enums"]["payment_health_status"]
          id?: string
          last_health_check_at?: string | null
          logo_url?: string | null
          max_amount?: number | null
          metadata?: Json
          min_amount?: number
          mode?: Database["public"]["Enums"]["payment_gateway_mode"]
          name: string
          percentage_fee?: number
          priority?: number
          provider: string
          provider_type?: string
          status?: Database["public"]["Enums"]["payment_gateway_status"]
          supported_countries?: string[]
          supported_currencies?: string[]
          updated_at?: string
          updated_by?: string | null
          webhook_secret_ref?: string | null
          webhook_url?: string | null
        }
        Update: {
          api_key_secret_ref?: string | null
          callback_url?: string | null
          code?: string
          created_at?: string
          created_by?: string | null
          fixed_fee?: number
          health_status?: Database["public"]["Enums"]["payment_health_status"]
          id?: string
          last_health_check_at?: string | null
          logo_url?: string | null
          max_amount?: number | null
          metadata?: Json
          min_amount?: number
          mode?: Database["public"]["Enums"]["payment_gateway_mode"]
          name?: string
          percentage_fee?: number
          priority?: number
          provider?: string
          provider_type?: string
          status?: Database["public"]["Enums"]["payment_gateway_status"]
          supported_countries?: string[]
          supported_currencies?: string[]
          updated_at?: string
          updated_by?: string | null
          webhook_secret_ref?: string | null
          webhook_url?: string | null
        }
        Relationships: []
      }
      payment_method_accounts: {
        Row: {
          account_number_masked: string | null
          account_number_secret_ref: string | null
          active: boolean
          bank_name: string | null
          beneficiary_name_masked: string | null
          beneficiary_name_secret_ref: string | null
          created_at: string
          created_by: string | null
          extra_data: Json
          iban_masked: string | null
          iban_secret_ref: string | null
          id: string
          label: string
          method_id: string
          swift_code: string | null
          updated_at: string
        }
        Insert: {
          account_number_masked?: string | null
          account_number_secret_ref?: string | null
          active?: boolean
          bank_name?: string | null
          beneficiary_name_masked?: string | null
          beneficiary_name_secret_ref?: string | null
          created_at?: string
          created_by?: string | null
          extra_data?: Json
          iban_masked?: string | null
          iban_secret_ref?: string | null
          id?: string
          label: string
          method_id: string
          swift_code?: string | null
          updated_at?: string
        }
        Update: {
          account_number_masked?: string | null
          account_number_secret_ref?: string | null
          active?: boolean
          bank_name?: string | null
          beneficiary_name_masked?: string | null
          beneficiary_name_secret_ref?: string | null
          created_at?: string
          created_by?: string | null
          extra_data?: Json
          iban_masked?: string | null
          iban_secret_ref?: string | null
          id?: string
          label?: string
          method_id?: string
          swift_code?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "payment_method_accounts_method_id_fkey"
            columns: ["method_id"]
            isOneToOne: false
            referencedRelation: "payment_methods"
            referencedColumns: ["id"]
          },
        ]
      }
      payment_method_country_rules: {
        Row: {
          active: boolean
          country_code: string
          created_at: string
          fixed_fee: number | null
          id: string
          max_amount: number | null
          method_id: string
          min_amount: number | null
          percentage_fee: number | null
          updated_at: string
        }
        Insert: {
          active?: boolean
          country_code: string
          created_at?: string
          fixed_fee?: number | null
          id?: string
          max_amount?: number | null
          method_id: string
          min_amount?: number | null
          percentage_fee?: number | null
          updated_at?: string
        }
        Update: {
          active?: boolean
          country_code?: string
          created_at?: string
          fixed_fee?: number | null
          id?: string
          max_amount?: number | null
          method_id?: string
          min_amount?: number | null
          percentage_fee?: number | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "payment_method_country_rules_method_id_fkey"
            columns: ["method_id"]
            isOneToOne: false
            referencedRelation: "payment_methods"
            referencedColumns: ["id"]
          },
        ]
      }
      payment_method_limits: {
        Row: {
          created_at: string
          daily_max: number | null
          id: string
          method_id: string
          monthly_max: number | null
          per_txn_max: number | null
          per_txn_min: number | null
          scope: string
          updated_at: string
          weekly_max: number | null
        }
        Insert: {
          created_at?: string
          daily_max?: number | null
          id?: string
          method_id: string
          monthly_max?: number | null
          per_txn_max?: number | null
          per_txn_min?: number | null
          scope: string
          updated_at?: string
          weekly_max?: number | null
        }
        Update: {
          created_at?: string
          daily_max?: number | null
          id?: string
          method_id?: string
          monthly_max?: number | null
          per_txn_max?: number | null
          per_txn_min?: number | null
          scope?: string
          updated_at?: string
          weekly_max?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "payment_method_limits_method_id_fkey"
            columns: ["method_id"]
            isOneToOne: false
            referencedRelation: "payment_methods"
            referencedColumns: ["id"]
          },
        ]
      }
      payment_methods: {
        Row: {
          code: string
          country_code: string | null
          created_at: string
          created_by: string | null
          currency_code: string
          fixed_fee: number
          for_agents: boolean
          for_recharge: boolean
          for_users: boolean
          for_withdrawal: boolean
          gateway_id: string | null
          id: string
          instructions_ar: string | null
          instructions_en: string | null
          logo_url: string | null
          max_amount: number | null
          method_type: Database["public"]["Enums"]["payment_method_type"]
          min_amount: number
          name_ar: string
          name_en: string
          percentage_fee: number
          qr_url: string | null
          sort_order: number
          status: Database["public"]["Enums"]["payment_method_status"]
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          code: string
          country_code?: string | null
          created_at?: string
          created_by?: string | null
          currency_code: string
          fixed_fee?: number
          for_agents?: boolean
          for_recharge?: boolean
          for_users?: boolean
          for_withdrawal?: boolean
          gateway_id?: string | null
          id?: string
          instructions_ar?: string | null
          instructions_en?: string | null
          logo_url?: string | null
          max_amount?: number | null
          method_type: Database["public"]["Enums"]["payment_method_type"]
          min_amount?: number
          name_ar: string
          name_en: string
          percentage_fee?: number
          qr_url?: string | null
          sort_order?: number
          status?: Database["public"]["Enums"]["payment_method_status"]
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          code?: string
          country_code?: string | null
          created_at?: string
          created_by?: string | null
          currency_code?: string
          fixed_fee?: number
          for_agents?: boolean
          for_recharge?: boolean
          for_users?: boolean
          for_withdrawal?: boolean
          gateway_id?: string | null
          id?: string
          instructions_ar?: string | null
          instructions_en?: string | null
          logo_url?: string | null
          max_amount?: number | null
          method_type?: Database["public"]["Enums"]["payment_method_type"]
          min_amount?: number
          name_ar?: string
          name_en?: string
          percentage_fee?: number
          qr_url?: string | null
          sort_order?: number
          status?: Database["public"]["Enums"]["payment_method_status"]
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "payment_methods_gateway_id_fkey"
            columns: ["gateway_id"]
            isOneToOne: false
            referencedRelation: "payment_gateway_stats"
            referencedColumns: ["gateway_id"]
          },
          {
            foreignKeyName: "payment_methods_gateway_id_fkey"
            columns: ["gateway_id"]
            isOneToOne: false
            referencedRelation: "payment_gateways"
            referencedColumns: ["id"]
          },
        ]
      }
      payment_webhook_attempts: {
        Row: {
          attempt_number: number
          created_at: string
          failure_code: string | null
          finished_at: string | null
          id: string
          idempotency_key: string | null
          reason: string | null
          result: string | null
          safe_error: string | null
          started_at: string
          trigger_type: string
          triggered_by: string | null
          webhook_id: string
        }
        Insert: {
          attempt_number: number
          created_at?: string
          failure_code?: string | null
          finished_at?: string | null
          id?: string
          idempotency_key?: string | null
          reason?: string | null
          result?: string | null
          safe_error?: string | null
          started_at?: string
          trigger_type: string
          triggered_by?: string | null
          webhook_id: string
        }
        Update: {
          attempt_number?: number
          created_at?: string
          failure_code?: string | null
          finished_at?: string | null
          id?: string
          idempotency_key?: string | null
          reason?: string | null
          result?: string | null
          safe_error?: string | null
          started_at?: string
          trigger_type?: string
          triggered_by?: string | null
          webhook_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "payment_webhook_attempts_webhook_id_fkey"
            columns: ["webhook_id"]
            isOneToOne: false
            referencedRelation: "payment_webhooks"
            referencedColumns: ["id"]
          },
        ]
      }
      payment_webhook_events: {
        Row: {
          created_at: string
          data: Json
          entity_id: string | null
          entity_type: string | null
          event_type: string
          id: string
          webhook_id: string
        }
        Insert: {
          created_at?: string
          data?: Json
          entity_id?: string | null
          entity_type?: string | null
          event_type: string
          id?: string
          webhook_id: string
        }
        Update: {
          created_at?: string
          data?: Json
          entity_id?: string | null
          entity_type?: string | null
          event_type?: string
          id?: string
          webhook_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "payment_webhook_events_webhook_id_fkey"
            columns: ["webhook_id"]
            isOneToOne: false
            referencedRelation: "payment_webhooks"
            referencedColumns: ["id"]
          },
        ]
      }
      payment_webhooks: {
        Row: {
          created_at: string
          event_amount: number | null
          event_currency: string | null
          event_domain: string
          event_type: string
          external_id: string | null
          failure_code: string | null
          gateway_id: string
          gateway_mode: string
          id: string
          idempotency_key: string | null
          marked_as_duplicate: boolean
          normalized_event_type: string | null
          occurred_at: string | null
          original_provider_payment_id: string | null
          payload_hash: string | null
          payload_redacted: Json | null
          processed: boolean
          processed_at: string | null
          processing_error: string | null
          processing_owner: string | null
          processing_started_at: string | null
          processing_state: string
          provider_event_id: string | null
          provider_refund_id: string | null
          raw_payload: Json
          received_at: string
          refund_id: string | null
          refund_reference: string | null
          related_request_id: string | null
          replay_check_passed: boolean | null
          retry_count: number
          safe_error: string | null
          signature: string | null
          signature_valid: boolean | null
          signature_verified: boolean | null
          timestamp_verified: boolean | null
          validation_status: string | null
        }
        Insert: {
          created_at?: string
          event_amount?: number | null
          event_currency?: string | null
          event_domain?: string
          event_type: string
          external_id?: string | null
          failure_code?: string | null
          gateway_id: string
          gateway_mode?: string
          id?: string
          idempotency_key?: string | null
          marked_as_duplicate?: boolean
          normalized_event_type?: string | null
          occurred_at?: string | null
          original_provider_payment_id?: string | null
          payload_hash?: string | null
          payload_redacted?: Json | null
          processed?: boolean
          processed_at?: string | null
          processing_error?: string | null
          processing_owner?: string | null
          processing_started_at?: string | null
          processing_state?: string
          provider_event_id?: string | null
          provider_refund_id?: string | null
          raw_payload: Json
          received_at?: string
          refund_id?: string | null
          refund_reference?: string | null
          related_request_id?: string | null
          replay_check_passed?: boolean | null
          retry_count?: number
          safe_error?: string | null
          signature?: string | null
          signature_valid?: boolean | null
          signature_verified?: boolean | null
          timestamp_verified?: boolean | null
          validation_status?: string | null
        }
        Update: {
          created_at?: string
          event_amount?: number | null
          event_currency?: string | null
          event_domain?: string
          event_type?: string
          external_id?: string | null
          failure_code?: string | null
          gateway_id?: string
          gateway_mode?: string
          id?: string
          idempotency_key?: string | null
          marked_as_duplicate?: boolean
          normalized_event_type?: string | null
          occurred_at?: string | null
          original_provider_payment_id?: string | null
          payload_hash?: string | null
          payload_redacted?: Json | null
          processed?: boolean
          processed_at?: string | null
          processing_error?: string | null
          processing_owner?: string | null
          processing_started_at?: string | null
          processing_state?: string
          provider_event_id?: string | null
          provider_refund_id?: string | null
          raw_payload?: Json
          received_at?: string
          refund_id?: string | null
          refund_reference?: string | null
          related_request_id?: string | null
          replay_check_passed?: boolean | null
          retry_count?: number
          safe_error?: string | null
          signature?: string | null
          signature_valid?: boolean | null
          signature_verified?: boolean | null
          timestamp_verified?: boolean | null
          validation_status?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "payment_webhooks_gateway_id_fkey"
            columns: ["gateway_id"]
            isOneToOne: false
            referencedRelation: "payment_gateway_stats"
            referencedColumns: ["gateway_id"]
          },
          {
            foreignKeyName: "payment_webhooks_gateway_id_fkey"
            columns: ["gateway_id"]
            isOneToOne: false
            referencedRelation: "payment_gateways"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payment_webhooks_refund_id_fkey"
            columns: ["refund_id"]
            isOneToOne: false
            referencedRelation: "recharge_refunds"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payment_webhooks_related_request_id_fkey"
            columns: ["related_request_id"]
            isOneToOne: false
            referencedRelation: "recharge_requests"
            referencedColumns: ["id"]
          },
        ]
      }
      pearl_coin_exchange_rates: {
        Row: {
          agency_id: string | null
          agent_level_id: number | null
          coins_per_pearl: number
          country: string | null
          created_at: string
          created_by: string | null
          daily_limit: number | null
          ends_at: string | null
          fee_percentage: number | null
          id: string
          max_exchange: number | null
          min_exchange: number | null
          monthly_limit: number | null
          pearl_amount_from: number
          pearl_amount_to: number | null
          starts_at: string | null
          status: string
          version: number
        }
        Insert: {
          agency_id?: string | null
          agent_level_id?: number | null
          coins_per_pearl: number
          country?: string | null
          created_at?: string
          created_by?: string | null
          daily_limit?: number | null
          ends_at?: string | null
          fee_percentage?: number | null
          id?: string
          max_exchange?: number | null
          min_exchange?: number | null
          monthly_limit?: number | null
          pearl_amount_from?: number
          pearl_amount_to?: number | null
          starts_at?: string | null
          status?: string
          version?: number
        }
        Update: {
          agency_id?: string | null
          agent_level_id?: number | null
          coins_per_pearl?: number
          country?: string | null
          created_at?: string
          created_by?: string | null
          daily_limit?: number | null
          ends_at?: string | null
          fee_percentage?: number | null
          id?: string
          max_exchange?: number | null
          min_exchange?: number | null
          monthly_limit?: number | null
          pearl_amount_from?: number
          pearl_amount_to?: number | null
          starts_at?: string | null
          status?: string
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "pearl_coin_exchange_rates_agency_id_fkey"
            columns: ["agency_id"]
            isOneToOne: false
            referencedRelation: "charging_agencies"
            referencedColumns: ["id"]
          },
        ]
      }
      pearl_coin_exchange_reversals: {
        Row: {
          id: string
          original_exchange_id: string
          reason: string
          reversed_at: string
          reversed_by: string
        }
        Insert: {
          id?: string
          original_exchange_id: string
          reason: string
          reversed_at?: string
          reversed_by: string
        }
        Update: {
          id?: string
          original_exchange_id?: string
          reason?: string
          reversed_at?: string
          reversed_by?: string
        }
        Relationships: [
          {
            foreignKeyName: "pearl_coin_exchange_reversals_original_exchange_id_fkey"
            columns: ["original_exchange_id"]
            isOneToOne: true
            referencedRelation: "pearl_coin_exchanges"
            referencedColumns: ["id"]
          },
        ]
      }
      pearl_coin_exchanges: {
        Row: {
          agency_id: string | null
          agent_user_id: string
          applied_rate: number
          coins_amount: number
          completed_at: string | null
          created_at: string
          fee_amount: number | null
          id: string
          idempotency_key: string | null
          pearl_amount: number
          rate_id: string | null
          reference: string
          status: Database["public"]["Enums"]["charging_txn_status"]
        }
        Insert: {
          agency_id?: string | null
          agent_user_id: string
          applied_rate: number
          coins_amount: number
          completed_at?: string | null
          created_at?: string
          fee_amount?: number | null
          id?: string
          idempotency_key?: string | null
          pearl_amount: number
          rate_id?: string | null
          reference?: string
          status?: Database["public"]["Enums"]["charging_txn_status"]
        }
        Update: {
          agency_id?: string | null
          agent_user_id?: string
          applied_rate?: number
          coins_amount?: number
          completed_at?: string | null
          created_at?: string
          fee_amount?: number | null
          id?: string
          idempotency_key?: string | null
          pearl_amount?: number
          rate_id?: string | null
          reference?: string
          status?: Database["public"]["Enums"]["charging_txn_status"]
        }
        Relationships: [
          {
            foreignKeyName: "pearl_coin_exchanges_agency_id_fkey"
            columns: ["agency_id"]
            isOneToOne: false
            referencedRelation: "charging_agencies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pearl_coin_exchanges_agent_user_id_fkey"
            columns: ["agent_user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pearl_coin_exchanges_rate_id_fkey"
            columns: ["rate_id"]
            isOneToOne: false
            referencedRelation: "pearl_coin_exchange_rates"
            referencedColumns: ["id"]
          },
        ]
      }
      pearl_exchange_rates: {
        Row: {
          code: string
          country_code: string | null
          created_at: string
          created_by: string | null
          currency_code: string
          ends_at: string | null
          fee_pct: number
          id: string
          max_pearls: number | null
          min_pearls: number
          name: string
          pearls_per_coin: number
          priority: number
          starts_at: string | null
          status: Database["public"]["Enums"]["pearl_price_status"]
          updated_at: string
          updated_by: string | null
          version: number
        }
        Insert: {
          code: string
          country_code?: string | null
          created_at?: string
          created_by?: string | null
          currency_code: string
          ends_at?: string | null
          fee_pct?: number
          id?: string
          max_pearls?: number | null
          min_pearls?: number
          name: string
          pearls_per_coin: number
          priority?: number
          starts_at?: string | null
          status?: Database["public"]["Enums"]["pearl_price_status"]
          updated_at?: string
          updated_by?: string | null
          version?: number
        }
        Update: {
          code?: string
          country_code?: string | null
          created_at?: string
          created_by?: string | null
          currency_code?: string
          ends_at?: string | null
          fee_pct?: number
          id?: string
          max_pearls?: number | null
          min_pearls?: number
          name?: string
          pearls_per_coin?: number
          priority?: number
          starts_at?: string | null
          status?: Database["public"]["Enums"]["pearl_price_status"]
          updated_at?: string
          updated_by?: string | null
          version?: number
        }
        Relationships: []
      }
      pearl_price_rules: {
        Row: {
          agency_commission_pct: number
          agency_id: string | null
          agent_commission_pct: number
          base_unit_price: number
          code: string
          country_code: string | null
          created_at: string
          created_by: string | null
          currency_code: string
          ends_at: string | null
          id: string
          kind: Database["public"]["Enums"]["pearl_price_kind"]
          max_agent_level: number | null
          max_amount: number | null
          max_user_level: number | null
          max_vip: number | null
          min_agent_level: number | null
          min_amount: number
          min_user_level: number | null
          min_vip: number | null
          name: string
          platform_commission_pct: number
          priority: number
          starts_at: string | null
          status: Database["public"]["Enums"]["pearl_price_status"]
          updated_at: string
          updated_by: string | null
          version: number
          withdrawal_fee_fixed: number
          withdrawal_fee_pct: number
        }
        Insert: {
          agency_commission_pct?: number
          agency_id?: string | null
          agent_commission_pct?: number
          base_unit_price: number
          code: string
          country_code?: string | null
          created_at?: string
          created_by?: string | null
          currency_code: string
          ends_at?: string | null
          id?: string
          kind: Database["public"]["Enums"]["pearl_price_kind"]
          max_agent_level?: number | null
          max_amount?: number | null
          max_user_level?: number | null
          max_vip?: number | null
          min_agent_level?: number | null
          min_amount?: number
          min_user_level?: number | null
          min_vip?: number | null
          name: string
          platform_commission_pct?: number
          priority?: number
          starts_at?: string | null
          status?: Database["public"]["Enums"]["pearl_price_status"]
          updated_at?: string
          updated_by?: string | null
          version?: number
          withdrawal_fee_fixed?: number
          withdrawal_fee_pct?: number
        }
        Update: {
          agency_commission_pct?: number
          agency_id?: string | null
          agent_commission_pct?: number
          base_unit_price?: number
          code?: string
          country_code?: string | null
          created_at?: string
          created_by?: string | null
          currency_code?: string
          ends_at?: string | null
          id?: string
          kind?: Database["public"]["Enums"]["pearl_price_kind"]
          max_agent_level?: number | null
          max_amount?: number | null
          max_user_level?: number | null
          max_vip?: number | null
          min_agent_level?: number | null
          min_amount?: number
          min_user_level?: number | null
          min_vip?: number | null
          name?: string
          platform_commission_pct?: number
          priority?: number
          starts_at?: string | null
          status?: Database["public"]["Enums"]["pearl_price_status"]
          updated_at?: string
          updated_by?: string | null
          version?: number
          withdrawal_fee_fixed?: number
          withdrawal_fee_pct?: number
        }
        Relationships: []
      }
      pearl_price_tiers: {
        Row: {
          bonus_pct: number
          created_at: string
          discount_pct: number
          id: string
          max_amount: number | null
          min_amount: number
          rule_id: string
          unit_price: number
          updated_at: string
        }
        Insert: {
          bonus_pct?: number
          created_at?: string
          discount_pct?: number
          id?: string
          max_amount?: number | null
          min_amount: number
          rule_id: string
          unit_price: number
          updated_at?: string
        }
        Update: {
          bonus_pct?: number
          created_at?: string
          discount_pct?: number
          id?: string
          max_amount?: number | null
          min_amount?: number
          rule_id?: string
          unit_price?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "pearl_price_tiers_rule_id_fkey"
            columns: ["rule_id"]
            isOneToOne: false
            referencedRelation: "pearl_price_rules"
            referencedColumns: ["id"]
          },
        ]
      }
      pearl_price_versions: {
        Row: {
          change_note: string | null
          created_at: string
          created_by: string | null
          id: string
          rule_id: string
          snapshot: Json
          version: number
        }
        Insert: {
          change_note?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          rule_id: string
          snapshot: Json
          version: number
        }
        Update: {
          change_note?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          rule_id?: string
          snapshot?: Json
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "pearl_price_versions_rule_id_fkey"
            columns: ["rule_id"]
            isOneToOne: false
            referencedRelation: "pearl_price_rules"
            referencedColumns: ["id"]
          },
        ]
      }
      pearl_purchase_payments: {
        Row: {
          amount: number | null
          currency: string | null
          id: string
          method_code: string | null
          proof_url: string | null
          reference: string | null
          request_id: string
          submitted_at: string
          submitted_by: string | null
        }
        Insert: {
          amount?: number | null
          currency?: string | null
          id?: string
          method_code?: string | null
          proof_url?: string | null
          reference?: string | null
          request_id: string
          submitted_at?: string
          submitted_by?: string | null
        }
        Update: {
          amount?: number | null
          currency?: string | null
          id?: string
          method_code?: string | null
          proof_url?: string | null
          reference?: string | null
          request_id?: string
          submitted_at?: string
          submitted_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "pearl_purchase_payments_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "pearl_purchase_requests"
            referencedColumns: ["id"]
          },
        ]
      }
      pearl_purchase_requests: {
        Row: {
          admin_note: string | null
          admin_reviewed_at: string | null
          admin_reviewed_by: string | null
          agency_id: string | null
          agent_user_id: string
          completed_at: string | null
          created_at: string
          currency: string
          id: string
          idempotency_key: string | null
          message_id: string | null
          payment_proof_url: string | null
          payment_submitted_at: string | null
          pearl_amount: number
          price_amount: number
          reference: string
          status: Database["public"]["Enums"]["pearl_purchase_status"]
          user_confirmed_at: string | null
          user_id: string
          user_receipt_confirmed_at: string | null
        }
        Insert: {
          admin_note?: string | null
          admin_reviewed_at?: string | null
          admin_reviewed_by?: string | null
          agency_id?: string | null
          agent_user_id: string
          completed_at?: string | null
          created_at?: string
          currency?: string
          id?: string
          idempotency_key?: string | null
          message_id?: string | null
          payment_proof_url?: string | null
          payment_submitted_at?: string | null
          pearl_amount: number
          price_amount: number
          reference?: string
          status?: Database["public"]["Enums"]["pearl_purchase_status"]
          user_confirmed_at?: string | null
          user_id: string
          user_receipt_confirmed_at?: string | null
        }
        Update: {
          admin_note?: string | null
          admin_reviewed_at?: string | null
          admin_reviewed_by?: string | null
          agency_id?: string | null
          agent_user_id?: string
          completed_at?: string | null
          created_at?: string
          currency?: string
          id?: string
          idempotency_key?: string | null
          message_id?: string | null
          payment_proof_url?: string | null
          payment_submitted_at?: string | null
          pearl_amount?: number
          price_amount?: number
          reference?: string
          status?: Database["public"]["Enums"]["pearl_purchase_status"]
          user_confirmed_at?: string | null
          user_id?: string
          user_receipt_confirmed_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "pearl_purchase_requests_agency_id_fkey"
            columns: ["agency_id"]
            isOneToOne: false
            referencedRelation: "charging_agencies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pearl_purchase_requests_agent_user_id_fkey"
            columns: ["agent_user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pearl_purchase_requests_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      pearl_purchase_reversals: {
        Row: {
          id: string
          original_request_id: string
          reason: string
          reversed_at: string
          reversed_by: string
        }
        Insert: {
          id?: string
          original_request_id: string
          reason: string
          reversed_at?: string
          reversed_by: string
        }
        Update: {
          id?: string
          original_request_id?: string
          reason?: string
          reversed_at?: string
          reversed_by?: string
        }
        Relationships: [
          {
            foreignKeyName: "pearl_purchase_reversals_original_request_id_fkey"
            columns: ["original_request_id"]
            isOneToOne: true
            referencedRelation: "pearl_purchase_requests"
            referencedColumns: ["id"]
          },
        ]
      }
      permissions: {
        Row: {
          created_at: string
          description: string | null
          key: string
          label_ar: string
          label_en: string
          module: string
        }
        Insert: {
          created_at?: string
          description?: string | null
          key: string
          label_ar: string
          label_en: string
          module: string
        }
        Update: {
          created_at?: string
          description?: string | null
          key?: string
          label_ar?: string
          label_en?: string
          module?: string
        }
        Relationships: []
      }
      profiles: {
        Row: {
          agency_id: string | null
          avatar_url: string | null
          bd_id: string | null
          bio: string | null
          birth_date: string | null
          call_ban: boolean
          country: string | null
          cover_url: string | null
          created_at: string
          deleted_at: string | null
          deleted_by: string | null
          display_name: string | null
          external_uid: string | null
          gender: Database["public"]["Enums"]["gender"]
          id: string
          is_demo: boolean
          language: string | null
          last_seen_at: string | null
          level: number
          message_ban: boolean
          phone: string | null
          post_ban: boolean
          room_ban: boolean
          status: Database["public"]["Enums"]["user_status"]
          updated_at: string
          username: string | null
          verification: Database["public"]["Enums"]["verification_status"]
          vip_level: number
        }
        Insert: {
          agency_id?: string | null
          avatar_url?: string | null
          bd_id?: string | null
          bio?: string | null
          birth_date?: string | null
          call_ban?: boolean
          country?: string | null
          cover_url?: string | null
          created_at?: string
          deleted_at?: string | null
          deleted_by?: string | null
          display_name?: string | null
          external_uid?: string | null
          gender?: Database["public"]["Enums"]["gender"]
          id?: string
          is_demo?: boolean
          language?: string | null
          last_seen_at?: string | null
          level?: number
          message_ban?: boolean
          phone?: string | null
          post_ban?: boolean
          room_ban?: boolean
          status?: Database["public"]["Enums"]["user_status"]
          updated_at?: string
          username?: string | null
          verification?: Database["public"]["Enums"]["verification_status"]
          vip_level?: number
        }
        Update: {
          agency_id?: string | null
          avatar_url?: string | null
          bd_id?: string | null
          bio?: string | null
          birth_date?: string | null
          call_ban?: boolean
          country?: string | null
          cover_url?: string | null
          created_at?: string
          deleted_at?: string | null
          deleted_by?: string | null
          display_name?: string | null
          external_uid?: string | null
          gender?: Database["public"]["Enums"]["gender"]
          id?: string
          is_demo?: boolean
          language?: string | null
          last_seen_at?: string | null
          level?: number
          message_ban?: boolean
          phone?: string | null
          post_ban?: boolean
          room_ban?: boolean
          status?: Database["public"]["Enums"]["user_status"]
          updated_at?: string
          username?: string | null
          verification?: Database["public"]["Enums"]["verification_status"]
          vip_level?: number
        }
        Relationships: []
      }
      recharge_dispute_evidence: {
        Row: {
          created_at: string
          description: string | null
          dispute_id: string
          evidence_type: Database["public"]["Enums"]["recharge_dispute_evidence_type_enum"]
          id: string
          idempotency_key: string | null
          is_quarantined: boolean
          malware_scan_status: string
          metadata_safe: Json
          mime_type: string
          object_verified_at: string | null
          original_filename_masked: string | null
          rejection_reason: string | null
          review_reason: string | null
          review_status: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          sha256_hash: string | null
          size_bytes: number
          source: string | null
          status: Database["public"]["Enums"]["recharge_dispute_evidence_status_enum"]
          storage_bucket: string
          storage_object_path: string
          submitted_at: string
          submitted_by: string | null
          submitted_by_type: string
          supersedes_evidence_id: string | null
          visibility: Database["public"]["Enums"]["recharge_dispute_note_visibility_enum"]
        }
        Insert: {
          created_at?: string
          description?: string | null
          dispute_id: string
          evidence_type?: Database["public"]["Enums"]["recharge_dispute_evidence_type_enum"]
          id?: string
          idempotency_key?: string | null
          is_quarantined?: boolean
          malware_scan_status?: string
          metadata_safe?: Json
          mime_type: string
          object_verified_at?: string | null
          original_filename_masked?: string | null
          rejection_reason?: string | null
          review_reason?: string | null
          review_status?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          sha256_hash?: string | null
          size_bytes: number
          source?: string | null
          status?: Database["public"]["Enums"]["recharge_dispute_evidence_status_enum"]
          storage_bucket?: string
          storage_object_path: string
          submitted_at?: string
          submitted_by?: string | null
          submitted_by_type?: string
          supersedes_evidence_id?: string | null
          visibility?: Database["public"]["Enums"]["recharge_dispute_note_visibility_enum"]
        }
        Update: {
          created_at?: string
          description?: string | null
          dispute_id?: string
          evidence_type?: Database["public"]["Enums"]["recharge_dispute_evidence_type_enum"]
          id?: string
          idempotency_key?: string | null
          is_quarantined?: boolean
          malware_scan_status?: string
          metadata_safe?: Json
          mime_type?: string
          object_verified_at?: string | null
          original_filename_masked?: string | null
          rejection_reason?: string | null
          review_reason?: string | null
          review_status?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          sha256_hash?: string | null
          size_bytes?: number
          source?: string | null
          status?: Database["public"]["Enums"]["recharge_dispute_evidence_status_enum"]
          storage_bucket?: string
          storage_object_path?: string
          submitted_at?: string
          submitted_by?: string | null
          submitted_by_type?: string
          supersedes_evidence_id?: string | null
          visibility?: Database["public"]["Enums"]["recharge_dispute_note_visibility_enum"]
        }
        Relationships: [
          {
            foreignKeyName: "recharge_dispute_evidence_dispute_id_fkey"
            columns: ["dispute_id"]
            isOneToOne: false
            referencedRelation: "recharge_disputes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "recharge_dispute_evidence_supersedes_evidence_id_fkey"
            columns: ["supersedes_evidence_id"]
            isOneToOne: false
            referencedRelation: "recharge_dispute_evidence"
            referencedColumns: ["id"]
          },
        ]
      }
      recharge_dispute_notes: {
        Row: {
          author_id: string | null
          body: string | null
          content_hash: string | null
          created_at: string
          dispute_id: string
          id: string
          idempotency_key: string | null
          is_internal: boolean
          is_redacted: boolean
          note: string
          note_type: Database["public"]["Enums"]["recharge_dispute_note_type_enum"]
          redacted_at: string | null
          redacted_by: string | null
          redaction_hash: string | null
          redaction_reason: string | null
          safe_metadata: Json
          supersedes_note_id: string | null
          user_delivery_status: string | null
          visibility: Database["public"]["Enums"]["recharge_dispute_note_visibility_enum"]
        }
        Insert: {
          author_id?: string | null
          body?: string | null
          content_hash?: string | null
          created_at?: string
          dispute_id: string
          id?: string
          idempotency_key?: string | null
          is_internal?: boolean
          is_redacted?: boolean
          note: string
          note_type?: Database["public"]["Enums"]["recharge_dispute_note_type_enum"]
          redacted_at?: string | null
          redacted_by?: string | null
          redaction_hash?: string | null
          redaction_reason?: string | null
          safe_metadata?: Json
          supersedes_note_id?: string | null
          user_delivery_status?: string | null
          visibility?: Database["public"]["Enums"]["recharge_dispute_note_visibility_enum"]
        }
        Update: {
          author_id?: string | null
          body?: string | null
          content_hash?: string | null
          created_at?: string
          dispute_id?: string
          id?: string
          idempotency_key?: string | null
          is_internal?: boolean
          is_redacted?: boolean
          note?: string
          note_type?: Database["public"]["Enums"]["recharge_dispute_note_type_enum"]
          redacted_at?: string | null
          redacted_by?: string | null
          redaction_hash?: string | null
          redaction_reason?: string | null
          safe_metadata?: Json
          supersedes_note_id?: string | null
          user_delivery_status?: string | null
          visibility?: Database["public"]["Enums"]["recharge_dispute_note_visibility_enum"]
        }
        Relationships: [
          {
            foreignKeyName: "recharge_dispute_notes_dispute_id_fkey"
            columns: ["dispute_id"]
            isOneToOne: false
            referencedRelation: "recharge_disputes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "recharge_dispute_notes_supersedes_note_id_fkey"
            columns: ["supersedes_note_id"]
            isOneToOne: false
            referencedRelation: "recharge_dispute_notes"
            referencedColumns: ["id"]
          },
        ]
      }
      recharge_dispute_policies: {
        Row: {
          active: boolean
          allow_user_submission: boolean
          auto_close_after_no_response_days: number
          chargeback_response_days: number
          country: string | null
          created_at: string
          created_by: string | null
          currency: string | null
          dispute_type:
            | Database["public"]["Enums"]["recharge_dispute_type_enum"]
            | null
          ends_at: string | null
          evidence_submission_days: number
          first_response_hours: number
          gateway_id: string | null
          gateway_mode: string | null
          id: string
          name: string
          priority: number
          provisional_action_policy: Json
          require_gateway_evidence: boolean
          require_receipt: boolean
          require_second_decision: boolean
          resolution_target_hours: number
          second_decision_threshold: number
          source:
            | Database["public"]["Enums"]["recharge_dispute_source_enum"]
            | null
          starts_at: string | null
          updated_at: string
          user_dispute_window_days: number
          version: number
          wallet_restriction_policy: Json
        }
        Insert: {
          active?: boolean
          allow_user_submission?: boolean
          auto_close_after_no_response_days?: number
          chargeback_response_days?: number
          country?: string | null
          created_at?: string
          created_by?: string | null
          currency?: string | null
          dispute_type?:
            | Database["public"]["Enums"]["recharge_dispute_type_enum"]
            | null
          ends_at?: string | null
          evidence_submission_days?: number
          first_response_hours?: number
          gateway_id?: string | null
          gateway_mode?: string | null
          id?: string
          name: string
          priority?: number
          provisional_action_policy?: Json
          require_gateway_evidence?: boolean
          require_receipt?: boolean
          require_second_decision?: boolean
          resolution_target_hours?: number
          second_decision_threshold?: number
          source?:
            | Database["public"]["Enums"]["recharge_dispute_source_enum"]
            | null
          starts_at?: string | null
          updated_at?: string
          user_dispute_window_days?: number
          version?: number
          wallet_restriction_policy?: Json
        }
        Update: {
          active?: boolean
          allow_user_submission?: boolean
          auto_close_after_no_response_days?: number
          chargeback_response_days?: number
          country?: string | null
          created_at?: string
          created_by?: string | null
          currency?: string | null
          dispute_type?:
            | Database["public"]["Enums"]["recharge_dispute_type_enum"]
            | null
          ends_at?: string | null
          evidence_submission_days?: number
          first_response_hours?: number
          gateway_id?: string | null
          gateway_mode?: string | null
          id?: string
          name?: string
          priority?: number
          provisional_action_policy?: Json
          require_gateway_evidence?: boolean
          require_receipt?: boolean
          require_second_decision?: boolean
          resolution_target_hours?: number
          second_decision_threshold?: number
          source?:
            | Database["public"]["Enums"]["recharge_dispute_source_enum"]
            | null
          starts_at?: string | null
          updated_at?: string
          user_dispute_window_days?: number
          version?: number
          wallet_restriction_policy?: Json
        }
        Relationships: [
          {
            foreignKeyName: "recharge_dispute_policies_gateway_id_fkey"
            columns: ["gateway_id"]
            isOneToOne: false
            referencedRelation: "payment_gateway_stats"
            referencedColumns: ["gateway_id"]
          },
          {
            foreignKeyName: "recharge_dispute_policies_gateway_id_fkey"
            columns: ["gateway_id"]
            isOneToOne: false
            referencedRelation: "payment_gateways"
            referencedColumns: ["id"]
          },
        ]
      }
      recharge_disputes: {
        Row: {
          already_refunded_amount: number | null
          amount: number | null
          approved_resolution_amount: number | null
          assigned_team: string | null
          assigned_to: string | null
          bonus_already_reversed: number | null
          cancelled_at: string | null
          cancelled_by: string | null
          chargeback_amount: number | null
          chargeback_currency: string | null
          claimed_amount: number | null
          closed_at: string | null
          closed_by: string | null
          coins_already_reversed: number | null
          created_at: string
          currency: string | null
          currency_code: string | null
          current_available_bonus: number | null
          current_available_coins: number | null
          current_exposure_checked_at: string | null
          current_exposure_snapshot: Json | null
          decision_type: string | null
          description: string | null
          dispute_policy_id: string | null
          dispute_policy_version: number | null
          dispute_reference: string
          dispute_source: Database["public"]["Enums"]["recharge_dispute_source_enum"]
          dispute_type: Database["public"]["Enums"]["recharge_dispute_type_enum"]
          due_at: string | null
          evidence: Json
          evidence_deadline: string | null
          evidence_due_at: string | null
          failure_code: string | null
          financial_exposure_amount: number | null
          financial_resolution_status: Database["public"]["Enums"]["financial_resolution_status_enum"]
          first_decision_at: string | null
          first_decision_by: string | null
          gateway_id: string | null
          gateway_mode: string | null
          id: string
          idempotency_key: string | null
          last_action_idempotency_key: string | null
          legacy_status_original: string | null
          metadata: Json
          metadata_safe: Json
          opened_at: string | null
          opened_by: string | null
          original_base_coins: number | null
          original_bonus_coins: number | null
          original_paid_amount: number | null
          original_payment_reference: string | null
          parent_dispute_id: string | null
          payment_method_id: string | null
          policy_snapshot: Json | null
          priority: Database["public"]["Enums"]["recharge_dispute_priority_enum"]
          provider_case_reference: string | null
          provider_chargeback_id: string | null
          provider_decision: string | null
          provider_decision_at: string | null
          provider_dispute_id: string | null
          provider_event_id: string | null
          provider_mode: string | null
          provider_opened_at: string | null
          provider_payment_id: string | null
          provider_reason_category: string | null
          provider_reason_code: string | null
          provider_status: string | null
          provider_updated_at: string | null
          provisional_action: Database["public"]["Enums"]["recharge_dispute_provisional_action_enum"]
          provisional_expires_at: string | null
          reason: string
          reason_code: string | null
          recommended_resolution_amount: number | null
          recoverable_coin_amount: number | null
          refund_id: string | null
          rejected_at: string | null
          rejected_by: string | null
          reopen_reason: string | null
          reopen_sequence: number
          reopened_from_status:
            | Database["public"]["Enums"]["recharge_dispute_status_enum"]
            | null
          request_id: string
          requested_by: string | null
          requires_second_decision: boolean
          resolution: string | null
          resolution_code: string | null
          resolution_reason: string | null
          resolution_version: number
          resolved_at: string | null
          resolved_by: string | null
          response_due_at: string | null
          root_dispute_id: string | null
          safe_internal_summary: string | null
          second_decision_at: string | null
          second_decision_by: string | null
          severity: Database["public"]["Enums"]["recharge_dispute_severity_enum"]
          sla_policy_id: string | null
          status: Database["public"]["Enums"]["recharge_dispute_status_enum"]
          summary: string | null
          threshold_snapshot: Json | null
          title: string | null
          triaged_at: string | null
          triaged_by: string | null
          unrecovered_coin_amount: number | null
          updated_at: string
          user_claim: string | null
          user_id: string | null
        }
        Insert: {
          already_refunded_amount?: number | null
          amount?: number | null
          approved_resolution_amount?: number | null
          assigned_team?: string | null
          assigned_to?: string | null
          bonus_already_reversed?: number | null
          cancelled_at?: string | null
          cancelled_by?: string | null
          chargeback_amount?: number | null
          chargeback_currency?: string | null
          claimed_amount?: number | null
          closed_at?: string | null
          closed_by?: string | null
          coins_already_reversed?: number | null
          created_at?: string
          currency?: string | null
          currency_code?: string | null
          current_available_bonus?: number | null
          current_available_coins?: number | null
          current_exposure_checked_at?: string | null
          current_exposure_snapshot?: Json | null
          decision_type?: string | null
          description?: string | null
          dispute_policy_id?: string | null
          dispute_policy_version?: number | null
          dispute_reference: string
          dispute_source?: Database["public"]["Enums"]["recharge_dispute_source_enum"]
          dispute_type?: Database["public"]["Enums"]["recharge_dispute_type_enum"]
          due_at?: string | null
          evidence?: Json
          evidence_deadline?: string | null
          evidence_due_at?: string | null
          failure_code?: string | null
          financial_exposure_amount?: number | null
          financial_resolution_status?: Database["public"]["Enums"]["financial_resolution_status_enum"]
          first_decision_at?: string | null
          first_decision_by?: string | null
          gateway_id?: string | null
          gateway_mode?: string | null
          id?: string
          idempotency_key?: string | null
          last_action_idempotency_key?: string | null
          legacy_status_original?: string | null
          metadata?: Json
          metadata_safe?: Json
          opened_at?: string | null
          opened_by?: string | null
          original_base_coins?: number | null
          original_bonus_coins?: number | null
          original_paid_amount?: number | null
          original_payment_reference?: string | null
          parent_dispute_id?: string | null
          payment_method_id?: string | null
          policy_snapshot?: Json | null
          priority?: Database["public"]["Enums"]["recharge_dispute_priority_enum"]
          provider_case_reference?: string | null
          provider_chargeback_id?: string | null
          provider_decision?: string | null
          provider_decision_at?: string | null
          provider_dispute_id?: string | null
          provider_event_id?: string | null
          provider_mode?: string | null
          provider_opened_at?: string | null
          provider_payment_id?: string | null
          provider_reason_category?: string | null
          provider_reason_code?: string | null
          provider_status?: string | null
          provider_updated_at?: string | null
          provisional_action?: Database["public"]["Enums"]["recharge_dispute_provisional_action_enum"]
          provisional_expires_at?: string | null
          reason: string
          reason_code?: string | null
          recommended_resolution_amount?: number | null
          recoverable_coin_amount?: number | null
          refund_id?: string | null
          rejected_at?: string | null
          rejected_by?: string | null
          reopen_reason?: string | null
          reopen_sequence?: number
          reopened_from_status?:
            | Database["public"]["Enums"]["recharge_dispute_status_enum"]
            | null
          request_id: string
          requested_by?: string | null
          requires_second_decision?: boolean
          resolution?: string | null
          resolution_code?: string | null
          resolution_reason?: string | null
          resolution_version?: number
          resolved_at?: string | null
          resolved_by?: string | null
          response_due_at?: string | null
          root_dispute_id?: string | null
          safe_internal_summary?: string | null
          second_decision_at?: string | null
          second_decision_by?: string | null
          severity?: Database["public"]["Enums"]["recharge_dispute_severity_enum"]
          sla_policy_id?: string | null
          status?: Database["public"]["Enums"]["recharge_dispute_status_enum"]
          summary?: string | null
          threshold_snapshot?: Json | null
          title?: string | null
          triaged_at?: string | null
          triaged_by?: string | null
          unrecovered_coin_amount?: number | null
          updated_at?: string
          user_claim?: string | null
          user_id?: string | null
        }
        Update: {
          already_refunded_amount?: number | null
          amount?: number | null
          approved_resolution_amount?: number | null
          assigned_team?: string | null
          assigned_to?: string | null
          bonus_already_reversed?: number | null
          cancelled_at?: string | null
          cancelled_by?: string | null
          chargeback_amount?: number | null
          chargeback_currency?: string | null
          claimed_amount?: number | null
          closed_at?: string | null
          closed_by?: string | null
          coins_already_reversed?: number | null
          created_at?: string
          currency?: string | null
          currency_code?: string | null
          current_available_bonus?: number | null
          current_available_coins?: number | null
          current_exposure_checked_at?: string | null
          current_exposure_snapshot?: Json | null
          decision_type?: string | null
          description?: string | null
          dispute_policy_id?: string | null
          dispute_policy_version?: number | null
          dispute_reference?: string
          dispute_source?: Database["public"]["Enums"]["recharge_dispute_source_enum"]
          dispute_type?: Database["public"]["Enums"]["recharge_dispute_type_enum"]
          due_at?: string | null
          evidence?: Json
          evidence_deadline?: string | null
          evidence_due_at?: string | null
          failure_code?: string | null
          financial_exposure_amount?: number | null
          financial_resolution_status?: Database["public"]["Enums"]["financial_resolution_status_enum"]
          first_decision_at?: string | null
          first_decision_by?: string | null
          gateway_id?: string | null
          gateway_mode?: string | null
          id?: string
          idempotency_key?: string | null
          last_action_idempotency_key?: string | null
          legacy_status_original?: string | null
          metadata?: Json
          metadata_safe?: Json
          opened_at?: string | null
          opened_by?: string | null
          original_base_coins?: number | null
          original_bonus_coins?: number | null
          original_paid_amount?: number | null
          original_payment_reference?: string | null
          parent_dispute_id?: string | null
          payment_method_id?: string | null
          policy_snapshot?: Json | null
          priority?: Database["public"]["Enums"]["recharge_dispute_priority_enum"]
          provider_case_reference?: string | null
          provider_chargeback_id?: string | null
          provider_decision?: string | null
          provider_decision_at?: string | null
          provider_dispute_id?: string | null
          provider_event_id?: string | null
          provider_mode?: string | null
          provider_opened_at?: string | null
          provider_payment_id?: string | null
          provider_reason_category?: string | null
          provider_reason_code?: string | null
          provider_status?: string | null
          provider_updated_at?: string | null
          provisional_action?: Database["public"]["Enums"]["recharge_dispute_provisional_action_enum"]
          provisional_expires_at?: string | null
          reason?: string
          reason_code?: string | null
          recommended_resolution_amount?: number | null
          recoverable_coin_amount?: number | null
          refund_id?: string | null
          rejected_at?: string | null
          rejected_by?: string | null
          reopen_reason?: string | null
          reopen_sequence?: number
          reopened_from_status?:
            | Database["public"]["Enums"]["recharge_dispute_status_enum"]
            | null
          request_id?: string
          requested_by?: string | null
          requires_second_decision?: boolean
          resolution?: string | null
          resolution_code?: string | null
          resolution_reason?: string | null
          resolution_version?: number
          resolved_at?: string | null
          resolved_by?: string | null
          response_due_at?: string | null
          root_dispute_id?: string | null
          safe_internal_summary?: string | null
          second_decision_at?: string | null
          second_decision_by?: string | null
          severity?: Database["public"]["Enums"]["recharge_dispute_severity_enum"]
          sla_policy_id?: string | null
          status?: Database["public"]["Enums"]["recharge_dispute_status_enum"]
          summary?: string | null
          threshold_snapshot?: Json | null
          title?: string | null
          triaged_at?: string | null
          triaged_by?: string | null
          unrecovered_coin_amount?: number | null
          updated_at?: string
          user_claim?: string | null
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "recharge_disputes_gateway_id_fkey"
            columns: ["gateway_id"]
            isOneToOne: false
            referencedRelation: "payment_gateway_stats"
            referencedColumns: ["gateway_id"]
          },
          {
            foreignKeyName: "recharge_disputes_gateway_id_fkey"
            columns: ["gateway_id"]
            isOneToOne: false
            referencedRelation: "payment_gateways"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "recharge_disputes_parent_dispute_id_fkey"
            columns: ["parent_dispute_id"]
            isOneToOne: false
            referencedRelation: "recharge_disputes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "recharge_disputes_payment_method_id_fkey"
            columns: ["payment_method_id"]
            isOneToOne: false
            referencedRelation: "payment_methods"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "recharge_disputes_refund_id_fkey"
            columns: ["refund_id"]
            isOneToOne: false
            referencedRelation: "recharge_refunds"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "recharge_disputes_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "recharge_requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "recharge_disputes_root_dispute_id_fkey"
            columns: ["root_dispute_id"]
            isOneToOne: false
            referencedRelation: "recharge_disputes"
            referencedColumns: ["id"]
          },
        ]
      }
      recharge_package_bonuses: {
        Row: {
          active: boolean
          created_at: string
          ends_at: string | null
          extra_coins: number
          id: string
          label_ar: string | null
          label_en: string | null
          package_id: string
          starts_at: string | null
          target: Database["public"]["Enums"]["recharge_user_target"]
          updated_at: string
        }
        Insert: {
          active?: boolean
          created_at?: string
          ends_at?: string | null
          extra_coins?: number
          id?: string
          label_ar?: string | null
          label_en?: string | null
          package_id: string
          starts_at?: string | null
          target?: Database["public"]["Enums"]["recharge_user_target"]
          updated_at?: string
        }
        Update: {
          active?: boolean
          created_at?: string
          ends_at?: string | null
          extra_coins?: number
          id?: string
          label_ar?: string | null
          label_en?: string | null
          package_id?: string
          starts_at?: string | null
          target?: Database["public"]["Enums"]["recharge_user_target"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "recharge_package_bonuses_package_id_fkey"
            columns: ["package_id"]
            isOneToOne: false
            referencedRelation: "recharge_packages"
            referencedColumns: ["id"]
          },
        ]
      }
      recharge_package_prices: {
        Row: {
          active: boolean
          country_code: string | null
          created_at: string
          created_by: string | null
          currency_code: string
          id: string
          is_default: boolean
          package_id: string
          payment_gateway_id: string | null
          payment_method_id: string | null
          price: number
          updated_at: string
        }
        Insert: {
          active?: boolean
          country_code?: string | null
          created_at?: string
          created_by?: string | null
          currency_code: string
          id?: string
          is_default?: boolean
          package_id: string
          payment_gateway_id?: string | null
          payment_method_id?: string | null
          price: number
          updated_at?: string
        }
        Update: {
          active?: boolean
          country_code?: string | null
          created_at?: string
          created_by?: string | null
          currency_code?: string
          id?: string
          is_default?: boolean
          package_id?: string
          payment_gateway_id?: string | null
          payment_method_id?: string | null
          price?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "recharge_package_prices_package_id_fkey"
            columns: ["package_id"]
            isOneToOne: false
            referencedRelation: "recharge_packages"
            referencedColumns: ["id"]
          },
        ]
      }
      recharge_package_stats: {
        Row: {
          created_at: string
          id: string
          package_id: string
          purchases_count: number
          revenue_amount: number
          stat_date: string
          updated_at: string
          views_count: number
        }
        Insert: {
          created_at?: string
          id?: string
          package_id: string
          purchases_count?: number
          revenue_amount?: number
          stat_date?: string
          updated_at?: string
          views_count?: number
        }
        Update: {
          created_at?: string
          id?: string
          package_id?: string
          purchases_count?: number
          revenue_amount?: number
          stat_date?: string
          updated_at?: string
          views_count?: number
        }
        Relationships: [
          {
            foreignKeyName: "recharge_package_stats_package_id_fkey"
            columns: ["package_id"]
            isOneToOne: false
            referencedRelation: "recharge_packages"
            referencedColumns: ["id"]
          },
        ]
      }
      recharge_package_targets: {
        Row: {
          country_codes: string[] | null
          created_at: string
          exclude_user_ids: string[] | null
          id: string
          include_user_ids: string[] | null
          max_level: number | null
          max_vip: number | null
          min_level: number | null
          min_vip: number | null
          package_id: string
          updated_at: string
          user_target: Database["public"]["Enums"]["recharge_user_target"]
        }
        Insert: {
          country_codes?: string[] | null
          created_at?: string
          exclude_user_ids?: string[] | null
          id?: string
          include_user_ids?: string[] | null
          max_level?: number | null
          max_vip?: number | null
          min_level?: number | null
          min_vip?: number | null
          package_id: string
          updated_at?: string
          user_target?: Database["public"]["Enums"]["recharge_user_target"]
        }
        Update: {
          country_codes?: string[] | null
          created_at?: string
          exclude_user_ids?: string[] | null
          id?: string
          include_user_ids?: string[] | null
          max_level?: number | null
          max_vip?: number | null
          min_level?: number | null
          min_vip?: number | null
          package_id?: string
          updated_at?: string
          user_target?: Database["public"]["Enums"]["recharge_user_target"]
        }
        Relationships: [
          {
            foreignKeyName: "recharge_package_targets_package_id_fkey"
            columns: ["package_id"]
            isOneToOne: false
            referencedRelation: "recharge_packages"
            referencedColumns: ["id"]
          },
        ]
      }
      recharge_package_versions: {
        Row: {
          change_note: string | null
          created_at: string
          created_by: string | null
          id: string
          package_id: string
          snapshot: Json
          version: number
        }
        Insert: {
          change_note?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          package_id: string
          snapshot: Json
          version: number
        }
        Update: {
          change_note?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          package_id?: string
          snapshot?: Json
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "recharge_package_versions_package_id_fkey"
            columns: ["package_id"]
            isOneToOne: false
            referencedRelation: "recharge_packages"
            referencedColumns: ["id"]
          },
        ]
      }
      recharge_packages: {
        Row: {
          archived_at: string | null
          badge_text_ar: string | null
          badge_text_en: string | null
          base_coins: number
          bonus_coins: number
          code: string
          created_at: string
          created_by: string | null
          deleted_at: string | null
          description_ar: string | null
          description_en: string | null
          ends_at: string | null
          featured: boolean
          id: string
          image_url: string | null
          name_ar: string
          name_en: string
          published_at: string | null
          sort_order: number
          starts_at: string | null
          status: Database["public"]["Enums"]["recharge_package_status"]
          terms_ar: string | null
          terms_en: string | null
          total_coins: number | null
          updated_at: string
          updated_by: string | null
          version: number
        }
        Insert: {
          archived_at?: string | null
          badge_text_ar?: string | null
          badge_text_en?: string | null
          base_coins: number
          bonus_coins?: number
          code: string
          created_at?: string
          created_by?: string | null
          deleted_at?: string | null
          description_ar?: string | null
          description_en?: string | null
          ends_at?: string | null
          featured?: boolean
          id?: string
          image_url?: string | null
          name_ar: string
          name_en: string
          published_at?: string | null
          sort_order?: number
          starts_at?: string | null
          status?: Database["public"]["Enums"]["recharge_package_status"]
          terms_ar?: string | null
          terms_en?: string | null
          total_coins?: number | null
          updated_at?: string
          updated_by?: string | null
          version?: number
        }
        Update: {
          archived_at?: string | null
          badge_text_ar?: string | null
          badge_text_en?: string | null
          base_coins?: number
          bonus_coins?: number
          code?: string
          created_at?: string
          created_by?: string | null
          deleted_at?: string | null
          description_ar?: string | null
          description_en?: string | null
          ends_at?: string | null
          featured?: boolean
          id?: string
          image_url?: string | null
          name_ar?: string
          name_en?: string
          published_at?: string | null
          sort_order?: number
          starts_at?: string | null
          status?: Database["public"]["Enums"]["recharge_package_status"]
          terms_ar?: string | null
          terms_en?: string | null
          total_coins?: number | null
          updated_at?: string
          updated_by?: string | null
          version?: number
        }
        Relationships: []
      }
      recharge_receipts: {
        Row: {
          created_at: string
          currency: string | null
          id: string
          is_quarantined: boolean
          malware_scan_status: Database["public"]["Enums"]["malware_scan_status"]
          metadata_safe: Json
          mime_type: string | null
          original_filename_masked: string | null
          paid_amount: number | null
          paid_at: string | null
          payment_reference: string | null
          receipt_number: string | null
          receipt_url: string | null
          request_id: string
          review_decision: string | null
          review_reason: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          sender_name: string | null
          sha256_hash: string | null
          size_bytes: number | null
          status: Database["public"]["Enums"]["recharge_receipt_status"]
          storage_bucket: string
          storage_object_path: string | null
          submitted_at: string | null
          supersedes_receipt_id: string | null
          updated_at: string
          uploaded_by: string | null
          user_id: string | null
        }
        Insert: {
          created_at?: string
          currency?: string | null
          id?: string
          is_quarantined?: boolean
          malware_scan_status?: Database["public"]["Enums"]["malware_scan_status"]
          metadata_safe?: Json
          mime_type?: string | null
          original_filename_masked?: string | null
          paid_amount?: number | null
          paid_at?: string | null
          payment_reference?: string | null
          receipt_number?: string | null
          receipt_url?: string | null
          request_id: string
          review_decision?: string | null
          review_reason?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          sender_name?: string | null
          sha256_hash?: string | null
          size_bytes?: number | null
          status?: Database["public"]["Enums"]["recharge_receipt_status"]
          storage_bucket?: string
          storage_object_path?: string | null
          submitted_at?: string | null
          supersedes_receipt_id?: string | null
          updated_at?: string
          uploaded_by?: string | null
          user_id?: string | null
        }
        Update: {
          created_at?: string
          currency?: string | null
          id?: string
          is_quarantined?: boolean
          malware_scan_status?: Database["public"]["Enums"]["malware_scan_status"]
          metadata_safe?: Json
          mime_type?: string | null
          original_filename_masked?: string | null
          paid_amount?: number | null
          paid_at?: string | null
          payment_reference?: string | null
          receipt_number?: string | null
          receipt_url?: string | null
          request_id?: string
          review_decision?: string | null
          review_reason?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          sender_name?: string | null
          sha256_hash?: string | null
          size_bytes?: number | null
          status?: Database["public"]["Enums"]["recharge_receipt_status"]
          storage_bucket?: string
          storage_object_path?: string | null
          submitted_at?: string | null
          supersedes_receipt_id?: string | null
          updated_at?: string
          uploaded_by?: string | null
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "recharge_receipts_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "recharge_requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "recharge_receipts_supersedes_receipt_id_fkey"
            columns: ["supersedes_receipt_id"]
            isOneToOne: false
            referencedRelation: "recharge_receipts"
            referencedColumns: ["id"]
          },
        ]
      }
      recharge_refund_attempts: {
        Row: {
          attempt_number: number
          created_at: string
          execution_owner_id: string | null
          execution_token_hash: string | null
          failure_code: string | null
          finalized_at: string | null
          finished_at: string | null
          gateway_id: string | null
          gateway_mode:
            | Database["public"]["Enums"]["payment_gateway_mode"]
            | null
          id: string
          idempotency_key: string | null
          provider_idempotency_key: string | null
          provider_refund_id: string | null
          reason: string | null
          refund_id: string
          request_correlation_id: string | null
          result: Json
          safe_error: string | null
          started_at: string
          status: string
          trigger_type: string
          triggered_by: string | null
        }
        Insert: {
          attempt_number: number
          created_at?: string
          execution_owner_id?: string | null
          execution_token_hash?: string | null
          failure_code?: string | null
          finalized_at?: string | null
          finished_at?: string | null
          gateway_id?: string | null
          gateway_mode?:
            | Database["public"]["Enums"]["payment_gateway_mode"]
            | null
          id?: string
          idempotency_key?: string | null
          provider_idempotency_key?: string | null
          provider_refund_id?: string | null
          reason?: string | null
          refund_id: string
          request_correlation_id?: string | null
          result?: Json
          safe_error?: string | null
          started_at?: string
          status: string
          trigger_type: string
          triggered_by?: string | null
        }
        Update: {
          attempt_number?: number
          created_at?: string
          execution_owner_id?: string | null
          execution_token_hash?: string | null
          failure_code?: string | null
          finalized_at?: string | null
          finished_at?: string | null
          gateway_id?: string | null
          gateway_mode?:
            | Database["public"]["Enums"]["payment_gateway_mode"]
            | null
          id?: string
          idempotency_key?: string | null
          provider_idempotency_key?: string | null
          provider_refund_id?: string | null
          reason?: string | null
          refund_id?: string
          request_correlation_id?: string | null
          result?: Json
          safe_error?: string | null
          started_at?: string
          status?: string
          trigger_type?: string
          triggered_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "recharge_refund_attempts_refund_id_fkey"
            columns: ["refund_id"]
            isOneToOne: false
            referencedRelation: "recharge_refunds"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "recharge_refund_attempts_triggered_by_fkey"
            columns: ["triggered_by"]
            isOneToOne: false
            referencedRelation: "admin_users"
            referencedColumns: ["id"]
          },
        ]
      }
      recharge_refunds: {
        Row: {
          amount: number
          approved_amount: number | null
          approved_at: string | null
          approved_by: string | null
          base_coins_to_reverse: number | null
          bonus_actually_reversed: number | null
          bonus_coins_reversed: number
          bonus_coins_to_reverse: number | null
          bonus_policy_snapshot: string | null
          cash_amount: number | null
          coins_actually_reversed: number | null
          coins_reversed: number
          created_at: string
          currency_code: string | null
          decision_reason: string | null
          executed_at: string | null
          executed_by: string | null
          execution_owner_id: string | null
          execution_started_at: string | null
          failure_code: string | null
          failure_reason: string | null
          first_reviewed_at: string | null
          first_reviewed_by: string | null
          gateway_execution_state: string | null
          gateway_id: string | null
          gateway_mode:
            | Database["public"]["Enums"]["payment_gateway_mode"]
            | null
          gateway_refund_id: string | null
          id: string
          idempotency_key: string | null
          last_retry_at: string | null
          last_status_checked_at: string | null
          metadata: Json
          next_status_check_at: string | null
          original_payment_reference: string | null
          payment_method_id: string | null
          polling_lease_expires_at: string | null
          polling_owner: string | null
          polling_started_at: string | null
          preflight_snapshot: Json | null
          processed_by: string | null
          provider_idempotency_key: string | null
          provider_refund_id: string | null
          reason: string
          refund_reference: string
          refund_scope: Database["public"]["Enums"]["refund_scope"] | null
          refund_type: Database["public"]["Enums"]["refund_type"]
          rejected_at: string | null
          rejected_by: string | null
          request_id: string
          requested_amount: number | null
          requested_at: string
          requested_by: string | null
          requires_coin_reversal: boolean | null
          requires_second_approval: boolean | null
          retry_attempt_count: number
          reversal_mode: string
          second_reviewed_at: string | null
          second_reviewed_by: string | null
          second_reviewer_id: string | null
          status: Database["public"]["Enums"]["refund_status"]
          status_refresh_count: number
          threshold_rule_id: string | null
          unrecovered_bonus_amount: number | null
          unrecovered_coin_amount: number | null
          updated_at: string
          user_id: string | null
        }
        Insert: {
          amount: number
          approved_amount?: number | null
          approved_at?: string | null
          approved_by?: string | null
          base_coins_to_reverse?: number | null
          bonus_actually_reversed?: number | null
          bonus_coins_reversed?: number
          bonus_coins_to_reverse?: number | null
          bonus_policy_snapshot?: string | null
          cash_amount?: number | null
          coins_actually_reversed?: number | null
          coins_reversed?: number
          created_at?: string
          currency_code?: string | null
          decision_reason?: string | null
          executed_at?: string | null
          executed_by?: string | null
          execution_owner_id?: string | null
          execution_started_at?: string | null
          failure_code?: string | null
          failure_reason?: string | null
          first_reviewed_at?: string | null
          first_reviewed_by?: string | null
          gateway_execution_state?: string | null
          gateway_id?: string | null
          gateway_mode?:
            | Database["public"]["Enums"]["payment_gateway_mode"]
            | null
          gateway_refund_id?: string | null
          id?: string
          idempotency_key?: string | null
          last_retry_at?: string | null
          last_status_checked_at?: string | null
          metadata?: Json
          next_status_check_at?: string | null
          original_payment_reference?: string | null
          payment_method_id?: string | null
          polling_lease_expires_at?: string | null
          polling_owner?: string | null
          polling_started_at?: string | null
          preflight_snapshot?: Json | null
          processed_by?: string | null
          provider_idempotency_key?: string | null
          provider_refund_id?: string | null
          reason: string
          refund_reference: string
          refund_scope?: Database["public"]["Enums"]["refund_scope"] | null
          refund_type?: Database["public"]["Enums"]["refund_type"]
          rejected_at?: string | null
          rejected_by?: string | null
          request_id: string
          requested_amount?: number | null
          requested_at?: string
          requested_by?: string | null
          requires_coin_reversal?: boolean | null
          requires_second_approval?: boolean | null
          retry_attempt_count?: number
          reversal_mode?: string
          second_reviewed_at?: string | null
          second_reviewed_by?: string | null
          second_reviewer_id?: string | null
          status?: Database["public"]["Enums"]["refund_status"]
          status_refresh_count?: number
          threshold_rule_id?: string | null
          unrecovered_bonus_amount?: number | null
          unrecovered_coin_amount?: number | null
          updated_at?: string
          user_id?: string | null
        }
        Update: {
          amount?: number
          approved_amount?: number | null
          approved_at?: string | null
          approved_by?: string | null
          base_coins_to_reverse?: number | null
          bonus_actually_reversed?: number | null
          bonus_coins_reversed?: number
          bonus_coins_to_reverse?: number | null
          bonus_policy_snapshot?: string | null
          cash_amount?: number | null
          coins_actually_reversed?: number | null
          coins_reversed?: number
          created_at?: string
          currency_code?: string | null
          decision_reason?: string | null
          executed_at?: string | null
          executed_by?: string | null
          execution_owner_id?: string | null
          execution_started_at?: string | null
          failure_code?: string | null
          failure_reason?: string | null
          first_reviewed_at?: string | null
          first_reviewed_by?: string | null
          gateway_execution_state?: string | null
          gateway_id?: string | null
          gateway_mode?:
            | Database["public"]["Enums"]["payment_gateway_mode"]
            | null
          gateway_refund_id?: string | null
          id?: string
          idempotency_key?: string | null
          last_retry_at?: string | null
          last_status_checked_at?: string | null
          metadata?: Json
          next_status_check_at?: string | null
          original_payment_reference?: string | null
          payment_method_id?: string | null
          polling_lease_expires_at?: string | null
          polling_owner?: string | null
          polling_started_at?: string | null
          preflight_snapshot?: Json | null
          processed_by?: string | null
          provider_idempotency_key?: string | null
          provider_refund_id?: string | null
          reason?: string
          refund_reference?: string
          refund_scope?: Database["public"]["Enums"]["refund_scope"] | null
          refund_type?: Database["public"]["Enums"]["refund_type"]
          rejected_at?: string | null
          rejected_by?: string | null
          request_id?: string
          requested_amount?: number | null
          requested_at?: string
          requested_by?: string | null
          requires_coin_reversal?: boolean | null
          requires_second_approval?: boolean | null
          retry_attempt_count?: number
          reversal_mode?: string
          second_reviewed_at?: string | null
          second_reviewed_by?: string | null
          second_reviewer_id?: string | null
          status?: Database["public"]["Enums"]["refund_status"]
          status_refresh_count?: number
          threshold_rule_id?: string | null
          unrecovered_bonus_amount?: number | null
          unrecovered_coin_amount?: number | null
          updated_at?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "recharge_refunds_gateway_id_fkey"
            columns: ["gateway_id"]
            isOneToOne: false
            referencedRelation: "payment_gateway_stats"
            referencedColumns: ["gateway_id"]
          },
          {
            foreignKeyName: "recharge_refunds_gateway_id_fkey"
            columns: ["gateway_id"]
            isOneToOne: false
            referencedRelation: "payment_gateways"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "recharge_refunds_payment_method_id_fkey"
            columns: ["payment_method_id"]
            isOneToOne: false
            referencedRelation: "payment_methods"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "recharge_refunds_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "recharge_requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "recharge_refunds_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      recharge_request_events: {
        Row: {
          actor_id: string | null
          created_at: string
          from_status:
            | Database["public"]["Enums"]["recharge_request_status"]
            | null
          id: string
          metadata: Json
          note: string | null
          request_id: string
          to_status: Database["public"]["Enums"]["recharge_request_status"]
        }
        Insert: {
          actor_id?: string | null
          created_at?: string
          from_status?:
            | Database["public"]["Enums"]["recharge_request_status"]
            | null
          id?: string
          metadata?: Json
          note?: string | null
          request_id: string
          to_status: Database["public"]["Enums"]["recharge_request_status"]
        }
        Update: {
          actor_id?: string | null
          created_at?: string
          from_status?:
            | Database["public"]["Enums"]["recharge_request_status"]
            | null
          id?: string
          metadata?: Json
          note?: string | null
          request_id?: string
          to_status?: Database["public"]["Enums"]["recharge_request_status"]
        }
        Relationships: [
          {
            foreignKeyName: "recharge_request_events_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "recharge_requests"
            referencedColumns: ["id"]
          },
        ]
      }
      recharge_requests: {
        Row: {
          base_price: number | null
          bonus_amount: number
          cancelled_at: string | null
          coin_amount: number
          completed_at: string | null
          country_code: string | null
          created_at: string
          currency_code: string
          discount_amount: number
          expires_at: string | null
          external_reference: string | null
          failed_at: string | null
          failure_code: string | null
          failure_reason: string | null
          final_amount: number | null
          gateway_fee: number
          id: string
          idempotency_key: string | null
          metadata: Json
          package_id: string | null
          package_snapshot: Json
          package_version_id: string | null
          paid_at: string | null
          payment_account_id: string | null
          payment_account_reference: string | null
          payment_gateway_id: string | null
          payment_gateway_mode: string
          payment_method_fee: number
          payment_method_id: string | null
          payment_status: string
          price: number
          price_rule_id: string | null
          price_rule_version: number | null
          price_snapshot: Json
          provider_payment_id: string | null
          receipt_url: string | null
          refunded_at: string | null
          request_reference: string
          requires_second_review: boolean
          reviewer_id: string | null
          status: Database["public"]["Enums"]["recharge_request_status"]
          submitted_at: string | null
          tax_amount: number
          total_coins: number
          updated_at: string
          user_id: string
          verified_at: string | null
        }
        Insert: {
          base_price?: number | null
          bonus_amount?: number
          cancelled_at?: string | null
          coin_amount: number
          completed_at?: string | null
          country_code?: string | null
          created_at?: string
          currency_code: string
          discount_amount?: number
          expires_at?: string | null
          external_reference?: string | null
          failed_at?: string | null
          failure_code?: string | null
          failure_reason?: string | null
          final_amount?: number | null
          gateway_fee?: number
          id?: string
          idempotency_key?: string | null
          metadata?: Json
          package_id?: string | null
          package_snapshot?: Json
          package_version_id?: string | null
          paid_at?: string | null
          payment_account_id?: string | null
          payment_account_reference?: string | null
          payment_gateway_id?: string | null
          payment_gateway_mode?: string
          payment_method_fee?: number
          payment_method_id?: string | null
          payment_status?: string
          price: number
          price_rule_id?: string | null
          price_rule_version?: number | null
          price_snapshot?: Json
          provider_payment_id?: string | null
          receipt_url?: string | null
          refunded_at?: string | null
          request_reference: string
          requires_second_review?: boolean
          reviewer_id?: string | null
          status?: Database["public"]["Enums"]["recharge_request_status"]
          submitted_at?: string | null
          tax_amount?: number
          total_coins: number
          updated_at?: string
          user_id: string
          verified_at?: string | null
        }
        Update: {
          base_price?: number | null
          bonus_amount?: number
          cancelled_at?: string | null
          coin_amount?: number
          completed_at?: string | null
          country_code?: string | null
          created_at?: string
          currency_code?: string
          discount_amount?: number
          expires_at?: string | null
          external_reference?: string | null
          failed_at?: string | null
          failure_code?: string | null
          failure_reason?: string | null
          final_amount?: number | null
          gateway_fee?: number
          id?: string
          idempotency_key?: string | null
          metadata?: Json
          package_id?: string | null
          package_snapshot?: Json
          package_version_id?: string | null
          paid_at?: string | null
          payment_account_id?: string | null
          payment_account_reference?: string | null
          payment_gateway_id?: string | null
          payment_gateway_mode?: string
          payment_method_fee?: number
          payment_method_id?: string | null
          payment_status?: string
          price?: number
          price_rule_id?: string | null
          price_rule_version?: number | null
          price_snapshot?: Json
          provider_payment_id?: string | null
          receipt_url?: string | null
          refunded_at?: string | null
          request_reference?: string
          requires_second_review?: boolean
          reviewer_id?: string | null
          status?: Database["public"]["Enums"]["recharge_request_status"]
          submitted_at?: string | null
          tax_amount?: number
          total_coins?: number
          updated_at?: string
          user_id?: string
          verified_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "recharge_requests_package_id_fkey"
            columns: ["package_id"]
            isOneToOne: false
            referencedRelation: "recharge_packages"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "recharge_requests_package_version_id_fkey"
            columns: ["package_version_id"]
            isOneToOne: false
            referencedRelation: "recharge_package_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "recharge_requests_payment_account_id_fkey"
            columns: ["payment_account_id"]
            isOneToOne: false
            referencedRelation: "payment_method_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "recharge_requests_payment_gateway_id_fkey"
            columns: ["payment_gateway_id"]
            isOneToOne: false
            referencedRelation: "payment_gateway_stats"
            referencedColumns: ["gateway_id"]
          },
          {
            foreignKeyName: "recharge_requests_payment_gateway_id_fkey"
            columns: ["payment_gateway_id"]
            isOneToOne: false
            referencedRelation: "payment_gateways"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "recharge_requests_payment_method_id_fkey"
            columns: ["payment_method_id"]
            isOneToOne: false
            referencedRelation: "payment_methods"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "recharge_requests_price_rule_id_fkey"
            columns: ["price_rule_id"]
            isOneToOne: false
            referencedRelation: "coin_price_rules"
            referencedColumns: ["id"]
          },
        ]
      }
      refund_policies: {
        Row: {
          allow_money_only_refund: boolean
          allow_partial_refund: boolean
          country_code: string | null
          created_at: string
          created_by: string | null
          currency_code: string | null
          decimal_scale: number
          ends_at: string | null
          gateway_id: string | null
          id: string
          insufficient_balance_policy: string
          name: string
          partial_bonus_policy: string
          refund_type_scope: string[]
          refund_window_days: number
          require_wallet_reversal_before_gateway_refund: boolean
          rounding_mode: string
          second_approval_threshold: number
          single_approval_threshold: number
          starts_at: string
          status: string
          updated_at: string
          version: number
        }
        Insert: {
          allow_money_only_refund?: boolean
          allow_partial_refund?: boolean
          country_code?: string | null
          created_at?: string
          created_by?: string | null
          currency_code?: string | null
          decimal_scale?: number
          ends_at?: string | null
          gateway_id?: string | null
          id?: string
          insufficient_balance_policy?: string
          name: string
          partial_bonus_policy?: string
          refund_type_scope?: string[]
          refund_window_days?: number
          require_wallet_reversal_before_gateway_refund?: boolean
          rounding_mode?: string
          second_approval_threshold?: number
          single_approval_threshold?: number
          starts_at?: string
          status?: string
          updated_at?: string
          version?: number
        }
        Update: {
          allow_money_only_refund?: boolean
          allow_partial_refund?: boolean
          country_code?: string | null
          created_at?: string
          created_by?: string | null
          currency_code?: string | null
          decimal_scale?: number
          ends_at?: string | null
          gateway_id?: string | null
          id?: string
          insufficient_balance_policy?: string
          name?: string
          partial_bonus_policy?: string
          refund_type_scope?: string[]
          refund_window_days?: number
          require_wallet_reversal_before_gateway_refund?: boolean
          rounding_mode?: string
          second_approval_threshold?: number
          single_approval_threshold?: number
          starts_at?: string
          status?: string
          updated_at?: string
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "refund_policies_gateway_id_fkey"
            columns: ["gateway_id"]
            isOneToOne: false
            referencedRelation: "payment_gateway_stats"
            referencedColumns: ["gateway_id"]
          },
          {
            foreignKeyName: "refund_policies_gateway_id_fkey"
            columns: ["gateway_id"]
            isOneToOne: false
            referencedRelation: "payment_gateways"
            referencedColumns: ["id"]
          },
        ]
      }
      refund_retry_policies: {
        Row: {
          active: boolean
          backoff_multiplier: number
          created_at: string
          created_by: string | null
          gateway_id: string | null
          gateway_mode:
            | Database["public"]["Enums"]["payment_gateway_mode"]
            | null
          id: string
          initial_backoff_seconds: number
          jitter_percent: number
          max_backoff_seconds: number
          max_create_attempts: number
          max_status_refresh_attempts: number
          move_to_manual_review_after: number
          polling_interval_seconds: number
          stale_processing_timeout_minutes: number
          unknown_result_timeout_minutes: number
          updated_at: string
          version: number
        }
        Insert: {
          active?: boolean
          backoff_multiplier?: number
          created_at?: string
          created_by?: string | null
          gateway_id?: string | null
          gateway_mode?:
            | Database["public"]["Enums"]["payment_gateway_mode"]
            | null
          id?: string
          initial_backoff_seconds?: number
          jitter_percent?: number
          max_backoff_seconds?: number
          max_create_attempts?: number
          max_status_refresh_attempts?: number
          move_to_manual_review_after?: number
          polling_interval_seconds?: number
          stale_processing_timeout_minutes?: number
          unknown_result_timeout_minutes?: number
          updated_at?: string
          version?: number
        }
        Update: {
          active?: boolean
          backoff_multiplier?: number
          created_at?: string
          created_by?: string | null
          gateway_id?: string | null
          gateway_mode?:
            | Database["public"]["Enums"]["payment_gateway_mode"]
            | null
          id?: string
          initial_backoff_seconds?: number
          jitter_percent?: number
          max_backoff_seconds?: number
          max_create_attempts?: number
          max_status_refresh_attempts?: number
          move_to_manual_review_after?: number
          polling_interval_seconds?: number
          stale_processing_timeout_minutes?: number
          unknown_result_timeout_minutes?: number
          updated_at?: string
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "refund_retry_policies_gateway_id_fkey"
            columns: ["gateway_id"]
            isOneToOne: false
            referencedRelation: "payment_gateway_stats"
            referencedColumns: ["gateway_id"]
          },
          {
            foreignKeyName: "refund_retry_policies_gateway_id_fkey"
            columns: ["gateway_id"]
            isOneToOne: false
            referencedRelation: "payment_gateways"
            referencedColumns: ["id"]
          },
        ]
      }
      role_permissions: {
        Row: {
          created_at: string
          permission_key: string
          role: Database["public"]["Enums"]["admin_role"]
        }
        Insert: {
          created_at?: string
          permission_key: string
          role: Database["public"]["Enums"]["admin_role"]
        }
        Update: {
          created_at?: string
          permission_key?: string
          role?: Database["public"]["Enums"]["admin_role"]
        }
        Relationships: [
          {
            foreignKeyName: "role_permissions_permission_key_fkey"
            columns: ["permission_key"]
            isOneToOne: false
            referencedRelation: "permissions"
            referencedColumns: ["key"]
          },
        ]
      }
      roles: {
        Row: {
          created_at: string
          description: string | null
          label_ar: string
          label_en: string
          role: Database["public"]["Enums"]["admin_role"]
        }
        Insert: {
          created_at?: string
          description?: string | null
          label_ar: string
          label_en: string
          role: Database["public"]["Enums"]["admin_role"]
        }
        Update: {
          created_at?: string
          description?: string | null
          label_ar?: string
          label_en?: string
          role?: Database["public"]["Enums"]["admin_role"]
        }
        Relationships: []
      }
      security_definer_public_allowlist: {
        Row: {
          added_at: string
          added_by: string | null
          decision: string | null
          function_args: string
          function_name: string
          reason: string
          risk: string | null
        }
        Insert: {
          added_at?: string
          added_by?: string | null
          decision?: string | null
          function_args: string
          function_name: string
          reason: string
          risk?: string | null
        }
        Update: {
          added_at?: string
          added_by?: string | null
          decision?: string | null
          function_args?: string
          function_name?: string
          reason?: string
          risk?: string | null
        }
        Relationships: []
      }
      system_accounts: {
        Row: {
          account_type: string
          code: string
          created_at: string
          currency: string | null
          id: string
          is_system: boolean
          name: string
        }
        Insert: {
          account_type: string
          code: string
          created_at?: string
          currency?: string | null
          id?: string
          is_system?: boolean
          name: string
        }
        Update: {
          account_type?: string
          code?: string
          created_at?: string
          currency?: string | null
          id?: string
          is_system?: boolean
          name?: string
        }
        Relationships: []
      }
      system_ledger: {
        Row: {
          amount: number
          asset_class: string
          batch_reference: string | null
          created_at: string
          created_by: string | null
          currency: string | null
          direction: string
          id: number
          ledger_side: string | null
          metadata: Json
          paired_user_ledger_id: number | null
          recharge_request_id: string | null
          reference: string | null
          refund_id: string | null
          system_account_id: string
          transaction_group_id: string | null
        }
        Insert: {
          amount: number
          asset_class: string
          batch_reference?: string | null
          created_at?: string
          created_by?: string | null
          currency?: string | null
          direction: string
          id?: number
          ledger_side?: string | null
          metadata?: Json
          paired_user_ledger_id?: number | null
          recharge_request_id?: string | null
          reference?: string | null
          refund_id?: string | null
          system_account_id: string
          transaction_group_id?: string | null
        }
        Update: {
          amount?: number
          asset_class?: string
          batch_reference?: string | null
          created_at?: string
          created_by?: string | null
          currency?: string | null
          direction?: string
          id?: number
          ledger_side?: string | null
          metadata?: Json
          paired_user_ledger_id?: number | null
          recharge_request_id?: string | null
          reference?: string | null
          refund_id?: string | null
          system_account_id?: string
          transaction_group_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "system_ledger_recharge_request_id_fkey"
            columns: ["recharge_request_id"]
            isOneToOne: false
            referencedRelation: "recharge_requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "system_ledger_refund_id_fkey"
            columns: ["refund_id"]
            isOneToOne: false
            referencedRelation: "recharge_refunds"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "system_ledger_system_account_id_fkey"
            columns: ["system_account_id"]
            isOneToOne: false
            referencedRelation: "system_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      system_settings: {
        Row: {
          key: string
          updated_at: string
          updated_by: string | null
          value: Json
        }
        Insert: {
          key: string
          updated_at?: string
          updated_by?: string | null
          value?: Json
        }
        Update: {
          key?: string
          updated_at?: string
          updated_by?: string | null
          value?: Json
        }
        Relationships: []
      }
      transaction_message_outbox: {
        Row: {
          attempts: number
          available_at: string
          created_at: string
          event_type: string
          id: string
          idempotency_key: string
          last_error: string | null
          processed_at: string | null
          recipient_user_id: string
          safe_payload: Json
          status: Database["public"]["Enums"]["txn_outbox_status"]
          transaction_id: string
          transaction_type: string
        }
        Insert: {
          attempts?: number
          available_at?: string
          created_at?: string
          event_type: string
          id?: string
          idempotency_key: string
          last_error?: string | null
          processed_at?: string | null
          recipient_user_id: string
          safe_payload?: Json
          status?: Database["public"]["Enums"]["txn_outbox_status"]
          transaction_id: string
          transaction_type: string
        }
        Update: {
          attempts?: number
          available_at?: string
          created_at?: string
          event_type?: string
          id?: string
          idempotency_key?: string
          last_error?: string | null
          processed_at?: string | null
          recipient_user_id?: string
          safe_payload?: Json
          status?: Database["public"]["Enums"]["txn_outbox_status"]
          transaction_id?: string
          transaction_type?: string
        }
        Relationships: []
      }
      transactions: {
        Row: {
          amount: number
          created_at: string
          currency: string
          id: string
          metadata: Json
          provider: string | null
          provider_ref: string | null
          status: string
          type: string
          updated_at: string
          user_id: string | null
        }
        Insert: {
          amount: number
          created_at?: string
          currency?: string
          id?: string
          metadata?: Json
          provider?: string | null
          provider_ref?: string | null
          status?: string
          type: string
          updated_at?: string
          user_id?: string | null
        }
        Update: {
          amount?: number
          created_at?: string
          currency?: string
          id?: string
          metadata?: Json
          provider?: string | null
          provider_ref?: string | null
          status?: string
          type?: string
          updated_at?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "transactions_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      user_devices: {
        Row: {
          app_version: string | null
          created_at: string
          device_id: string
          id: string
          last_seen_at: string | null
          os_version: string | null
          platform: string | null
          push_token: string | null
          user_id: string
        }
        Insert: {
          app_version?: string | null
          created_at?: string
          device_id: string
          id?: string
          last_seen_at?: string | null
          os_version?: string | null
          platform?: string | null
          push_token?: string | null
          user_id: string
        }
        Update: {
          app_version?: string | null
          created_at?: string
          device_id?: string
          id?: string
          last_seen_at?: string | null
          os_version?: string | null
          platform?: string | null
          push_token?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_devices_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      user_edit_history: {
        Row: {
          actor_id: string | null
          created_at: string
          field: string
          id: string
          new_value: Json | null
          old_value: Json | null
          reason: string | null
          user_id: string
        }
        Insert: {
          actor_id?: string | null
          created_at?: string
          field: string
          id?: string
          new_value?: Json | null
          old_value?: Json | null
          reason?: string | null
          user_id: string
        }
        Update: {
          actor_id?: string | null
          created_at?: string
          field?: string
          id?: string
          new_value?: Json | null
          old_value?: Json | null
          reason?: string | null
          user_id?: string
        }
        Relationships: []
      }
      user_penalties: {
        Row: {
          active: boolean
          created_at: string
          duration_h: number | null
          ends_at: string | null
          id: string
          issued_by: string | null
          metadata: Json
          reason: string
          starts_at: string
          type: string
          user_id: string
        }
        Insert: {
          active?: boolean
          created_at?: string
          duration_h?: number | null
          ends_at?: string | null
          id?: string
          issued_by?: string | null
          metadata?: Json
          reason: string
          starts_at?: string
          type: string
          user_id: string
        }
        Update: {
          active?: boolean
          created_at?: string
          duration_h?: number | null
          ends_at?: string | null
          id?: string
          issued_by?: string | null
          metadata?: Json
          reason?: string
          starts_at?: string
          type?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_penalties_issued_by_fkey"
            columns: ["issued_by"]
            isOneToOne: false
            referencedRelation: "admin_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_penalties_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      user_sessions: {
        Row: {
          country: string | null
          device_id: string | null
          ended_at: string | null
          id: string
          ip_address: string | null
          started_at: string
          user_id: string
        }
        Insert: {
          country?: string | null
          device_id?: string | null
          ended_at?: string | null
          id?: string
          ip_address?: string | null
          started_at?: string
          user_id: string
        }
        Update: {
          country?: string | null
          device_id?: string | null
          ended_at?: string | null
          id?: string
          ip_address?: string | null
          started_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_sessions_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      wallet_adjustment_requests: {
        Row: {
          amount: number
          applied_at: string | null
          balance_after: number | null
          balance_before: number | null
          created_at: string
          created_by: string
          id: string
          idempotency_key: string | null
          kind: Database["public"]["Enums"]["wallet_adjustment_kind"]
          reason: string
          reference: string
          requires_dual_review: boolean
          reversed_at: string | null
          status: Database["public"]["Enums"]["wallet_adjustment_status"]
          target_user_id: string
        }
        Insert: {
          amount: number
          applied_at?: string | null
          balance_after?: number | null
          balance_before?: number | null
          created_at?: string
          created_by: string
          id?: string
          idempotency_key?: string | null
          kind: Database["public"]["Enums"]["wallet_adjustment_kind"]
          reason: string
          reference?: string
          requires_dual_review?: boolean
          reversed_at?: string | null
          status?: Database["public"]["Enums"]["wallet_adjustment_status"]
          target_user_id: string
        }
        Update: {
          amount?: number
          applied_at?: string | null
          balance_after?: number | null
          balance_before?: number | null
          created_at?: string
          created_by?: string
          id?: string
          idempotency_key?: string | null
          kind?: Database["public"]["Enums"]["wallet_adjustment_kind"]
          reason?: string
          reference?: string
          requires_dual_review?: boolean
          reversed_at?: string | null
          status?: Database["public"]["Enums"]["wallet_adjustment_status"]
          target_user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "wallet_adjustment_requests_target_user_id_fkey"
            columns: ["target_user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      wallet_adjustment_reviews: {
        Row: {
          decision: string
          id: string
          note: string | null
          request_id: string
          reviewed_at: string
          reviewer_id: string
        }
        Insert: {
          decision: string
          id?: string
          note?: string | null
          request_id: string
          reviewed_at?: string
          reviewer_id: string
        }
        Update: {
          decision?: string
          id?: string
          note?: string | null
          request_id?: string
          reviewed_at?: string
          reviewer_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "wallet_adjustment_reviews_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "wallet_adjustment_requests"
            referencedColumns: ["id"]
          },
        ]
      }
      wallet_ledger: {
        Row: {
          account: Database["public"]["Enums"]["wallet_account"]
          amount: number
          balance_after: number
          created_at: string
          created_by: string | null
          direction: Database["public"]["Enums"]["ledger_direction"]
          id: number
          ledger_side: string | null
          metadata: Json
          reason: Database["public"]["Enums"]["ledger_reason"]
          recharge_request_id: string | null
          reference: string | null
          refund_id: string | null
          transaction_group_id: string | null
          user_id: string
          wallet_id: string
        }
        Insert: {
          account: Database["public"]["Enums"]["wallet_account"]
          amount: number
          balance_after: number
          created_at?: string
          created_by?: string | null
          direction: Database["public"]["Enums"]["ledger_direction"]
          id?: number
          ledger_side?: string | null
          metadata?: Json
          reason: Database["public"]["Enums"]["ledger_reason"]
          recharge_request_id?: string | null
          reference?: string | null
          refund_id?: string | null
          transaction_group_id?: string | null
          user_id: string
          wallet_id: string
        }
        Update: {
          account?: Database["public"]["Enums"]["wallet_account"]
          amount?: number
          balance_after?: number
          created_at?: string
          created_by?: string | null
          direction?: Database["public"]["Enums"]["ledger_direction"]
          id?: number
          ledger_side?: string | null
          metadata?: Json
          reason?: Database["public"]["Enums"]["ledger_reason"]
          recharge_request_id?: string | null
          reference?: string | null
          refund_id?: string | null
          transaction_group_id?: string | null
          user_id?: string
          wallet_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "wallet_ledger_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "admin_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "wallet_ledger_recharge_request_id_fkey"
            columns: ["recharge_request_id"]
            isOneToOne: false
            referencedRelation: "recharge_requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "wallet_ledger_refund_id_fkey"
            columns: ["refund_id"]
            isOneToOne: false
            referencedRelation: "recharge_refunds"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "wallet_ledger_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "wallet_ledger_wallet_id_fkey"
            columns: ["wallet_id"]
            isOneToOne: false
            referencedRelation: "wallets"
            referencedColumns: ["id"]
          },
        ]
      }
      wallets: {
        Row: {
          account: Database["public"]["Enums"]["wallet_account"]
          balance: number
          id: string
          reserved: number
          updated_at: string
          user_id: string
        }
        Insert: {
          account: Database["public"]["Enums"]["wallet_account"]
          balance?: number
          id?: string
          reserved?: number
          updated_at?: string
          user_id: string
        }
        Update: {
          account?: Database["public"]["Enums"]["wallet_account"]
          balance?: number
          id?: string
          reserved?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "wallets_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      withdrawal_events: {
        Row: {
          actor_id: string | null
          created_at: string
          from_status: Database["public"]["Enums"]["withdrawal_status"] | null
          id: string
          metadata: Json
          note: string | null
          request_id: string
          to_status: Database["public"]["Enums"]["withdrawal_status"]
        }
        Insert: {
          actor_id?: string | null
          created_at?: string
          from_status?: Database["public"]["Enums"]["withdrawal_status"] | null
          id?: string
          metadata?: Json
          note?: string | null
          request_id: string
          to_status: Database["public"]["Enums"]["withdrawal_status"]
        }
        Update: {
          actor_id?: string | null
          created_at?: string
          from_status?: Database["public"]["Enums"]["withdrawal_status"] | null
          id?: string
          metadata?: Json
          note?: string | null
          request_id?: string
          to_status?: Database["public"]["Enums"]["withdrawal_status"]
        }
        Relationships: [
          {
            foreignKeyName: "withdrawal_events_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "withdrawal_requests"
            referencedColumns: ["id"]
          },
        ]
      }
      withdrawal_fees: {
        Row: {
          country_code: string | null
          created_at: string
          currency_code: string
          fixed_fee: number
          id: string
          is_active: boolean
          max_pearls: number | null
          method_id: string | null
          min_pearls: number
          percentage_fee: number
          updated_at: string
        }
        Insert: {
          country_code?: string | null
          created_at?: string
          currency_code: string
          fixed_fee?: number
          id?: string
          is_active?: boolean
          max_pearls?: number | null
          method_id?: string | null
          min_pearls?: number
          percentage_fee?: number
          updated_at?: string
        }
        Update: {
          country_code?: string | null
          created_at?: string
          currency_code?: string
          fixed_fee?: number
          id?: string
          is_active?: boolean
          max_pearls?: number | null
          method_id?: string | null
          min_pearls?: number
          percentage_fee?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "withdrawal_fees_method_id_fkey"
            columns: ["method_id"]
            isOneToOne: false
            referencedRelation: "withdrawal_methods"
            referencedColumns: ["id"]
          },
        ]
      }
      withdrawal_limits: {
        Row: {
          code: string
          country_code: string | null
          created_at: string
          currency_code: string
          daily_max_pearls: number | null
          dual_review_threshold: number | null
          id: string
          is_active: boolean
          max_pearls_per_request: number | null
          method_id: string | null
          min_pearls: number
          min_user_level: number | null
          monthly_max_pearls: number | null
          updated_at: string
          weekly_max_pearls: number | null
        }
        Insert: {
          code: string
          country_code?: string | null
          created_at?: string
          currency_code: string
          daily_max_pearls?: number | null
          dual_review_threshold?: number | null
          id?: string
          is_active?: boolean
          max_pearls_per_request?: number | null
          method_id?: string | null
          min_pearls?: number
          min_user_level?: number | null
          monthly_max_pearls?: number | null
          updated_at?: string
          weekly_max_pearls?: number | null
        }
        Update: {
          code?: string
          country_code?: string | null
          created_at?: string
          currency_code?: string
          daily_max_pearls?: number | null
          dual_review_threshold?: number | null
          id?: string
          is_active?: boolean
          max_pearls_per_request?: number | null
          method_id?: string | null
          min_pearls?: number
          min_user_level?: number | null
          monthly_max_pearls?: number | null
          updated_at?: string
          weekly_max_pearls?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "withdrawal_limits_method_id_fkey"
            columns: ["method_id"]
            isOneToOne: false
            referencedRelation: "withdrawal_methods"
            referencedColumns: ["id"]
          },
        ]
      }
      withdrawal_methods: {
        Row: {
          code: string
          country_code: string | null
          created_at: string
          currency_code: string
          id: string
          instructions: string | null
          is_active: boolean
          metadata: Json
          name: string
          payment_gateway_id: string | null
          requires_manual_review: boolean
          updated_at: string
        }
        Insert: {
          code: string
          country_code?: string | null
          created_at?: string
          currency_code: string
          id?: string
          instructions?: string | null
          is_active?: boolean
          metadata?: Json
          name: string
          payment_gateway_id?: string | null
          requires_manual_review?: boolean
          updated_at?: string
        }
        Update: {
          code?: string
          country_code?: string | null
          created_at?: string
          currency_code?: string
          id?: string
          instructions?: string | null
          is_active?: boolean
          metadata?: Json
          name?: string
          payment_gateway_id?: string | null
          requires_manual_review?: boolean
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "withdrawal_methods_payment_gateway_id_fkey"
            columns: ["payment_gateway_id"]
            isOneToOne: false
            referencedRelation: "payment_gateway_stats"
            referencedColumns: ["gateway_id"]
          },
          {
            foreignKeyName: "withdrawal_methods_payment_gateway_id_fkey"
            columns: ["payment_gateway_id"]
            isOneToOne: false
            referencedRelation: "payment_gateways"
            referencedColumns: ["id"]
          },
        ]
      }
      withdrawal_requests: {
        Row: {
          account_data: Json
          admin_notes: string | null
          approval_count: number
          approved_at: string | null
          confirmed_at: string | null
          country_code: string | null
          created_at: string
          currency_code: string
          external_reference: string | null
          fee_amount: number
          id: string
          metadata: Json
          method_id: string | null
          net_amount: number
          paid_at: string | null
          pearls_amount: number
          price_rule_id: string | null
          price_version: number | null
          proof_url: string | null
          rejected_at: string | null
          rejection_reason: string | null
          required_approvals: number
          requires_dual_review: boolean
          reviewed_at: string | null
          status: Database["public"]["Enums"]["withdrawal_status"]
          updated_at: string
          user_id: string
        }
        Insert: {
          account_data?: Json
          admin_notes?: string | null
          approval_count?: number
          approved_at?: string | null
          confirmed_at?: string | null
          country_code?: string | null
          created_at?: string
          currency_code: string
          external_reference?: string | null
          fee_amount?: number
          id?: string
          metadata?: Json
          method_id?: string | null
          net_amount: number
          paid_at?: string | null
          pearls_amount: number
          price_rule_id?: string | null
          price_version?: number | null
          proof_url?: string | null
          rejected_at?: string | null
          rejection_reason?: string | null
          required_approvals?: number
          requires_dual_review?: boolean
          reviewed_at?: string | null
          status?: Database["public"]["Enums"]["withdrawal_status"]
          updated_at?: string
          user_id: string
        }
        Update: {
          account_data?: Json
          admin_notes?: string | null
          approval_count?: number
          approved_at?: string | null
          confirmed_at?: string | null
          country_code?: string | null
          created_at?: string
          currency_code?: string
          external_reference?: string | null
          fee_amount?: number
          id?: string
          metadata?: Json
          method_id?: string | null
          net_amount?: number
          paid_at?: string | null
          pearls_amount?: number
          price_rule_id?: string | null
          price_version?: number | null
          proof_url?: string | null
          rejected_at?: string | null
          rejection_reason?: string | null
          required_approvals?: number
          requires_dual_review?: boolean
          reviewed_at?: string | null
          status?: Database["public"]["Enums"]["withdrawal_status"]
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "withdrawal_requests_method_id_fkey"
            columns: ["method_id"]
            isOneToOne: false
            referencedRelation: "withdrawal_methods"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "withdrawal_requests_price_rule_id_fkey"
            columns: ["price_rule_id"]
            isOneToOne: false
            referencedRelation: "pearl_price_rules"
            referencedColumns: ["id"]
          },
        ]
      }
      withdrawal_reviews: {
        Row: {
          created_at: string
          decision: string
          id: string
          note: string | null
          request_id: string
          reviewer_id: string
        }
        Insert: {
          created_at?: string
          decision: string
          id?: string
          note?: string | null
          request_id: string
          reviewer_id: string
        }
        Update: {
          created_at?: string
          decision?: string
          id?: string
          note?: string | null
          request_id?: string
          reviewer_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "withdrawal_reviews_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "withdrawal_requests"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      payment_gateway_stats: {
        Row: {
          failure_count: number | null
          gateway_id: string | null
          last_webhook_at: string | null
          success_count: number | null
          total_failures: number | null
        }
        Insert: {
          failure_count?: never
          gateway_id?: string | null
          last_webhook_at?: never
          success_count?: never
          total_failures?: never
        }
        Update: {
          failure_count?: never
          gateway_id?: string | null
          last_webhook_at?: never
          success_count?: never
          total_failures?: never
        }
        Relationships: []
      }
    }
    Functions: {
      _admin_wallet_adjust: {
        Args: {
          _amount: number
          _idempotency_key: string
          _kind: Database["public"]["Enums"]["wallet_adjustment_kind"]
          _reason: string
          _target_user_id: string
        }
        Returns: {
          adjustment_id: string
          reference: string
        }[]
      }
      _apply_recharge_refund_wallet_reversal: {
        Args: { _execution_reference: string; _refund_id: string }
        Returns: Json
      }
      _assert_reason: { Args: { _reason: string }; Returns: undefined }
      _charge_audit: {
        Args: {
          _action: string
          _entity_id: string
          _entity_type: string
          _meta: Json
        }
        Returns: undefined
      }
      _complete_recharge_request_internal: {
        Args: {
          _actor: string
          _external_ref: string
          _request_id: string
          _source: string
        }
        Returns: string
      }
      _dispute_assert_actor: { Args: { _perm: string }; Returns: string }
      _dispute_assert_transition: {
        Args: {
          _current: Database["public"]["Enums"]["recharge_dispute_status_enum"]
          _next: Database["public"]["Enums"]["recharge_dispute_status_enum"]
        }
        Returns: undefined
      }
      _dispute_idem_finalize: {
        Args: { _action: string; _actor: string; _key: string; _result: Json }
        Returns: undefined
      }
      _dispute_idem_lookup: {
        Args: {
          _action: string
          _actor: string
          _decision_version?: number
          _dispute?: string
          _input_hash: string
          _key: string
          _source_cycle?: string
        }
        Returns: Json
      }
      _dispute_lock: {
        Args: { _dispute_id: string }
        Returns: {
          already_refunded_amount: number | null
          amount: number | null
          approved_resolution_amount: number | null
          assigned_team: string | null
          assigned_to: string | null
          bonus_already_reversed: number | null
          cancelled_at: string | null
          cancelled_by: string | null
          chargeback_amount: number | null
          chargeback_currency: string | null
          claimed_amount: number | null
          closed_at: string | null
          closed_by: string | null
          coins_already_reversed: number | null
          created_at: string
          currency: string | null
          currency_code: string | null
          current_available_bonus: number | null
          current_available_coins: number | null
          current_exposure_checked_at: string | null
          current_exposure_snapshot: Json | null
          decision_type: string | null
          description: string | null
          dispute_policy_id: string | null
          dispute_policy_version: number | null
          dispute_reference: string
          dispute_source: Database["public"]["Enums"]["recharge_dispute_source_enum"]
          dispute_type: Database["public"]["Enums"]["recharge_dispute_type_enum"]
          due_at: string | null
          evidence: Json
          evidence_deadline: string | null
          evidence_due_at: string | null
          failure_code: string | null
          financial_exposure_amount: number | null
          financial_resolution_status: Database["public"]["Enums"]["financial_resolution_status_enum"]
          first_decision_at: string | null
          first_decision_by: string | null
          gateway_id: string | null
          gateway_mode: string | null
          id: string
          idempotency_key: string | null
          last_action_idempotency_key: string | null
          legacy_status_original: string | null
          metadata: Json
          metadata_safe: Json
          opened_at: string | null
          opened_by: string | null
          original_base_coins: number | null
          original_bonus_coins: number | null
          original_paid_amount: number | null
          original_payment_reference: string | null
          parent_dispute_id: string | null
          payment_method_id: string | null
          policy_snapshot: Json | null
          priority: Database["public"]["Enums"]["recharge_dispute_priority_enum"]
          provider_case_reference: string | null
          provider_chargeback_id: string | null
          provider_decision: string | null
          provider_decision_at: string | null
          provider_dispute_id: string | null
          provider_event_id: string | null
          provider_mode: string | null
          provider_opened_at: string | null
          provider_payment_id: string | null
          provider_reason_category: string | null
          provider_reason_code: string | null
          provider_status: string | null
          provider_updated_at: string | null
          provisional_action: Database["public"]["Enums"]["recharge_dispute_provisional_action_enum"]
          provisional_expires_at: string | null
          reason: string
          reason_code: string | null
          recommended_resolution_amount: number | null
          recoverable_coin_amount: number | null
          refund_id: string | null
          rejected_at: string | null
          rejected_by: string | null
          reopen_reason: string | null
          reopen_sequence: number
          reopened_from_status:
            | Database["public"]["Enums"]["recharge_dispute_status_enum"]
            | null
          request_id: string
          requested_by: string | null
          requires_second_decision: boolean
          resolution: string | null
          resolution_code: string | null
          resolution_reason: string | null
          resolution_version: number
          resolved_at: string | null
          resolved_by: string | null
          response_due_at: string | null
          root_dispute_id: string | null
          safe_internal_summary: string | null
          second_decision_at: string | null
          second_decision_by: string | null
          severity: Database["public"]["Enums"]["recharge_dispute_severity_enum"]
          sla_policy_id: string | null
          status: Database["public"]["Enums"]["recharge_dispute_status_enum"]
          summary: string | null
          threshold_snapshot: Json | null
          title: string | null
          triaged_at: string | null
          triaged_by: string | null
          unrecovered_coin_amount: number | null
          updated_at: string
          user_claim: string | null
          user_id: string | null
        }
        SetofOptions: {
          from: "*"
          to: "recharge_disputes"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      _dispute_snapshot_exposure: {
        Args: { _dispute: string; _request: string }
        Returns: Json
      }
      _dispute_transition_ok: {
        Args: {
          _from: Database["public"]["Enums"]["recharge_dispute_status_enum"]
          _to: Database["public"]["Enums"]["recharge_dispute_status_enum"]
        }
        Returns: boolean
      }
      _dispute_write_audit: {
        Args: {
          _action: string
          _actor: string
          _dispute: string
          _meta: Json
          _new_status: string
          _old_status: string
          _reason: string
        }
        Returns: undefined
      }
      _dispute_write_outbox: {
        Args: {
          _dispute: string
          _event: string
          _key: string
          _payload: Json
          _recipient: string
        }
        Returns: undefined
      }
      _enqueue_txn_message: {
        Args: {
          _event_type: string
          _idem: string
          _recipient: string
          _safe_payload: Json
          _txn_id: string
          _txn_type: string
        }
        Returns: undefined
      }
      _lookup_refund_policy: {
        Args: { _country: string; _currency: string; _gateway_id: string }
        Returns: {
          allow_money_only_refund: boolean
          allow_partial_refund: boolean
          country_code: string | null
          created_at: string
          created_by: string | null
          currency_code: string | null
          decimal_scale: number
          ends_at: string | null
          gateway_id: string | null
          id: string
          insufficient_balance_policy: string
          name: string
          partial_bonus_policy: string
          refund_type_scope: string[]
          refund_window_days: number
          require_wallet_reversal_before_gateway_refund: boolean
          rounding_mode: string
          second_approval_threshold: number
          single_approval_threshold: number
          starts_at: string
          status: string
          updated_at: string
          version: number
        }
        SetofOptions: {
          from: "*"
          to: "refund_policies"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      _lookup_refund_retry_policy: {
        Args: {
          _gateway_id: string
          _gateway_mode: Database["public"]["Enums"]["payment_gateway_mode"]
        }
        Returns: {
          active: boolean
          backoff_multiplier: number
          created_at: string
          created_by: string | null
          gateway_id: string | null
          gateway_mode:
            | Database["public"]["Enums"]["payment_gateway_mode"]
            | null
          id: string
          initial_backoff_seconds: number
          jitter_percent: number
          max_backoff_seconds: number
          max_create_attempts: number
          max_status_refresh_attempts: number
          move_to_manual_review_after: number
          polling_interval_seconds: number
          stale_processing_timeout_minutes: number
          unknown_result_timeout_minutes: number
          updated_at: string
          version: number
        }
        SetofOptions: {
          from: "*"
          to: "refund_retry_policies"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      _recharge_transition_ok: {
        Args: {
          _from: Database["public"]["Enums"]["recharge_request_status"]
          _to: Database["public"]["Enums"]["recharge_request_status"]
        }
        Returns: boolean
      }
      _refund_preflight_calc: {
        Args: {
          _bonus_policy_override?: string
          _recharge_request_id: string
          _refund_scope: string
          _refund_type: string
          _requested_amount: number
        }
        Returns: Json
      }
      _refund_transition_ok: {
        Args: {
          p_from: Database["public"]["Enums"]["refund_status"]
          p_to: Database["public"]["Enums"]["refund_status"]
        }
        Returns: boolean
      }
      _require_perm: { Args: { _perm: string }; Returns: undefined }
      _resolve_pearl_rule: {
        Args: {
          _amount: number
          _country: string
          _currency: string
          _kind: Database["public"]["Enums"]["pearl_price_kind"]
          _user_id: string
        }
        Returns: {
          agency_commission_pct: number
          agency_id: string | null
          agent_commission_pct: number
          base_unit_price: number
          code: string
          country_code: string | null
          created_at: string
          created_by: string | null
          currency_code: string
          ends_at: string | null
          id: string
          kind: Database["public"]["Enums"]["pearl_price_kind"]
          max_agent_level: number | null
          max_amount: number | null
          max_user_level: number | null
          max_vip: number | null
          min_agent_level: number | null
          min_amount: number
          min_user_level: number | null
          min_vip: number | null
          name: string
          platform_commission_pct: number
          priority: number
          starts_at: string | null
          status: Database["public"]["Enums"]["pearl_price_status"]
          updated_at: string
          updated_by: string | null
          version: number
          withdrawal_fee_fixed: number
          withdrawal_fee_pct: number
        }
        SetofOptions: {
          from: "*"
          to: "pearl_price_rules"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      _transfer_approve: {
        Args: {
          _decision: string
          _note: string
          _stage: string
          _transfer_id: string
        }
        Returns: undefined
      }
      _wallet_apply: {
        Args: {
          _account: Database["public"]["Enums"]["wallet_account"]
          _delta: number
          _metadata: Json
          _reason: Database["public"]["Enums"]["ledger_reason"]
          _reference: string
          _user_id: string
        }
        Returns: number
      }
      accept_admin_invite: { Args: { _token: string }; Returns: undefined }
      acknowledge_chargeback: {
        Args: { _dispute_id: string; _idempotency_key: string; _reason: string }
        Returns: undefined
      }
      activate_charging_agent: {
        Args: {
          _agency_id: string
          _daily_coin_limit: number
          _daily_pearl_limit: number
          _monthly_coin_limit: number
          _monthly_pearl_limit: number
          _role: Database["public"]["Enums"]["charging_agent_role"]
          _user_id: string
        }
        Returns: undefined
      }
      activate_payment_method: {
        Args: { _id: string; _reason: string }
        Returns: undefined
      }
      add_dispute_internal_note: {
        Args: {
          _body: string
          _dispute_id: string
          _idempotency_key: string
          _reason: string
          _visibility: string
        }
        Returns: string
      }
      add_dispute_user_visible_note: {
        Args: {
          _body: string
          _dispute_id: string
          _idempotency_key: string
          _reason: string
        }
        Returns: string
      }
      add_host_to_agency: {
        Args: { _agency_id: string; _user_id: string }
        Returns: string
      }
      admin_ban_user: {
        Args: { _reason: string; _until?: string; _user_id: string }
        Returns: undefined
      }
      admin_create_invite: {
        Args: {
          _days?: number
          _email: string
          _role: Database["public"]["Enums"]["admin_role"]
        }
        Returns: {
          invite_id: string
          raw_token: string
        }[]
      }
      admin_credit_user_coins: {
        Args: {
          _amount: number
          _idempotency_key: string
          _reason: string
          _target_user_id: string
        }
        Returns: {
          adjustment_id: string
          reference: string
        }[]
      }
      admin_credit_user_pearls: {
        Args: {
          _amount: number
          _idempotency_key: string
          _reason: string
          _target_user_id: string
        }
        Returns: {
          adjustment_id: string
          reference: string
        }[]
      }
      admin_debit_user_coins: {
        Args: {
          _amount: number
          _idempotency_key: string
          _reason: string
          _target_user_id: string
        }
        Returns: {
          adjustment_id: string
          reference: string
        }[]
      }
      admin_debit_user_pearls: {
        Args: {
          _amount: number
          _idempotency_key: string
          _reason: string
          _target_user_id: string
        }
        Returns: {
          adjustment_id: string
          reference: string
        }[]
      }
      admin_restore_user: {
        Args: { _reason: string; _user_id: string }
        Returns: undefined
      }
      admin_revoke_invite: { Args: { _invite_id: string }; Returns: undefined }
      admin_soft_delete_user: {
        Args: { _reason: string; _user_id: string }
        Returns: undefined
      }
      admin_terminate_sessions: {
        Args: { _reason: string; _user_id: string }
        Returns: number
      }
      admin_toggle_comm_ban: {
        Args: {
          _banned: boolean
          _channel: string
          _reason: string
          _user_id: string
        }
        Returns: undefined
      }
      admin_unban_user: {
        Args: { _reason: string; _user_id: string }
        Returns: undefined
      }
      admin_update_gender: {
        Args: { _gender: string; _reason: string; _user_id: string }
        Returns: undefined
      }
      admin_update_level: {
        Args: { _level: number; _reason: string; _user_id: string }
        Returns: undefined
      }
      admin_update_profile: {
        Args: {
          _avatar_url: string
          _bio: string
          _country: string
          _cover_url: string
          _display_name: string
          _language: string
          _user_id: string
          _username: string
        }
        Returns: undefined
      }
      admin_update_vip: {
        Args: { _reason: string; _user_id: string; _vip: number }
        Returns: undefined
      }
      admin_verify_user: {
        Args: { _reason?: string; _user_id: string; _verified: boolean }
        Returns: undefined
      }
      apply_refund_webhook_event: {
        Args: { _attempt_id: string; _webhook_id: string }
        Returns: Json
      }
      approve_agency_join_request: {
        Args: { _note: string; _req_id: string }
        Returns: undefined
      }
      approve_host_transfer_admin: {
        Args: { _decision: string; _note: string; _transfer_id: string }
        Returns: undefined
      }
      approve_host_transfer_bd: {
        Args: { _decision: string; _note: string; _transfer_id: string }
        Returns: undefined
      }
      approve_host_transfer_source: {
        Args: { _decision: string; _note: string; _transfer_id: string }
        Returns: undefined
      }
      approve_host_transfer_target: {
        Args: { _decision: string; _note: string; _transfer_id: string }
        Returns: undefined
      }
      approve_recharge_refund: {
        Args: { _reason: string; _refund_id: string }
        Returns: undefined
      }
      archive_coin_price_rule: {
        Args: { _id: string; _reason: string }
        Returns: undefined
      }
      archive_payment_method: {
        Args: { _id: string; _reason: string }
        Returns: undefined
      }
      archive_recharge_package: {
        Args: { _id: string; _reason: string }
        Returns: undefined
      }
      assert_mock_refund_allowed: {
        Args: { _gateway_id: string }
        Returns: undefined
      }
      assert_no_overlapping_recharge_dispute_policies: {
        Args: never
        Returns: {
          a_id: string
          b_id: string
          reason: string
        }[]
      }
      assert_no_overlapping_refund_policies: {
        Args: never
        Returns: {
          violation: string
        }[]
      }
      assert_no_overlapping_refund_retry_policies: {
        Args: never
        Returns: {
          violation: string
        }[]
      }
      assert_no_public_security_definer: {
        Args: never
        Returns: {
          exposure: string
          function_args: string
          function_name: string
        }[]
      }
      assert_refund_completed_has_ledger: {
        Args: never
        Returns: {
          missing: string
          refund_id: string
          refund_reference: string
          status: string
        }[]
      }
      assert_refund_ledger_pairing: {
        Args: never
        Returns: {
          details: string
          issue: string
          refund_id: string
          transaction_group_id: string
        }[]
      }
      assign_agency_bd: {
        Args: { _agency_id: string; _bd_id: string }
        Returns: undefined
      }
      assign_agency_deputy: {
        Args: { _agency_id: string; _user_id: string }
        Returns: undefined
      }
      assign_agency_owner: {
        Args: { _agency_id: string; _user_id: string }
        Returns: undefined
      }
      assign_agent_to_charging_agency: {
        Args: {
          _agency_id: string
          _role: Database["public"]["Enums"]["charging_agent_role"]
          _user_id: string
        }
        Returns: undefined
      }
      assign_recharge_dispute: {
        Args: {
          _assigned_team: string
          _assigned_to: string
          _dispute_id: string
          _idempotency_key: string
          _reason: string
        }
        Returns: undefined
      }
      audit_authenticated_security_definer: {
        Args: never
        Returns: {
          category: string
          function_signature: string
          guard_kind: string
          has_guard: boolean
          verdict: string
        }[]
      }
      calculate_recharge_dispute_sla: {
        Args: { _dispute_id: string }
        Returns: {
          chargeback_due_at: string
          evidence_due_at: string
          first_response_due_at: string
          is_chargeback_overdue: boolean
          is_first_response_overdue: boolean
          is_resolution_overdue: boolean
          policy_id: string
          resolution_due_at: string
        }[]
      }
      cancel_host_transfer: {
        Args: { _reason: string; _transfer_id: string }
        Returns: undefined
      }
      cancel_recharge_dispute: {
        Args: { _dispute_id: string; _idempotency_key: string; _reason: string }
        Returns: undefined
      }
      cancel_recharge_refund: {
        Args: { _reason: string; _refund_id: string }
        Returns: undefined
      }
      cancel_recharge_request: {
        Args: { _reason: string; _request_id: string }
        Returns: undefined
      }
      cancel_withdrawal: {
        Args: { _reason: string; _request_id: string }
        Returns: undefined
      }
      change_payment_gateway_mode: {
        Args: {
          _id: string
          _new_mode: Database["public"]["Enums"]["payment_gateway_mode"]
          _reason: string
        }
        Returns: undefined
      }
      charging_agent_transfer_coins: {
        Args: {
          _amount: number
          _currency: string
          _idempotency_key: string
          _note: string
          _payment_reference: string
          _receipt_url: string
          _recipient_user_id: string
          _sale_price: number
        }
        Returns: {
          reference: string
          transfer_id: string
        }[]
      }
      charging_agent_transfer_pearls: {
        Args: {
          _amount: number
          _idempotency_key: string
          _note: string
          _recipient_user_id: string
        }
        Returns: {
          reference: string
          transfer_id: string
        }[]
      }
      claim_refund_status_refresh: {
        Args: { _lease_seconds?: number; _owner: string; _refund_id: string }
        Returns: Json
      }
      claim_refund_webhook_for_processing: {
        Args: { _owner: string; _stale_after?: string; _webhook_id: string }
        Returns: Json
      }
      close_agency: {
        Args: { _agency_id: string; _reason: string }
        Returns: undefined
      }
      close_charging_agency: {
        Args: { _agency_id: string; _reason: string }
        Returns: undefined
      }
      close_recharge_dispute: {
        Args: { _dispute_id: string; _idempotency_key: string; _reason: string }
        Returns: undefined
      }
      complete_recharge_request: {
        Args: { _external_ref: string; _request_id: string }
        Returns: string
      }
      confirm_withdrawal: { Args: { _request_id: string }; Returns: undefined }
      create_agency: {
        Args: {
          _bd_id: string
          _code: string
          _country: string
          _language: string
          _level_id: number
          _name: string
          _owner_user_id: string
        }
        Returns: string
      }
      create_agency_join_request: {
        Args: { _agency_id: string; _message: string; _user_id: string }
        Returns: string
      }
      create_bd_manager: {
        Args: {
          _admin_user_id: string
          _code: string
          _country: string
          _display_name: string
          _email: string
          _level: number
          _phone: string
        }
        Returns: string
      }
      create_charging_agency: {
        Args: {
          _city: string
          _country: string
          _default_currency: string
          _deputy_user_id: string
          _email: string
          _name: string
          _owner_user_id: string
          _phone: string
        }
        Returns: string
      }
      create_coin_price_rule: { Args: { _payload: Json }; Returns: string }
      create_host_transfer_request: {
        Args: {
          _host_user_id: string
          _idempotency_key: string
          _reason: string
          _to_agency_id: string
        }
        Returns: string
      }
      create_payment_gateway: {
        Args: {
          _callback_url?: string
          _code: string
          _countries?: string[]
          _currencies?: string[]
          _fixed_fee?: number
          _logo_url?: string
          _max_amount?: number
          _min_amount?: number
          _mode?: Database["public"]["Enums"]["payment_gateway_mode"]
          _name: string
          _percentage_fee?: number
          _priority?: number
          _provider: string
          _webhook_url?: string
        }
        Returns: string
      }
      create_payment_method: {
        Args: {
          _code: string
          _country_code: string
          _currency_code: string
          _fixed_fee: number
          _for_agents: boolean
          _for_recharge: boolean
          _for_users: boolean
          _for_withdrawal: boolean
          _gateway_id: string
          _instructions_ar: string
          _instructions_en: string
          _logo_url: string
          _max_amount: number
          _method_type: Database["public"]["Enums"]["payment_method_type"]
          _min_amount: number
          _name_ar: string
          _name_en: string
          _percentage_fee: number
          _qr_url: string
          _sort_order: number
        }
        Returns: string
      }
      create_payment_method_account: {
        Args: {
          _account_number_masked: string
          _account_number_secret_ref: string
          _bank_name: string
          _beneficiary_name_masked: string
          _beneficiary_name_secret_ref: string
          _extra_data: Json
          _iban_masked: string
          _iban_secret_ref: string
          _label: string
          _method_id: string
          _swift_code: string
        }
        Returns: string
      }
      create_pearl_exchange_rate: {
        Args: {
          _agency_id: string
          _coins_per_pearl: number
          _country: string
          _daily_limit: number
          _fee_percentage: number
          _max_exchange: number
          _min_exchange: number
          _monthly_limit: number
          _status: string
        }
        Returns: string
      }
      create_recharge_dispute: {
        Args: {
          _dispute_type: Database["public"]["Enums"]["recharge_dispute_type_enum"]
          _idempotency_key: string
          _reason: string
          _recharge_request_id: string
          _source: Database["public"]["Enums"]["recharge_dispute_source_enum"]
          _summary: string
          _title: string
          _user_claim: string
        }
        Returns: string
      }
      create_recharge_package: {
        Args: {
          _base_coins: number
          _bonus_coins: number
          _code: string
          _name_ar: string
          _name_en: string
        }
        Returns: string
      }
      create_recharge_receipt_upload: {
        Args: { _mime: string; _request_id: string; _size_bytes: number }
        Returns: {
          receipt_id: string
          storage_bucket: string
          storage_object_path: string
        }[]
      }
      create_recharge_request: {
        Args: {
          _bonus: number
          _coin_amount: number
          _country: string
          _currency: string
          _gateway_id: string
          _idempotency_key: string
          _method_id: string
          _package_id: string
          _price: number
        }
        Returns: string
      }
      deactivate_charging_agent: {
        Args: { _reason: string; _user_id: string }
        Returns: undefined
      }
      disable_payment_gateway: {
        Args: { _id: string; _reason: string }
        Returns: undefined
      }
      disable_payment_method: {
        Args: { _id: string; _reason: string }
        Returns: undefined
      }
      duplicate_recharge_package: { Args: { _id: string }; Returns: string }
      emergency_grant_super_admin: {
        Args: { _user_id: string }
        Returns: undefined
      }
      enable_payment_gateway: {
        Args: { _id: string; _reason: string }
        Returns: undefined
      }
      escalate_recharge_dispute: {
        Args: {
          _dispute_id: string
          _escalation_level: string
          _idempotency_key: string
          _reason: string
          _target_team: string
        }
        Returns: undefined
      }
      exchange_pearls_to_coins: {
        Args: {
          _idempotency_key: string
          _pearl_amount: number
          _rate_id: string
        }
        Returns: {
          coins_amount: number
          exchange_id: string
          reference: string
        }[]
      }
      execute_host_transfer: {
        Args: { _transfer_id: string }
        Returns: undefined
      }
      execute_recharge_refund: {
        Args: { _idempotency_key: string; _reason: string; _refund_id: string }
        Returns: Json
      }
      fail_recharge_request: {
        Args: { _reason: string; _request_id: string }
        Returns: undefined
      }
      fail_refund_gateway_execution: {
        Args: {
          _attempt_id: string
          _execution_token: string
          _failure_code: string
          _refund_id: string
          _safe_error: string
        }
        Returns: Json
      }
      finalize_refund_gateway_execution: {
        Args: {
          _attempt_id: string
          _execution_token: string
          _is_final: boolean
          _is_success: boolean
          _normalized_status: string
          _provider_refund_id: string
          _refund_id: string
          _requires_webhook_confirmation: boolean
          _safe_error_code: string
          _safe_reference: string
        }
        Returns: Json
      }
      finalize_refund_status_refresh: {
        Args: {
          _amount: number
          _attempt_id: string
          _currency: string
          _execution_token: string
          _gateway_mode: Database["public"]["Enums"]["payment_gateway_mode"]
          _is_final: boolean
          _normalized_status: string
          _provider_refund_id: string
          _refund_id: string
          _safe_error_code: string
        }
        Returns: Json
      }
      first_decide_recharge_dispute: {
        Args: {
          _decision_type: string
          _dispute_id: string
          _idempotency_key: string
          _reason: string
          _recommended_amount: number
          _resolution_code: string
          _resolution_reason: string
        }
        Returns: undefined
      }
      get_available_payment_methods: {
        Args: {
          _amount: number
          _country: string
          _currency: string
          _op_type: string
          _user_type?: string
        }
        Returns: {
          code: string
          country_code: string | null
          created_at: string
          created_by: string | null
          currency_code: string
          fixed_fee: number
          for_agents: boolean
          for_recharge: boolean
          for_users: boolean
          for_withdrawal: boolean
          gateway_id: string | null
          id: string
          instructions_ar: string | null
          instructions_en: string | null
          logo_url: string | null
          max_amount: number | null
          method_type: Database["public"]["Enums"]["payment_method_type"]
          min_amount: number
          name_ar: string
          name_en: string
          percentage_fee: number
          qr_url: string | null
          sort_order: number
          status: Database["public"]["Enums"]["payment_method_status"]
          updated_at: string
          updated_by: string | null
        }[]
        SetofOptions: {
          from: "*"
          to: "payment_methods"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      get_recharge_receipt_signed_url:
        | {
            Args: { _receipt_id: string; _ttl_seconds?: number }
            Returns: {
              storage_bucket: string
              storage_object_path: string
              ttl_seconds: number
            }[]
          }
        | {
            Args: {
              _reason?: string
              _receipt_id: string
              _ttl_seconds?: number
            }
            Returns: {
              storage_bucket: string
              storage_object_path: string
              ttl_seconds: number
            }[]
          }
      get_redacted_webhook_detail: {
        Args: { _webhook_id: string }
        Returns: Json
      }
      has_permission: {
        Args: { _permission: string; _user_id: string }
        Returns: boolean
      }
      has_role: {
        Args: {
          _role: Database["public"]["Enums"]["admin_role"]
          _user_id: string
        }
        Returns: boolean
      }
      is_admin: { Args: { _user_id: string }; Returns: boolean }
      is_charging_agency_owner: {
        Args: { _agency_id: string; _user_id: string }
        Returns: boolean
      }
      is_charging_agent: { Args: { _user_id: string }; Returns: boolean }
      list_recharge_webhooks: {
        Args: { _request_id: string }
        Returns: {
          event_type: string
          external_id: string
          gateway_id: string
          gateway_mode: string
          gateway_name: string
          id: string
          processed: boolean
          processed_at: string
          processing_error: string
          processing_owner: string
          processing_started_at: string
          processing_state: string
          provider_event_id: string
          received_at: string
          related_request_id: string
          retry_count: number
          signature_valid: boolean
        }[]
      }
      log_recharge_export: {
        Args: { _export_type: string; _filters: Json; _row_count: number }
        Returns: undefined
      }
      log_refund_webhook_audit: {
        Args: {
          _action: string
          _metadata: Json
          _refund_id: string
          _webhook_id: string
        }
        Returns: undefined
      }
      mark_chargeback_evidence_due: {
        Args: {
          _dispute_id: string
          _due_at: string
          _idempotency_key: string
          _reason: string
        }
        Returns: undefined
      }
      mark_gateway_secret_configured: {
        Args: {
          _id: string
          _reason: string
          _ref: string
          _secret_kind: string
        }
        Returns: undefined
      }
      mark_refund_webhook_terminal: {
        Args: {
          _attempt_id: string
          _failure_code: string
          _final_state: string
          _marked_duplicate?: boolean
          _safe_error: string
          _validation: string
          _webhook_id: string
        }
        Returns: undefined
      }
      mark_withdrawal_paid: {
        Args: { _external_ref: string; _proof_url: string; _request_id: string }
        Returns: undefined
      }
      mock_emit_webhook: {
        Args: { _kind: string; _override?: Json; _request_id: string }
        Returns: string
      }
      my_permissions: {
        Args: never
        Returns: {
          permission_key: string
        }[]
      }
      my_roles: {
        Args: never
        Returns: {
          role: Database["public"]["Enums"]["admin_role"]
        }[]
      }
      open_recharge_dispute: {
        Args: { _reason: string; _request_id: string }
        Returns: string
      }
      pause_coin_price_rule: { Args: { _id: string }; Returns: undefined }
      pause_coin_price_rule_v2: {
        Args: { _id: string; _reason: string }
        Returns: undefined
      }
      pause_payment_method: {
        Args: { _id: string; _reason: string }
        Returns: undefined
      }
      pause_recharge_package: {
        Args: { _id: string; _reason: string }
        Returns: undefined
      }
      prepare_refund_gateway_execution: {
        Args: {
          _reason: string
          _refund_id: string
          _request_idempotency_key: string
        }
        Returns: Json
      }
      prepare_refund_retry: {
        Args: {
          _override_limit?: boolean
          _reason: string
          _refund_id: string
          _request_idempotency_key: string
          _triggered_by: string
        }
        Returns: Json
      }
      prepare_refund_status_refresh: {
        Args: {
          _polling_owner: string
          _reason: string
          _refund_id: string
          _request_idempotency_key: string
          _triggered_by: string
        }
        Returns: Json
      }
      preview_admin_invite: {
        Args: { _token: string }
        Returns: {
          email: string
          expires_at: string
          role: Database["public"]["Enums"]["admin_role"]
          status: string
        }[]
      }
      preview_recharge_dispute_exposure: {
        Args: { _dispute_id?: string; _recharge_request_id: string }
        Returns: {
          blocking_reasons: string[]
          charged_back_amount: number
          original_base_coins: number
          original_bonus: number
          original_paid_amount: number
          refunded_amount: number
          remaining_base_exposure: number
          remaining_bonus_exposure: number
          remaining_financial_exposure: number
          resolved_compensation_amount: number
          reversed_base_coins: number
          reversed_bonus: number
          warnings: string[]
        }[]
      }
      preview_recharge_refund: {
        Args: {
          _bonus_policy?: string
          _recharge_request_id: string
          _refund_scope: Database["public"]["Enums"]["refund_scope"]
          _refund_type: Database["public"]["Enums"]["refund_type"]
          _requested_amount?: number
        }
        Returns: Json
      }
      process_confirmed_recharge_refund: {
        Args: { _refund_id: string }
        Returns: Json
      }
      publish_coin_price_rule: { Args: { _id: string }; Returns: undefined }
      publish_coin_price_rule_v2: {
        Args: { _id: string; _reason: string }
        Returns: undefined
      }
      publish_pearl_price_rule: { Args: { _id: string }; Returns: undefined }
      publish_recharge_package: { Args: { _id: string }; Returns: undefined }
      reactivate_agency: {
        Args: { _agency_id: string; _reason: string }
        Returns: undefined
      }
      reactivate_charging_agency: {
        Args: { _agency_id: string }
        Returns: undefined
      }
      reactivate_charging_agent: {
        Args: { _user_id: string }
        Returns: undefined
      }
      reactivate_host: { Args: { _host_id: string }; Returns: undefined }
      reclaim_stale_refund_status_checks: {
        Args: { _max?: number }
        Returns: number
      }
      reclaim_stale_refund_webhooks: {
        Args: { _older_than?: string }
        Returns: number
      }
      reclaim_stale_webhooks: {
        Args: { _older_than?: string }
        Returns: number
      }
      record_chargeback_recommendation: {
        Args: {
          _dispute_id: string
          _idempotency_key: string
          _reason: string
          _recommendation: string
        }
        Returns: undefined
      }
      record_dispute_evidence_scan_result: {
        Args: {
          _evidence_id: string
          _scan_status: string
          _scanner_reference?: string
        }
        Returns: undefined
      }
      record_gateway_health_check: {
        Args: {
          _error?: string
          _http_status: number
          _id: string
          _new_status: Database["public"]["Enums"]["payment_health_status"]
          _response_ms: number
        }
        Returns: undefined
      }
      record_manual_chargeback_provider_status: {
        Args: {
          _dispute_id: string
          _idempotency_key: string
          _provider_reference: string
          _provider_status: string
          _reason: string
          _source_reference: string
        }
        Returns: undefined
      }
      redact_dispute_note: {
        Args: { _idempotency_key: string; _note_id: string; _reason: string }
        Returns: undefined
      }
      refund_recharge_request: {
        Args: { _reason: string; _request_id: string }
        Returns: undefined
      }
      register_refund_webhook_event: {
        Args: {
          _amount: number
          _currency: string
          _gateway_id: string
          _gateway_mode: Database["public"]["Enums"]["payment_gateway_mode"]
          _normalized_event_type: string
          _occurred_at: string
          _original_provider_payment_id: string
          _payload_hash: string
          _payload_redacted: Json
          _provider_event_id: string
          _provider_refund_id: string
          _refund_reference: string
          _replay_check_passed: boolean
          _signature_verified: boolean
          _timestamp_verified: boolean
        }
        Returns: Json
      }
      reject_agency_join_request: {
        Args: { _note: string; _req_id: string }
        Returns: undefined
      }
      reject_recharge_dispute: {
        Args: { _dispute_id: string; _idempotency_key: string; _reason: string }
        Returns: undefined
      }
      reject_recharge_refund: {
        Args: { _reason: string; _refund_id: string }
        Returns: undefined
      }
      release_refund_status_refresh: {
        Args: { _owner: string; _refund_id: string }
        Returns: undefined
      }
      remove_agent_from_charging_agency: {
        Args: { _agency_id: string; _reason: string; _user_id: string }
        Returns: undefined
      }
      remove_host_from_agency: {
        Args: { _host_id: string; _reason: string }
        Returns: undefined
      }
      reopen_recharge_dispute: {
        Args: {
          _closed_dispute_id: string
          _idempotency_key: string
          _reason: string
        }
        Returns: string
      }
      reorder_payment_methods: {
        Args: { _order: string[] }
        Returns: undefined
      }
      request_dispute_evidence: {
        Args: {
          _dispute_id: string
          _due_at: string
          _evidence_types: Database["public"]["Enums"]["recharge_dispute_evidence_type_enum"][]
          _idempotency_key: string
          _reason: string
          _requested_from: string
          _user_message: string
        }
        Returns: undefined
      }
      request_recharge_refund: {
        Args: {
          _bonus_policy: string
          _idempotency_key: string
          _reason: string
          _recharge_request_id: string
          _refund_scope: Database["public"]["Enums"]["refund_scope"]
          _refund_type: Database["public"]["Enums"]["refund_type"]
          _requested_amount: number
        }
        Returns: string
      }
      request_withdrawal: {
        Args: {
          _account_data: Json
          _country: string
          _currency: string
          _method_id: string
          _pearls: number
        }
        Returns: string
      }
      resolve_coin_price: {
        Args: {
          _coin_amount: number
          _country: string
          _currency: string
          _payment_gateway_id?: string
          _payment_method_id?: string
          _user_id?: string
        }
        Returns: {
          base_price: number
          bonus_coins: number
          discount: number
          final_price: number
          fixed_fee: number
          percentage_fee: number
          rule_id: string
          tax: number
          version: number
        }[]
      }
      resolve_payment_failure: {
        Args: { _id: string; _resolution_note: string }
        Returns: undefined
      }
      resolve_payment_instructions: {
        Args: { _request_id: string }
        Returns: {
          account_bank_name: string
          account_currency: string
          account_display_name: string
          account_last4: string
          account_reference: string
          expires_at: string
          method_id: string
          method_kind: string
          method_label_ar: string
          method_label_en: string
        }[]
      }
      resolve_payment_method_account: {
        Args: {
          _amount: number
          _country_code: string
          _currency_code: string
          _method_id: string
          _operation_type: string
        }
        Returns: {
          account_id: string
          account_number_masked: string
          bank_name: string
          beneficiary_name_masked: string
          computed_fee: number
          extra_data: Json
          fixed_fee: number
          iban_masked: string
          label: string
          percentage_fee: number
          swift_code: string
        }[]
      }
      resolve_pearl_purchase_price: {
        Args: {
          _country: string
          _currency: string
          _pearls: number
          _user_id?: string
        }
        Returns: {
          agency_commission: number
          agent_commission: number
          base: number
          final_amount: number
          platform_commission: number
          rule_id: string
          version: number
        }[]
      }
      resolve_pearl_to_coin_exchange_rate: {
        Args: { _country: string; _currency: string; _pearls: number }
        Returns: {
          coins: number
          fee_pct: number
          rate_id: string
          version: number
        }[]
      }
      resolve_pearl_withdrawal_price: {
        Args: {
          _country: string
          _currency: string
          _pearls: number
          _user_id?: string
        }
        Returns: {
          base: number
          fees: number
          final_amount: number
          rule_id: string
          version: number
        }[]
      }
      resolve_recharge_dispute: {
        Args: {
          _dispute_id: string
          _idempotency_key: string
          _reason: string
          _resolution_code: string
          _resolution_reason: string
          _resolution_type: string
        }
        Returns: undefined
      }
      resolve_recharge_dispute_policy: {
        Args: {
          _country: string
          _currency: string
          _dispute_type: Database["public"]["Enums"]["recharge_dispute_type_enum"]
          _gateway_id: string
          _gateway_mode: string
          _source: Database["public"]["Enums"]["recharge_dispute_source_enum"]
        }
        Returns: {
          active: boolean
          allow_user_submission: boolean
          auto_close_after_no_response_days: number
          chargeback_response_days: number
          country: string | null
          created_at: string
          created_by: string | null
          currency: string | null
          dispute_type:
            | Database["public"]["Enums"]["recharge_dispute_type_enum"]
            | null
          ends_at: string | null
          evidence_submission_days: number
          first_response_hours: number
          gateway_id: string | null
          gateway_mode: string | null
          id: string
          name: string
          priority: number
          provisional_action_policy: Json
          require_gateway_evidence: boolean
          require_receipt: boolean
          require_second_decision: boolean
          resolution_target_hours: number
          second_decision_threshold: number
          source:
            | Database["public"]["Enums"]["recharge_dispute_source_enum"]
            | null
          starts_at: string | null
          updated_at: string
          user_dispute_window_days: number
          version: number
          wallet_restriction_policy: Json
        }
        SetofOptions: {
          from: "*"
          to: "recharge_dispute_policies"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      resolve_refund_policy: {
        Args: {
          _at?: string
          _country: string
          _currency: string
          _gateway_id: string
          _gateway_mode: string
          _refund_scope: Database["public"]["Enums"]["refund_scope"]
          _refund_type: Database["public"]["Enums"]["refund_type"]
        }
        Returns: {
          policy_id: string
          priority: number
          version: number
        }[]
      }
      resolve_refund_retry_policy: {
        Args: { _at?: string; _gateway_id: string; _gateway_mode: string }
        Returns: {
          policy_id: string
          priority: number
          version: number
        }[]
      }
      retry_payment_webhook: {
        Args: { _idempotency_key: string; _reason: string; _webhook_id: string }
        Returns: Json
      }
      reveal_payment_account_sensitive_data: {
        Args: { _id: string; _reason: string }
        Returns: {
          account_number_secret_ref: string
          beneficiary_name_secret_ref: string
          iban_secret_ref: string
        }[]
      }
      reverse_admin_wallet_adjustment: {
        Args: { _adjustment_id: string; _reason: string }
        Returns: undefined
      }
      reverse_coin_transfer: {
        Args: { _reason: string; _transfer_id: string }
        Returns: undefined
      }
      reverse_pearl_transfer: {
        Args: { _reason: string; _transfer_id: string }
        Returns: undefined
      }
      review_dispute_evidence: {
        Args: {
          _evidence_id: string
          _idempotency_key: string
          _reason: string
          _review_action: string
        }
        Returns: undefined
      }
      review_recharge_dispute: {
        Args: {
          _dispute_id: string
          _idempotency_key: string
          _reason: string
          _review_action: string
        }
        Returns: undefined
      }
      review_recharge_receipt: {
        Args: { _decision: string; _reason: string; _receipt_id: string }
        Returns: undefined
      }
      review_recharge_refund: {
        Args: { _decision: string; _reason: string; _refund_id: string }
        Returns: undefined
      }
      review_withdrawal: {
        Args: { _decision: string; _note: string; _request_id: string }
        Returns: undefined
      }
      rollback_coin_price_rule: {
        Args: { _id: string; _to_version: number }
        Returns: undefined
      }
      rollback_coin_price_rule_v2: {
        Args: { _id: string; _reason: string; _to_version: number }
        Returns: undefined
      }
      rollback_pearl_price_rule: {
        Args: { _id: string; _to_version: number }
        Returns: undefined
      }
      rollback_recharge_package: {
        Args: { _id: string; _to_version: number }
        Returns: undefined
      }
      second_approve_recharge_refund: {
        Args: { _reason: string; _refund_id: string }
        Returns: undefined
      }
      second_decide_recharge_dispute: {
        Args: {
          _approved_amount: number
          _decision: string
          _dispute_id: string
          _idempotency_key: string
          _reason: string
        }
        Returns: undefined
      }
      set_payment_method_account_active: {
        Args: { _active: boolean; _id: string; _reason: string }
        Returns: undefined
      }
      simulate_coin_price: { Args: { _payload: Json }; Returns: Json }
      submit_dispute_evidence: {
        Args: {
          _evidence_id: string
          _idempotency_key: string
          _reason: string
        }
        Returns: undefined
      }
      submit_recharge_receipt: {
        Args: {
          _currency: string
          _paid_amount: number
          _paid_at: string
          _payment_reference: string
          _receipt_id: string
          _sender_name: string
        }
        Returns: undefined
      }
      suspend_agency: {
        Args: { _agency_id: string; _reason: string }
        Returns: undefined
      }
      suspend_charging_agency: {
        Args: { _agency_id: string; _reason: string }
        Returns: undefined
      }
      suspend_charging_agent: {
        Args: { _reason: string; _user_id: string }
        Returns: undefined
      }
      suspend_host: {
        Args: { _host_id: string; _reason: string }
        Returns: undefined
      }
      transfer_agency_to_bd: {
        Args: { _agency_id: string; _new_bd_id: string; _reason: string }
        Returns: undefined
      }
      triage_recharge_dispute: {
        Args: {
          _assigned_team: string
          _dispute_id: string
          _idempotency_key: string
          _next_action: string
          _priority: Database["public"]["Enums"]["recharge_dispute_priority_enum"]
          _reason: string
          _request_gateway_evidence: boolean
          _request_internal_evidence: boolean
          _request_user_evidence: boolean
          _severity: Database["public"]["Enums"]["recharge_dispute_severity_enum"]
        }
        Returns: undefined
      }
      update_agency: {
        Args: {
          _agency_id: string
          _bio: string
          _country: string
          _cover_url: string
          _join_policy: string
          _language: string
          _logo_url: string
          _name: string
        }
        Returns: undefined
      }
      update_agency_level: {
        Args: { _agency_id: string; _new_level: number; _reason: string }
        Returns: undefined
      }
      update_bd_level: {
        Args: { _bd_id: string; _level: number }
        Returns: undefined
      }
      update_charging_agency: {
        Args: {
          _admin_notes: string
          _agency_id: string
          _city: string
          _country: string
          _cover_url: string
          _default_currency: string
          _email: string
          _logo_url: string
          _name: string
          _phone: string
        }
        Returns: undefined
      }
      update_charging_agent_limits: {
        Args: {
          _daily_coin_limit: number
          _daily_pearl_limit: number
          _max_coin_transfer: number
          _max_pearl_transfer: number
          _min_coin_transfer: number
          _min_pearl_transfer: number
          _monthly_coin_limit: number
          _monthly_pearl_limit: number
          _user_id: string
        }
        Returns: undefined
      }
      update_charging_agent_permissions: {
        Args: {
          _can_buy_pearls: boolean
          _can_exchange_pearls_to_coins: boolean
          _can_sell_coins: boolean
          _can_transfer_to_agents: boolean
          _user_id: string
        }
        Returns: undefined
      }
      update_coin_price_rule: {
        Args: { _id: string; _payload: Json }
        Returns: undefined
      }
      update_gateway_country_config: {
        Args: {
          _active: boolean
          _country_code: string
          _fixed_fee: number
          _gateway_id: string
          _max_amount: number
          _min_amount: number
          _percentage_fee: number
        }
        Returns: string
      }
      update_gateway_currency_config: {
        Args: {
          _active: boolean
          _currency_code: string
          _exchange_rate: number
          _gateway_id: string
        }
        Returns: string
      }
      update_gateway_health: {
        Args: {
          _id: string
          _status: Database["public"]["Enums"]["payment_health_status"]
        }
        Returns: undefined
      }
      update_host_level: {
        Args: { _host_id: string; _level: number }
        Returns: undefined
      }
      update_payment_gateway: {
        Args: { _id: string; _patch: Json; _reason?: string }
        Returns: undefined
      }
      update_payment_method: {
        Args: { _id: string; _patch: Json; _reason: string }
        Returns: undefined
      }
      update_payment_method_account: {
        Args: { _id: string; _patch: Json; _reason: string }
        Returns: undefined
      }
      upsert_payment_method_limit: {
        Args: {
          _daily_max: number
          _method_id: string
          _monthly_max: number
          _per_txn_max: number
          _per_txn_min: number
          _scope: string
          _weekly_max: number
        }
        Returns: string
      }
      validate_coin_price_conflicts: {
        Args: { _rule_id: string }
        Returns: {
          conflict_code: string
          conflict_name: string
          conflict_rule_id: string
          reason: string
        }[]
      }
      verify_recharge_payment: {
        Args: {
          _idempotency_key: string
          _reason: string
          _request_id: string
          _source: string
        }
        Returns: Json
      }
    }
    Enums: {
      admin_role:
        | "super_admin"
        | "admin"
        | "finance"
        | "moderator"
        | "agency_manager"
        | "bd_manager"
        | "support"
        | "auditor"
        | "viewer"
      charging_agency_status:
        | "pending"
        | "active"
        | "suspended"
        | "under_review"
        | "closed"
      charging_agent_role:
        | "charging_agency_owner"
        | "charging_agency_deputy"
        | "charging_agent"
        | "charging_accountant"
        | "charging_supervisor"
        | "charging_region_manager"
        | "charging_country_manager"
      charging_agent_status: "active" | "suspended" | "inactive"
      charging_txn_status: "pending" | "completed" | "reversed" | "failed"
      coin_price_status:
        | "draft"
        | "published"
        | "paused"
        | "archived"
        | "expired"
      financial_resolution_status_enum:
        | "not_required"
        | "pending"
        | "blocked"
        | "waived"
        | "completed"
      gender: "male" | "female" | "other" | "unspecified"
      ledger_direction: "credit" | "debit"
      ledger_reason:
        | "recharge"
        | "gift_sent"
        | "gift_received"
        | "call_cost"
        | "withdrawal"
        | "refund"
        | "bonus"
        | "penalty"
        | "transfer_in"
        | "transfer_out"
        | "adjustment"
        | "reward"
        | "game_win"
        | "game_loss"
        | "charging_coin_transfer"
        | "charging_coin_transfer_reverse"
        | "charging_pearl_transfer"
        | "charging_pearl_transfer_reverse"
        | "pearl_purchase"
        | "pearl_purchase_reverse"
        | "pearl_to_coin_exchange"
        | "pearl_to_coin_exchange_reverse"
        | "admin_coin_credit"
        | "admin_coin_debit"
        | "admin_pearl_credit"
        | "admin_pearl_debit"
        | "recharge_credit"
        | "recharge_bonus"
        | "recharge_refund"
        | "withdrawal_reserve"
        | "withdrawal_release"
        | "withdrawal_settle"
      malware_scan_status:
        | "pending"
        | "clean"
        | "suspicious"
        | "infected"
        | "failed"
        | "skipped"
      payment_gateway_mode: "test" | "live"
      payment_gateway_status:
        | "active"
        | "inactive"
        | "maintenance"
        | "deprecated"
      payment_health_status:
        | "healthy"
        | "degraded"
        | "down"
        | "unknown"
        | "misconfigured"
      payment_method_status:
        | "active"
        | "disabled"
        | "maintenance"
        | "paused"
        | "archived"
        | "draft"
        | "under_review"
        | "misconfigured"
      payment_method_type:
        | "wallet"
        | "card"
        | "bank_transfer"
        | "mobile_money"
        | "qr"
        | "manual"
        | "crypto"
      pearl_price_kind:
        | "buy_from_user"
        | "withdrawal"
        | "agent_buy"
        | "exchange_to_coins"
      pearl_price_status: "draft" | "published" | "paused" | "archived"
      pearl_purchase_status:
        | "draft"
        | "pending_user_confirmation"
        | "pending_agent_payment"
        | "payment_submitted"
        | "pending_user_receipt_confirmation"
        | "pending_admin_review"
        | "completed"
        | "rejected"
        | "cancelled"
        | "disputed"
        | "reversed"
      recharge_dispute_evidence_status_enum:
        | "uploaded"
        | "submitted"
        | "under_review"
        | "accepted"
        | "rejected"
        | "superseded"
        | "quarantined"
      recharge_dispute_evidence_type_enum:
        | "payment_receipt"
        | "bank_statement"
        | "account_statement"
        | "gateway_confirmation"
        | "refund_confirmation"
        | "user_screenshot"
        | "chat_record"
        | "support_record"
        | "device_log"
        | "webhook_record"
        | "provider_document"
        | "identity_confirmation"
        | "other"
      recharge_dispute_note_type_enum:
        | "internal_note"
        | "user_message"
        | "system_event"
        | "gateway_update"
        | "evidence_request"
        | "evidence_received"
        | "decision_note"
        | "escalation_note"
        | "closure_note"
      recharge_dispute_note_visibility_enum:
        | "internal"
        | "user_visible"
        | "finance_only"
        | "auditor_only"
        | "system_only"
      recharge_dispute_priority_enum: "low" | "normal" | "high" | "urgent"
      recharge_dispute_provisional_action_enum:
        | "none"
        | "manual_monitoring"
        | "temporary_recharge_hold"
        | "temporary_refund_hold"
        | "temporary_withdrawal_hold"
        | "temporary_wallet_spending_hold"
        | "request_identity_review"
        | "escalate_to_fraud_review"
      recharge_dispute_severity_enum:
        | "informational"
        | "low"
        | "medium"
        | "high"
        | "critical"
      recharge_dispute_source_enum:
        | "user"
        | "support"
        | "finance"
        | "system"
        | "payment_gateway"
        | "bank"
        | "chargeback_webhook"
        | "internal_audit"
      recharge_dispute_status_enum:
        | "opened"
        | "triage"
        | "awaiting_user_evidence"
        | "awaiting_internal_evidence"
        | "awaiting_gateway_evidence"
        | "under_review"
        | "escalated"
        | "pending_first_decision"
        | "pending_second_decision"
        | "provisional_action"
        | "resolved_user_favor"
        | "resolved_platform_favor"
        | "resolved_partial"
        | "rejected"
        | "cancelled"
        | "closed"
        | "chargeback_received"
        | "chargeback_acknowledged"
        | "chargeback_evidence_due"
        | "chargeback_contested"
        | "chargeback_accepted"
        | "chargeback_won"
        | "chargeback_lost"
      recharge_dispute_type_enum:
        | "payment_not_credited"
        | "charged_wrong_amount"
        | "duplicate_charge"
        | "unauthorized_payment"
        | "payment_method_issue"
        | "receipt_rejected"
        | "refund_not_received"
        | "partial_refund_issue"
        | "coins_removed_incorrectly"
        | "provider_chargeback"
        | "provider_inquiry"
        | "fraud_suspected"
        | "technical_error"
        | "other"
      recharge_package_status:
        | "draft"
        | "review"
        | "published"
        | "paused"
        | "expired"
        | "archived"
      recharge_receipt_status:
        | "uploaded"
        | "submitted"
        | "under_review"
        | "approved"
        | "rejected"
        | "more_info_required"
        | "superseded"
        | "quarantined"
      recharge_request_status:
        | "created"
        | "pending_payment"
        | "payment_submitted"
        | "paid"
        | "verifying"
        | "manual_review"
        | "approved"
        | "crediting"
        | "completed"
        | "failed"
        | "cancelled"
        | "refunded"
        | "disputed"
        | "refund_pending"
        | "partially_refunded"
        | "chargeback"
        | "reversed"
      recharge_user_target:
        | "all"
        | "new"
        | "existing"
        | "vip"
        | "host"
        | "agent"
      refund_scope:
        | "money_only"
        | "money_and_base_coins"
        | "money_and_all_coins"
        | "administrative_compensation"
        | "technical_failure"
      refund_status:
        | "requested"
        | "pending_review"
        | "pending_second_review"
        | "approved"
        | "processing_gateway"
        | "gateway_confirmed"
        | "reversing_wallet"
        | "manual_review"
        | "completed"
        | "partially_completed"
        | "failed"
        | "rejected"
        | "cancelled"
      refund_type: "full" | "partial"
      txn_outbox_status:
        | "pending"
        | "processing"
        | "sent"
        | "failed"
        | "dead_letter"
      user_status: "active" | "banned" | "suspended" | "deleted"
      verification_status: "unverified" | "pending" | "verified" | "rejected"
      wallet_account: "coins" | "diamonds" | "bonus"
      wallet_adjustment_kind:
        | "coin_credit"
        | "coin_debit"
        | "pearl_credit"
        | "pearl_debit"
      wallet_adjustment_status:
        | "pending"
        | "approved"
        | "rejected"
        | "applied"
        | "reversed"
      withdrawal_status:
        | "submitted"
        | "reviewing"
        | "approved"
        | "paying"
        | "paid"
        | "confirmed"
        | "rejected"
        | "cancelled"
        | "disputed"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      admin_role: [
        "super_admin",
        "admin",
        "finance",
        "moderator",
        "agency_manager",
        "bd_manager",
        "support",
        "auditor",
        "viewer",
      ],
      charging_agency_status: [
        "pending",
        "active",
        "suspended",
        "under_review",
        "closed",
      ],
      charging_agent_role: [
        "charging_agency_owner",
        "charging_agency_deputy",
        "charging_agent",
        "charging_accountant",
        "charging_supervisor",
        "charging_region_manager",
        "charging_country_manager",
      ],
      charging_agent_status: ["active", "suspended", "inactive"],
      charging_txn_status: ["pending", "completed", "reversed", "failed"],
      coin_price_status: [
        "draft",
        "published",
        "paused",
        "archived",
        "expired",
      ],
      financial_resolution_status_enum: [
        "not_required",
        "pending",
        "blocked",
        "waived",
        "completed",
      ],
      gender: ["male", "female", "other", "unspecified"],
      ledger_direction: ["credit", "debit"],
      ledger_reason: [
        "recharge",
        "gift_sent",
        "gift_received",
        "call_cost",
        "withdrawal",
        "refund",
        "bonus",
        "penalty",
        "transfer_in",
        "transfer_out",
        "adjustment",
        "reward",
        "game_win",
        "game_loss",
        "charging_coin_transfer",
        "charging_coin_transfer_reverse",
        "charging_pearl_transfer",
        "charging_pearl_transfer_reverse",
        "pearl_purchase",
        "pearl_purchase_reverse",
        "pearl_to_coin_exchange",
        "pearl_to_coin_exchange_reverse",
        "admin_coin_credit",
        "admin_coin_debit",
        "admin_pearl_credit",
        "admin_pearl_debit",
        "recharge_credit",
        "recharge_bonus",
        "recharge_refund",
        "withdrawal_reserve",
        "withdrawal_release",
        "withdrawal_settle",
      ],
      malware_scan_status: [
        "pending",
        "clean",
        "suspicious",
        "infected",
        "failed",
        "skipped",
      ],
      payment_gateway_mode: ["test", "live"],
      payment_gateway_status: [
        "active",
        "inactive",
        "maintenance",
        "deprecated",
      ],
      payment_health_status: [
        "healthy",
        "degraded",
        "down",
        "unknown",
        "misconfigured",
      ],
      payment_method_status: [
        "active",
        "disabled",
        "maintenance",
        "paused",
        "archived",
        "draft",
        "under_review",
        "misconfigured",
      ],
      payment_method_type: [
        "wallet",
        "card",
        "bank_transfer",
        "mobile_money",
        "qr",
        "manual",
        "crypto",
      ],
      pearl_price_kind: [
        "buy_from_user",
        "withdrawal",
        "agent_buy",
        "exchange_to_coins",
      ],
      pearl_price_status: ["draft", "published", "paused", "archived"],
      pearl_purchase_status: [
        "draft",
        "pending_user_confirmation",
        "pending_agent_payment",
        "payment_submitted",
        "pending_user_receipt_confirmation",
        "pending_admin_review",
        "completed",
        "rejected",
        "cancelled",
        "disputed",
        "reversed",
      ],
      recharge_dispute_evidence_status_enum: [
        "uploaded",
        "submitted",
        "under_review",
        "accepted",
        "rejected",
        "superseded",
        "quarantined",
      ],
      recharge_dispute_evidence_type_enum: [
        "payment_receipt",
        "bank_statement",
        "account_statement",
        "gateway_confirmation",
        "refund_confirmation",
        "user_screenshot",
        "chat_record",
        "support_record",
        "device_log",
        "webhook_record",
        "provider_document",
        "identity_confirmation",
        "other",
      ],
      recharge_dispute_note_type_enum: [
        "internal_note",
        "user_message",
        "system_event",
        "gateway_update",
        "evidence_request",
        "evidence_received",
        "decision_note",
        "escalation_note",
        "closure_note",
      ],
      recharge_dispute_note_visibility_enum: [
        "internal",
        "user_visible",
        "finance_only",
        "auditor_only",
        "system_only",
      ],
      recharge_dispute_priority_enum: ["low", "normal", "high", "urgent"],
      recharge_dispute_provisional_action_enum: [
        "none",
        "manual_monitoring",
        "temporary_recharge_hold",
        "temporary_refund_hold",
        "temporary_withdrawal_hold",
        "temporary_wallet_spending_hold",
        "request_identity_review",
        "escalate_to_fraud_review",
      ],
      recharge_dispute_severity_enum: [
        "informational",
        "low",
        "medium",
        "high",
        "critical",
      ],
      recharge_dispute_source_enum: [
        "user",
        "support",
        "finance",
        "system",
        "payment_gateway",
        "bank",
        "chargeback_webhook",
        "internal_audit",
      ],
      recharge_dispute_status_enum: [
        "opened",
        "triage",
        "awaiting_user_evidence",
        "awaiting_internal_evidence",
        "awaiting_gateway_evidence",
        "under_review",
        "escalated",
        "pending_first_decision",
        "pending_second_decision",
        "provisional_action",
        "resolved_user_favor",
        "resolved_platform_favor",
        "resolved_partial",
        "rejected",
        "cancelled",
        "closed",
        "chargeback_received",
        "chargeback_acknowledged",
        "chargeback_evidence_due",
        "chargeback_contested",
        "chargeback_accepted",
        "chargeback_won",
        "chargeback_lost",
      ],
      recharge_dispute_type_enum: [
        "payment_not_credited",
        "charged_wrong_amount",
        "duplicate_charge",
        "unauthorized_payment",
        "payment_method_issue",
        "receipt_rejected",
        "refund_not_received",
        "partial_refund_issue",
        "coins_removed_incorrectly",
        "provider_chargeback",
        "provider_inquiry",
        "fraud_suspected",
        "technical_error",
        "other",
      ],
      recharge_package_status: [
        "draft",
        "review",
        "published",
        "paused",
        "expired",
        "archived",
      ],
      recharge_receipt_status: [
        "uploaded",
        "submitted",
        "under_review",
        "approved",
        "rejected",
        "more_info_required",
        "superseded",
        "quarantined",
      ],
      recharge_request_status: [
        "created",
        "pending_payment",
        "payment_submitted",
        "paid",
        "verifying",
        "manual_review",
        "approved",
        "crediting",
        "completed",
        "failed",
        "cancelled",
        "refunded",
        "disputed",
        "refund_pending",
        "partially_refunded",
        "chargeback",
        "reversed",
      ],
      recharge_user_target: ["all", "new", "existing", "vip", "host", "agent"],
      refund_scope: [
        "money_only",
        "money_and_base_coins",
        "money_and_all_coins",
        "administrative_compensation",
        "technical_failure",
      ],
      refund_status: [
        "requested",
        "pending_review",
        "pending_second_review",
        "approved",
        "processing_gateway",
        "gateway_confirmed",
        "reversing_wallet",
        "manual_review",
        "completed",
        "partially_completed",
        "failed",
        "rejected",
        "cancelled",
      ],
      refund_type: ["full", "partial"],
      txn_outbox_status: [
        "pending",
        "processing",
        "sent",
        "failed",
        "dead_letter",
      ],
      user_status: ["active", "banned", "suspended", "deleted"],
      verification_status: ["unverified", "pending", "verified", "rejected"],
      wallet_account: ["coins", "diamonds", "bonus"],
      wallet_adjustment_kind: [
        "coin_credit",
        "coin_debit",
        "pearl_credit",
        "pearl_debit",
      ],
      wallet_adjustment_status: [
        "pending",
        "approved",
        "rejected",
        "applied",
        "reversed",
      ],
      withdrawal_status: [
        "submitted",
        "reviewing",
        "approved",
        "paying",
        "paid",
        "confirmed",
        "rejected",
        "cancelled",
        "disputed",
      ],
    },
  },
} as const
