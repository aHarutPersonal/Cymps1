# CMPYS (CoMPare Your Success) - UI Design Prompt

## App Overview
CMPYS is a mobile app that helps users compare their life journey and achievements against historical "idols" (famous personalities like entrepreneurs, scientists, artists). Users set personal goals, track progress, and receive AI-powered mentorship in the voice of their chosen idol.

---

## Core Screens & Functionalities

### 1. Authentication Flow

**Auth Screen** (Sign Up / Sign In)
- Logo branding at top
- Social OAuth buttons (Google, Apple, Twitter)
- Divider with "or continue with"
- Email/password form with validation
- Loading states during authentication
- Error banners for failed auth
- Toggle between Sign Up / Sign In modes

**Splash Screen**
- App logo animation
- Loading indicator

---

### 2. Onboarding Flow

**Profile Setup Screen**
- Welcome messaging
- Form to collect user basic info (name, birthdate)

**Idol Search Screen**
- Search bar with live search (debounced 300ms)
- Suggested search terms (chips): "Entrepreneurs", "Scientists", "Athletes", "Artists", "Leaders"
- Popular searches list (clock icons)
- Search results as idol cards with:
  - Avatar/initials circle
  - Name
  - Primary occupation subtitle
- Empty state when no results found

**Idol Suggestions Screen**
- AI-powered idol recommendations based on user interests
- Grid/list of suggested idol cards
- "Search manually" option

**Idol Confirm Screen**
- Large idol avatar
- Name, birth/death dates, description
- Occupations as tags
- "Confirm Selection" CTA button

**Enriching Screen**
- Loading animation while idol data is being enhanced
- Progress messaging (fetching Wikidata, extracting timeline)
- Animated loading indicators

---

### 3. Intake Wizard (User Readiness Assessment)

- Multi-step wizard with progress bar at top
- One question per screen with navigation (back/next/skip)
- Question types supported:
  - Text input (single line)
  - Multiline text area
  - Single choice (radio-style selection cards)
  - Multi-choice (checkbox-style selection chips)
  - Scale (slider with value labels)
- Category headers for question groups (e.g., "Skills", "Experience", "Goals")
- Error banners for validation issues
- Final step with "Complete" action

---

### 4. Home Screen (Dashboard)

**Header** with greeting and user avatar

**Current Idol Card**:
- Idol avatar/photo
- Name and key dates
- Timeline completeness indicator
- Quick actions row (icons for Chat, Compare, Notes, Plan)

**"At Your Age" Section**:
- Highlighted milestones the idol achieved at user's current age
- Milestone cards with:
  - Category color badge (Career, Education, Personal, etc.)
  - Title and description
  - Age indicator

**Enriching Banner** (shown when timeline data incomplete):
- Progress messaging
- "View Status" link

**Quick Action Buttons**:
- Icon + label format
- Navigate to: Chat, Comparison, Plans, Notes, Achievements

---

### 5. Comparison Screen

**Header** with title "Compare" and idol name

**Overall Progress Ring** (circular progress indicator) with percentage

**Timeline Stats** section:
- User's milestones count
- Idol's milestones at same age count
- Visual comparison

**Category Breakdown Cards**:
- Category icon and name (Career, Education, Skills, Personal, Creativity)
- Progress bar with score
- Color-coded by category

**Strengths Section**:
- Cards highlighting areas where user excels
- Category badge + description

**Gaps Section**:
- Cards showing improvement areas
- Suggested action items
- Priority indicator

**Incomplete Data Notice** (when applicable):
- Banner explaining data limitations
- Link to complete profile

**AI-Generated Insights** section (if available):
- Summary analysis cards
- Key takeaways

---

### 6. Plans Screen (12-Week Development Plan)

**Header** with title, idol context, current week indicator

**Generating State**:
- Animated "thinking" indicator with streaming text
- Progress messaging

**No Plan State**:
- Empty state illustration
- "Generate Plan" CTA button

**Plan Content**:
- Week selector/navigator (tabs or horizontal scroll)
- Date range display
- Weekly Goal Card with progress ring
- Task Cards for each plan item:
  - Checkbox to mark completion
  - Title and description
  - Category color badge
  - Lesson/link indicator (if has detailed lesson)
  - Tap to expand/view detail
- Empty Week state for weeks without tasks

**Regenerate Dialog**:
- Confirmation modal
- Warning about losing progress
- Cancel/Confirm buttons

**Task Detail Screen** (when tapping a task):
- Full task description
- Learning resources
- Action items

**In-App Lesson Screen**:
- Content display
- Progress tracking
- Mark as complete

---

### 7. Chat Screen (AI Mentor Conversation)

**Header** with idol avatar and name

**Message List**:
- User messages (right-aligned, brand color background)
- Idol messages (left-aligned, surface color background)
  - Idol avatar beside messages
  - Text-only rendering (no markdown)
  - Timestamp

**Streaming Bubble** for AI responses in progress:
- Animated text appearing character-by-character
- Typing indicator (three animated dots)

**Typing Indicator** (shown while waiting for response):
- Idol avatar + animated dots

**Quick Action Chips** (suggested prompts):
- Horizontal scrollable row
- Pre-defined conversation starters
- "Advice for today", "My goals", "Tell me about your journey"

**Empty Chat State**:
- Welcome message from idol persona
- Suggested first questions

**Input Area**:
- Text field with placeholder
- Send button
- Disabled state when AI is responding

**LLM Unavailable Banner** (503 error handling):
- Warning message
- Retry option

---

### 8. Notes Screen

**Header** with title and add button

**Search Bar** for filtering notes

**Notes List**:
- Note cards with:
  - Title
  - Preview snippet
  - Date
  - Attachment badges (image/doc indicators)

**Empty State**:
- Illustration
- "Add your first note" CTA

**Add Note Screen**:
- Title input
- Content multiline input
- Save button in app bar

**Note Detail Screen**:
- View mode with full content
- Edit mode toggle
- Delete confirmation dialog
- Attachment display
- Date/time metadata

---

### 9. Achievements Screen

**Header** with title and add button

**Achievements List**:
- Achievement cards with:
  - Category icon and color badge
  - Title
  - Date achieved
  - Description preview

**Empty State**:
- Motivational empty state
- "Log your first achievement" CTA

**Add Achievement Screen**:
- Category selector (grid of category chips)
- Title input
- Description multiline input
- Date picker
- Evidence/details section
- Save button

**Achievement Detail Screen**:
- Full details display
- Category highlight
- Delete option

**Achievement Categories:**
- Career
- Education
- Skills
- Personal
- Creativity
- Health
- Finance

---

### 10. Profile Screen

**Header** with "Profile" title and settings gear icon

**Profile Card**:
- Large avatar with gradient background
- Full name
- Email
- Stats row: Age | Interests count
- "Edit Profile" button

**Interests Section**:
- Horizontal wrap of interest tags/chips

**Progress Overview Card** (navigates to Comparison):
- Progress ring with percentage
- "Overall Progress" label
- Current idol comparison context
- Chevron indicator

---

### 11. Settings Screen

**Navigation** with back button and "Settings" title

**Grouped Settings Cards:**

Account section:
- Edit Profile (user icon)
- Change Idol (users icon)
- Notifications (bell icon)

Preferences section:
- Appearance with current value (e.g., "Dark")
- Language with current value (e.g., "English")

Support section:
- Help Center
- Privacy Policy
- Terms of Service

**Sign Out** card (red icon, destructive action)

**App Version** footer text

---

## Reusable Components / Design System

| Component | Description |
|-----------|-------------|
| Cards | Rounded containers with surface background, subtle border |
| Buttons | Primary (gradient/brand), Secondary (outlined), Icon-only |
| Chips/Tags | Category badges, selection chips, interest tags |
| Progress Ring | Circular percentage indicator |
| Progress Bar | Horizontal bar with fill |
| Text Fields | Standard input, search field, multiline textarea |
| App Bar | Custom header with optional subtitle, actions |
| List Tile Cards | Icon + title + subtitle + chevron pattern |
| Loading States | Centered spinner with message |
| Empty States | Illustration + message + CTA |
| Error States | Banner style with retry option |
| Avatars | Initials avatar (gradient bg), Image avatar (for idols) |

---

## Design Aesthetic Notes

- **Theme**: Dark mode primary
- **Colors**: Category-specific (Career=Blue, Education=Purple, Skills=Green, Personal=Orange, Creativity=Pink)
- **Typography**: Modern sans-serif, clear hierarchy (H1, H2, H3, H4, Body, Caption)
- **Spacing**: Consistent padding system (8, 12, 16, 20, 24, 32px)
- **Animations**: Subtle micro-interactions, typing indicators, progress animations
- **Icons**: Line-style SVG icons (Lucide/Feather style)

---

## Key User Flows

1. **New User**: Auth → Profile Setup → Idol Selection → Intake Wizard → Home
2. **Daily Use**: Home → Chat/Compare/Plans → Track achievements → Notes
3. **Plan Generation**: Request plan → AI thinking animation → View 12-week plan → Complete tasks
4. **Idol Change**: Settings → Change Idol → Search/Suggest → Confirm → Re-enrichment

---

## Navigation Structure

```
├── Auth (unauthenticated)
│   ├── Splash
│   └── Auth Screen
│
├── Onboarding (first-time user)
│   ├── Profile Setup
│   ├── Idol Search / Suggest
│   ├── Idol Confirm
│   ├── Enriching
│   └── Intake Wizard
│
└── Main App (bottom tab navigation)
    ├── Home (Dashboard)
    ├── Plans
    ├── Chat
    ├── Notes
    └── Profile
        └── Settings
```

Secondary screens accessible from main:
- Comparison (from Home/Profile)
- Achievements (from Home)
- Task Detail / Lessons (from Plans)
- Note Detail (from Notes)
- Achievement Detail (from Achievements)
