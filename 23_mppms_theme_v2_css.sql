-- ============================================================
-- MPPMS :: 23_mppms_theme_v2_css.sql
-- Purpose : Corporate Blue & Glassmorphism Custom Theme CSS
-- Usage   : Paste into APEX Application Definition -> Theme Roller or User Defined Inline CSS
-- ============================================================

/*
=================================================================
MPPMS ENTERPRISE UI / UX DESIGN SYSTEM V2.0
=================================================================
*/

/* --- Global Theme Variables & Typography --- */
:root {
  --mppms-primary: #1E3A8A;        /* Deep Corporate Blue */
  --mppms-primary-light: #2563EB;  /* Sapphire Blue Accent */
  --mppms-secondary: #0F172A;      /* Slate Header Dark */
  --mppms-accent: #0284C7;         /* Ocean Cyan */
  --mppms-bg-light: #F8FAFC;       /* Off-White Page Background */
  --mppms-surface: #FFFFFF;        /* Card Surface White */
  --mppms-border: #E2E8F0;         /* Subtle Border Grey */
  --mppms-text-main: #1E293B;      /* High contrast body text */
  --mppms-text-muted: #64748B;     /* Muted secondary text */
  
  /* Status Colors */
  --mppms-success: #059669;        /* Emerald Green */
  --mppms-success-bg: #ECFDF5;
  --mppms-warning: #D97706;        /* Amber Orange */
  --mppms-warning-bg: #FFFBEB;
  --mppms-danger: #DC2626;         /* Crimson Red */
  --mppms-danger-bg: #FEF2F2;
  --mppms-info: #0284C7;           /* Cyan Info */
  --mppms-info-bg: #F0F9FF;
}

/* Page Background */
body.t-PageBody {
  background-color: var(--mppms-bg-light) !important;
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif !important;
  color: var(--mppms-text-main);
}

/* --- Top Navigation Header Bar --- */
.t-Header-navBar {
  background: linear-gradient(135deg, #0F172A 0%, #1E3A8A 100%) !important;
  box-shadow: 0 4px 12px rgba(15, 23, 42, 0.15);
}

.t-Header-logo-link {
  font-weight: 700 !important;
  letter-spacing: 0.5px;
  color: #FFFFFF !important;
}

/* --- Navigation Tree (Left Menu) --- */
.t-TreeNav {
  background-color: #0F172A !important;
}

.t-TreeNav .a-Tree-node--topLevel > .a-Tree-content {
  color: #94A3B8 !important;
  font-weight: 600;
  transition: all 0.2s ease-in-out;
}

.t-TreeNav .a-Tree-node--topLevel > .a-Tree-content:hover,
.t-TreeNav .a-Tree-node--topLevel.is-selected > .a-Tree-content {
  background: rgba(255, 255, 255, 0.08) !important;
  color: #FFFFFF !important;
  border-left: 4px solid var(--mppms-primary-light);
}

/* --- Glassmorphism KPI Dashboard Cards --- */
.mppms-kpi-card {
  background: rgba(255, 255, 255, 0.95);
  backdrop-filter: blur(10px);
  border: 1px solid var(--mppms-border);
  border-radius: 12px;
  padding: 24px;
  box-shadow: 0 10px 15px -3px rgba(0, 0, 0, 0.04), 0 4px 6px -2px rgba(0, 0, 0, 0.02);
  transition: transform 0.25s cubic-bezier(0.4, 0, 0.2, 1), box-shadow 0.25s cubic-bezier(0.4, 0, 0.2, 1);
  position: relative;
  overflow: hidden;
}

.mppms-kpi-card::before {
  content: '';
  position: absolute;
  top: 0;
  left: 0;
  width: 100%;
  height: 4px;
  background: linear-gradient(90deg, #2563EB, #0284C7);
}

.mppms-kpi-card:hover {
  transform: translateY(-4px);
  box-shadow: 0 20px 25px -5px rgba(0, 0, 0, 0.08), 0 10px 10px -5px rgba(0, 0, 0, 0.04);
}

.mppms-kpi-card.mppms-kpi-danger::before {
  background: linear-gradient(90deg, #DC2626, #EF4444);
}

.mppms-kpi-card.mppms-kpi-warning::before {
  background: linear-gradient(90deg, #D97706, #F59E0B);
}

.mppms-kpi-card.mppms-kpi-success::before {
  background: linear-gradient(90deg, #059669, #10B981);
}

.mppms-kpi-value {
  font-size: 2.25rem;
  font-weight: 800;
  line-height: 1.1;
  color: var(--mppms-text-main);
  letter-spacing: -0.02em;
}

.mppms-kpi-label {
  font-size: 0.85rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--mppms-text-muted);
  margin-top: 6px;
}

/* --- Region Containers & Cards --- */
.t-Region {
  border-radius: 12px !important;
  border: 1px solid var(--mppms-border) !important;
  box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.03) !important;
  background-color: var(--mppms-surface) !important;
  margin-bottom: 20px !important;
}

.t-Region-header {
  border-bottom: 1px solid var(--mppms-border) !important;
  background-color: #FAFAFA !important;
  border-top-left-radius: 12px !important;
  border-top-right-radius: 12px !important;
  padding: 14px 20px !important;
}

.t-Region-title {
  font-size: 1.05rem !important;
  font-weight: 700 !important;
  color: var(--mppms-secondary) !important;
}

/* --- Interactive Reports & Grids Table Styling --- */
.a-IRR-table, .a-GV-table {
  border-collapse: separate !important;
  border-spacing: 0 !important;
}

.a-IRR-header, .a-GV-header {
  background-color: #F1F5F9 !important;
  color: var(--mppms-secondary) !important;
  font-size: 0.8rem !important;
  font-weight: 700 !important;
  text-transform: uppercase !important;
  letter-spacing: 0.04em !important;
  border-bottom: 2px solid var(--mppms-border) !important;
}

.a-IRR-table td, .a-GV-table td {
  font-size: 0.88rem !important;
  padding: 12px 16px !important;
  border-bottom: 1px solid #F1F5F9 !important;
  color: var(--mppms-text-main) !important;
}

.a-IRR-table tr:hover td, .a-GV-table tr:hover td {
  background-color: #F8FAFC !important;
}

/* --- Modern Badge Pill Status Styling --- */
.mppms-badge {
  display: inline-flex;
  align-items: center;
  padding: 4px 10px;
  border-radius: 9999px;
  font-size: 0.72rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.05em;
}

.mppms-badge-success {
  background-color: var(--mppms-success-bg);
  color: var(--mppms-success);
  border: 1px solid rgba(5, 150, 105, 0.2);
}

.mppms-badge-warning {
  background-color: var(--mppms-warning-bg);
  color: var(--mppms-warning);
  border: 1px solid rgba(217, 119, 6, 0.2);
}

.mppms-badge-danger {
  background-color: var(--mppms-danger-bg);
  color: var(--mppms-danger);
  border: 1px solid rgba(220, 38, 38, 0.2);
}

.mppms-badge-info {
  background-color: var(--mppms-info-bg);
  color: var(--mppms-info);
  border: 1px solid rgba(2, 132, 199, 0.2);
}

/* --- Buttons --- */
.t-Button--hot {
  background: linear-gradient(135deg, #1E3A8A 0%, #2563EB 100%) !important;
  border: none !important;
  box-shadow: 0 4px 6px -1px rgba(37, 99, 235, 0.3) !important;
  border-radius: 8px !important;
  font-weight: 600 !important;
  padding: 8px 18px !important;
  transition: all 0.2s ease !important;
}

.t-Button--hot:hover {
  background: linear-gradient(135deg, #1D4ED8 0%, #1E40AF 100%) !important;
  box-shadow: 0 6px 12px -2px rgba(37, 99, 235, 0.4) !important;
  transform: translateY(-1px);
}
