# MPPMS — Oracle APEX Application Build Guide
## Phase 6: Complete Step-by-Step Instructions

---

## Prerequisites
Before starting, ensure all database phases are complete:
- ✅ Phase 1-2: Tables, Sequences, Triggers, Indexes
- ✅ Phase 3: Sample Data loaded
- ✅ Phase 4: PL/SQL Packages compiled
- ✅ Phase 5: Views created
- ✅ Phase 6: Workspace setup (`12_apex_workspace_setup.sql` run as SYSDBA)

**APEX URL:** `http://localhost:8080/ords/f?p=4550`  
**Workspace:** `MPPMS`  
**Login:** `MPPMS_ADMIN` / `Admin#2026`

---

## STEP 1 — Log Into APEX & Create Application

1. Open browser → `http://localhost:8080/ords/`
2. Click **App Builder** → Sign In:
   - Workspace: `MPPMS`
   - Username: `MPPMS_ADMIN`
   - Password: `Admin#2026`
3. Click **Create** → **New Application**

### Application Settings
| Setting | Value |
|---------|-------|
| **Name** | Material Planning & Procurement Management System |
| **Application ID** | (auto — note this down) |
| **Schema** | MPPMS |
| **Authentication** | Application Express Accounts |
| **Theme** | Universal Theme |
| **Theme Style** | Vita (we'll switch to Blue later) |
| **Language** | English |

4. Click **Create Application** (skip adding pages for now — we build manually)

---

## STEP 2 — Configure Theme Style (Blue/White Corporate)

1. **Shared Components** → **Themes** → **Universal Theme** → **Modify**
2. Under **Theme Style** → Select **Vita – Slate** (closest to corporate blue)
3. **OR**: Shared Components → **User Interface Attributes** → Theme Style → **Vita**

### Custom CSS (paste in Shared Components → CSS → Inline)
```css
/* MPPMS Corporate Blue Theme */
:root {
  --ut-palette-primary: #1565C0;
  --ut-palette-primary-text: #FFFFFF;
  --ut-palette-success: #2E7D32;
  --ut-palette-danger:  #C62828;
  --ut-palette-warning: #F57F17;
}

/* Navigation bar */
.t-Header-nav { background: linear-gradient(135deg, #0D47A1 0%, #1565C0 100%); }
.t-NavigationBar-item a { color: #FFFFFF !important; }

/* Page header */
.t-Body-title { background: #F5F7FA; border-bottom: 3px solid #1565C0; }

/* KPI Cards */
.mppms-kpi-card {
  background: #FFFFFF;
  border-radius: 12px;
  box-shadow: 0 2px 16px rgba(21,101,192,0.10);
  border-left: 4px solid #1565C0;
  padding: 20px;
  transition: transform 0.2s, box-shadow 0.2s;
}
.mppms-kpi-card:hover {
  transform: translateY(-3px);
  box-shadow: 0 8px 24px rgba(21,101,192,0.18);
}
.mppms-kpi-value {
  font-size: 2.4rem;
  font-weight: 700;
  color: #1565C0;
  line-height: 1;
}
.mppms-kpi-label {
  font-size: 0.85rem;
  color: #546E7A;
  font-weight: 500;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  margin-top: 6px;
}
.mppms-kpi-danger  { border-left-color: #C62828; }
.mppms-kpi-danger .mppms-kpi-value { color: #C62828; }
.mppms-kpi-warning { border-left-color: #F57F17; }
.mppms-kpi-warning .mppms-kpi-value { color: #E65100; }
.mppms-kpi-success { border-left-color: #2E7D32; }
.mppms-kpi-success .mppms-kpi-value { color: #2E7D32; }

/* Interactive Report styling */
.t-Report-wrap table { border-collapse: separate; border-spacing: 0; }
.t-Report-wrap th { background: #1565C0 !important; color: #FFFFFF !important; font-weight: 600; }
.t-Report-wrap tr:hover td { background: #E3F2FD !important; }

/* Badge styling for status */
.mppms-badge {
  display: inline-block;
  padding: 3px 10px;
  border-radius: 20px;
  font-size: 0.75rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.05em;
}
.badge-approved  { background: #E8F5E9; color: #2E7D32; }
.badge-pending   { background: #FFF8E1; color: #F57F17; }
.badge-danger    { background: #FFEBEE; color: #C62828; }
.badge-info      { background: #E3F2FD; color: #1565C0; }
.badge-draft     { background: #ECEFF1; color: #546E7A; }

/* Section headers */
.mppms-section-title {
  font-size: 1.1rem;
  font-weight: 700;
  color: #1565C0;
  border-bottom: 2px solid #E3F2FD;
  padding-bottom: 8px;
  margin-bottom: 16px;
}
```

---

## STEP 3 — Set Up Navigation Menu

**Shared Components → Navigation Menu → Desktop Navigation Menu → Edit**

Delete default entries and create this structure:

### Level 1: Dashboard
- Name: `Dashboard`
- Target: `Page 1`
- Icon: `fa-tachometer`

### Level 1: Masters
- Name: `Masters`
- Icon: `fa-database`
- No target (parent only)

  - **Child:** Supplier Master → Page 10 → Icon: `fa-truck`
  - **Child:** Material Master → Page 20 → Icon: `fa-cubes`
  - **Child:** Product Master → Page 30 → Icon: `fa-box`

### Level 1: Planning
- Name: `Planning`
- Icon: `fa-sitemap`

  - **Child:** Bill of Materials → Page 40 → Icon: `fa-list-alt`
  - **Child:** Demand Forecast → Page 50 → Icon: `fa-chart-bar`
  - **Child:** Production Plan → Page 60 → Icon: `fa-calendar-alt`
  - **Child:** MRP → Page 70 → Icon: `fa-cogs`

### Level 1: Procurement
- Name: `Procurement`
- Icon: `fa-shopping-cart`

  - **Child:** Purchase Requisition → Page 80 → Icon: `fa-file-alt`
  - **Child:** Purchase Order → Page 90 → Icon: `fa-file-invoice`
  - **Child:** Procurement Tracking → Page 100 → Icon: `fa-shipping-fast`

### Level 1: Reports
- Name: `Reports`
- Icon: `fa-chart-pie`

  - **Child:** Material Planning Report → Page 110 → Icon: `fa-chart-line`
  - **Child:** Procurement Report → Page 120 → Icon: `fa-chart-bar`
  - **Child:** Supplier Report → Page 130 → Icon: `fa-star`
  - **Child:** PO Report → Page 140 → Icon: `fa-file-invoice-dollar`

---

## STEP 4 — Create Shared LOVs

**Shared Components → List of Values → Create** (repeat for each):

| LOV Name | Type | Source |
|----------|------|--------|
| `LOV_SUPPLIERS` | Dynamic | See 13_apex_lovs.sql |
| `LOV_MATERIALS` | Dynamic | See 13_apex_lovs.sql |
| `LOV_PRODUCTS` | Dynamic | See 13_apex_lovs.sql |
| `LOV_ACTIVE_BOMS` | Dynamic | See 13_apex_lovs.sql |
| `LOV_SUPPLIER_STATUS` | Static | Active / Inactive |
| `LOV_PR_STATUS` | Static | Draft/Submitted/Approved/Rejected/Ordered/Closed |
| `LOV_PRIORITY` | Static | High/Medium/Low |
| `LOV_PO_STATUS` | Static | (see lovs file) |
| `LOV_DELIVERY_STATUS` | Static | (see lovs file) |
| `LOV_UNIT_OF_MEASURE` | Static | EA/KG/LTR/MTR/SQM/ROLL |
| `LOV_PLAN_STATUS` | Static | Draft/Approved/In Progress/Completed/Cancelled |
| `LOV_FORECAST_TYPE` | Static | Manual/System/AI/Historical |
| `LOV_MATERIAL_CATEGORY` | Dynamic | DISTINCT CATEGORY FROM MATERIAL_MASTER |

---

## STEP 5 — Page Map Summary

Use this as your build reference. Create pages **in this exact order**:

| Page # | Type | Title | Source |
|--------|------|-------|--------|
| 1 | Dashboard | Dashboard | PKG_DASHBOARD functions + chart queries |
| 10 | IR + Form (11) | Supplier Master | SUPPLIER_MASTER |
| 20 | IR + Form (21) | Material Master | MATERIAL_MASTER |
| 30 | IR + Form (31) | Product Master | PRODUCT_MASTER |
| 40 | IR + Form (41) | Bill of Materials | BOM_MASTER / BOM_DETAILS |
| 50 | IR + Form (51) | Demand Forecast | DEMAND_FORECAST |
| 60 | IR + Form (61) | Production Plan | PRODUCTION_PLAN |
| 70 | IR | Material Requirement Plan | VW_MRP_SUMMARY |
| 80 | IR + Form (81) | Purchase Requisition | VW_PR_DASHBOARD |
| 90 | IR + Form (91) | Purchase Order | VW_PO_HEADER |
| 100 | IR + Form (101) | Procurement Tracking | VW_PROCUREMENT_STATUS |
| 110 | IR | Material Planning Report | VW_DEMAND_VS_PLAN + VW_MRP_SUMMARY |
| 120 | IR | Procurement Report | VW_PR_DASHBOARD + VW_PO_HEADER |
| 130 | IR + Chart | Supplier Report | VW_SUPPLIER_PERFORMANCE |
| 140 | IR | PO Report | VW_PO_LINE_DETAIL |

---

## STEP 6 — Application-Level Settings

**Shared Components → Application Definition → Edit**

| Setting | Value |
|---------|-------|
| **Error Handling** | Custom error function |
| **Substitution Strings** | `APP_NAME` = Material Planning & Procurement |
| **Build Options** | Production |
| **Global Notifications** | Enable |

**Security Settings:**
- Authentication: Application Express Accounts
- Session State Protection: Enabled
- Maximum Session Length: 480 minutes (8 hours)
- Maximum Session Idle Time: 120 minutes

---

## STEP 7 — Global Page (Page 0)

Create items and processes on Page 0 that appear on all pages:

### Items on Page 0:
- `P0_USERNAME` — Hidden — Source: `APP_USER`
- `P0_APP_NAME` — Hidden — Source: Static: `MPPMS`

### Navigation Bar Items:
- **Username display:** `APP_USER`
- **Logout link:** `f?p=&APP_ID.:LOGOUT:&SESSION.`

---

## NEXT STEPS (Phase 7-11)

After completing Steps 1-7 above, we build each module's pages:

- **Phase 7:** Masters Module pages (Supplier, Material, Product)
- **Phase 8:** Planning Module pages (BOM, Forecast, Plan, MRP)
- **Phase 9:** Procurement Module pages (PR, PO, Tracking)
- **Phase 10:** Reports Module
- **Phase 11:** Dashboard with KPI cards and charts

Each phase provides exact **page type, region SQL, process code, dynamic actions, and validations**.
