// ===== CMPYS Design Prototype - Light Theme Screens + UX Improvements =====

const app = document.getElementById('app');
const bottomNav = document.getElementById('bottomNav');
let currentScreen = 'today';

function navigate(tab) {
  currentScreen = tab;
  document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));
  const btn = document.querySelector(`[data-tab="${tab}"]`);
  if (btn) btn.classList.add('active');
  showScreen(tab);
}

function showScreen(screen) {
  currentScreen = screen;
  const needsNav = ['today','plan','mentor','library','profile'].includes(screen);
  document.querySelector('.device-frame').classList.toggle('hide-nav', !needsNav);
  if (needsNav) {
    document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));
    const navBtn = document.querySelector(`[data-tab="${screen}"]`);
    if (navBtn) navBtn.classList.add('active');
  }
  app.scrollTop = 0;
  app.innerHTML = screens[screen] || '<div style="padding:40px;text-align:center;color:var(--text-tertiary)">Screen not found</div>';
}

const svg = {
  back: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M15 18l-6-6 6-6"/></svg>',
  chevron: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M9 18l6-6-6-6"/></svg>',
  check: '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3"><path d="M20 6L9 17l-5-5"/></svg>',
  fire: '<svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M12 23c-4.97 0-9-3.58-9-8 0-2.52 1.17-5.13 2.5-6.87.44-.57 1.2-.72 1.81-.37.61.36.85 1.1.58 1.74C7.13 11.38 7 13.3 7 15c0 2.76 2.24 5 5 5s5-2.24 5-5c0-1.7-.13-3.62-.89-5.5-.27-.64-.03-1.38.58-1.74.61-.35 1.37-.2 1.81.37C20.83 9.87 22 12.48 22 15c0 4.42-4.03 8-9 8z"/></svg>',
  bell: '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 8A6 6 0 006 8c0 7-3 9-3 9h18s-3-2-3-9M13.73 21a2 2 0 01-3.46 0"/></svg>',
  compass: '<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><polygon points="16.24 7.76 14.12 14.12 7.76 16.24 9.88 9.88 16.24 7.76" fill="currentColor"/></svg>',
  lock: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0110 0v4"/></svg>',
  play: '<svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor"><polygon points="5 3 19 12 5 21"/></svg>',
  lightning: '<svg width="16" height="16" viewBox="0 0 24 24" fill="var(--accent)"><polygon points="13 2 3 14 12 14 11 22 21 10 12 10"/></svg>',
  book: '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 19.5A2.5 2.5 0 016.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 014 19.5v-15A2.5 2.5 0 016.5 2z"/></svg>',
  sparkle: '<svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2l2.4 7.2L22 12l-7.6 2.8L12 22l-2.4-7.2L2 12l7.6-2.8z"/></svg>',
  search: '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="8"/><path d="M21 21l-4.35-4.35"/></svg>',
  send: '<svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor"><path d="M2.01 21L23 12 2.01 3 2 10l15 2-15 2z"/></svg>',
  heart: '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M20.84 4.61a5.5 5.5 0 00-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 00-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 000-7.78z"/></svg>',
  bookmark: '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M19 21l-7-5-7 5V5a2 2 0 012-2h10a2 2 0 012 2z"/></svg>',
  info: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4M12 8h.01"/></svg>',
  gear: '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 00.33 1.82l.06.06a2 2 0 01-2.83 2.83l-.06-.06a1.65 1.65 0 00-1.82-.33 1.65 1.65 0 00-1 1.51V21a2 2 0 01-4 0v-.09A1.65 1.65 0 009 19.4a1.65 1.65 0 00-1.82.33l-.06.06a2 2 0 01-2.83-2.83l.06-.06A1.65 1.65 0 004.68 15a1.65 1.65 0 00-1.51-1H3a2 2 0 010-4h.09A1.65 1.65 0 004.6 9a1.65 1.65 0 00-.33-1.82l-.06-.06a2 2 0 012.83-2.83l.06.06A1.65 1.65 0 009 4.68a1.65 1.65 0 001-1.51V3a2 2 0 014 0v.09a1.65 1.65 0 001 1.51 1.65 1.65 0 001.82-.33l.06-.06a2 2 0 012.83 2.83l-.06.06A1.65 1.65 0 0019.4 9a1.65 1.65 0 001.51 1H21a2 2 0 010 4h-.09a1.65 1.65 0 00-1.51 1z"/></svg>',
  plus: '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 5v14M5 12h14"/></svg>',
  trending: '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="var(--mint)" stroke-width="2"><polyline points="23 6 13.5 15.5 8.5 10.5 1 18"/><polyline points="17 6 23 6 23 12"/></svg>',
  briefcase: '<svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><rect x="2" y="7" width="20" height="14" rx="2"/><path d="M16 7V5a2 2 0 00-2-2h-4a2 2 0 00-2 2v2"/></svg>',
  graduation: '<svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M12 3L1 9l4 2.18v6L12 21l7-3.82v-6L23 9 12 3zm0 12.55L6 12.72v3.73l6 3.27 6-3.27v-3.73L12 15.55z"/></svg>',
  wrench: '<svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M22.7 19l-9.1-9.1c.9-2.3.4-5-1.5-6.9-2-2-5-2.4-7.4-1.3L9 6 6 9 1.6 4.7C.4 7.1.9 10.1 2.9 12.1c1.9 1.9 4.6 2.4 6.9 1.5l9.1 9.1c.4.4 1 .4 1.4 0l2.3-2.3c.5-.5.5-1.1.1-1.4z"/></svg>',
  heartIcon: '<svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z"/></svg>',
  palette: '<svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2C6.49 2 2 6.49 2 12s4.49 10 10 10c1.38 0 2.5-1.12 2.5-2.5 0-.61-.23-1.21-.64-1.67-.38-.45-.6-1.01-.6-1.58 0-1.38 1.12-2.5 2.5-2.5H16c3.31 0 6-2.69 6-6 0-4.96-4.49-9-10-9zM6.5 13c-.83 0-1.5-.67-1.5-1.5S5.67 10 6.5 10 8 10.67 8 11.5 7.33 13 6.5 13zm3-4C8.67 9 8 8.33 8 7.5S8.67 6 9.5 6s1.5.67 1.5 1.5S10.33 9 9.5 9zm5 0c-.83 0-1.5-.67-1.5-1.5S13.67 6 14.5 6s1.5.67 1.5 1.5S15.33 9 14.5 9zm3 4c-.83 0-1.5-.67-1.5-1.5s.67-1.5 1.5-1.5 1.5.67 1.5 1.5-.67 1.5-1.5 1.5z"/></svg>',
  video: '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polygon points="23 7 16 12 23 17 23 7"/><rect x="1" y="5" width="15" height="14" rx="2"/></svg>',
};

const screens = {};

// ===== AUTH =====
screens.auth = `
<div class="grid-bg" style="min-height:100%;display:flex;flex-direction:column;padding:20px 20px 40px;">
  <div style="flex:1;display:flex;flex-direction:column;justify-content:center;">
    <div style="text-align:center;margin-bottom:40px;">
      <div style="width:64px;height:64px;margin:0 auto 14px;border-radius:var(--r20);background:linear-gradient(135deg,var(--accent),var(--peach));display:flex;align-items:center;justify-content:center;box-shadow:var(--glow-accent);">
        ${svg.compass}
      </div>
      <div style="font-family:var(--font-mono);font-size:11px;font-weight:700;letter-spacing:0.8px;color:var(--mint);margin-bottom:4px;">CMPYS</div>
      <div style="font-size:22px;font-weight:800;color:var(--text-primary);">Compare Your Success</div>
      <div style="font-size:13px;color:var(--text-secondary);margin-top:4px;">See where you stand. Learn what they did.</div>
    </div>
    <div style="display:flex;flex-direction:column;gap:10px;margin-bottom:20px;">
      <button class="btn-secondary" style="gap:10px;"><svg width="18" height="18" viewBox="0 0 24 24"><path d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92a5.06 5.06 0 01-2.2 3.32v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.1z" fill="#4285F4"/><path d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" fill="#34A853"/><path d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" fill="#FBBC05"/><path d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" fill="#EA4335"/></svg> Continue with Google</button>
      <button class="btn-secondary"><svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z"/></svg> Continue with Apple</button>
    </div>
    <div style="display:flex;align-items:center;gap:12px;margin-bottom:20px;">
      <div style="flex:1;height:1px;background:var(--border);"></div>
      <span style="font-size:11px;color:var(--text-tertiary);">or</span>
      <div style="flex:1;height:1px;background:var(--border);"></div>
    </div>
    <div style="display:flex;flex-direction:column;gap:12px;">
      <input class="input-field" type="email" placeholder="Email address">
      <input class="input-field" type="password" placeholder="Password">
      <button class="btn-primary" style="margin-top:4px;">Sign In</button>
    </div>
    <div style="text-align:center;margin-top:16px;">
      <span style="font-size:13px;color:var(--text-tertiary);">Don't have an account? </span>
      <a href="#" onclick="showScreen('onboarding');return false" style="font-size:13px;color:var(--accent);font-weight:600;text-decoration:none;">Sign Up</a>
    </div>
  </div>
</div>`;

// ===== ONBOARDING / PROFILE SETUP =====
screens.onboarding = `
<div class="grid-bg" style="min-height:100%;display:flex;flex-direction:column;padding:20px 20px 40px;">
  <div style="display:flex;align-items:center;gap:12px;margin-bottom:28px;">
    <button class="btn-icon" onclick="showScreen('auth')" style="border:none;">${svg.back}</button>
    <div style="flex:1;display:flex;align-items:center;gap:8px;">
      <div style="flex:1;height:4px;background:var(--surface-2);border-radius:var(--rFull);overflow:hidden;">
        <div style="width:33%;height:100%;background:var(--accent);border-radius:var(--rFull);"></div>
      </div>
      <span style="font-family:var(--font-mono);font-size:11px;color:var(--text-tertiary);">1/3</span>
    </div>
  </div>
  <div style="flex:1;display:flex;flex-direction:column;justify-content:center;">
    <div style="text-align:center;margin-bottom:32px;">
      <div style="width:80px;height:80px;margin:0 auto 16px;border-radius:50%;background:var(--accent-muted);display:flex;align-items:center;justify-content:center;animation:float 3s ease-in-out infinite;">
        <svg width="36" height="36" viewBox="0 0 24 24" fill="var(--accent)" stroke="none"><path d="M15 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm-9-2V7H4v3H1v2h3v3h2v-3h3v-2H6zm9 4c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z"/></svg>
      </div>
      <div style="font-size:24px;font-weight:800;margin-bottom:6px;">Set up your profile</div>
      <div style="font-size:14px;color:var(--text-secondary);line-height:1.5;">Tell us about yourself so we can find the perfect mentor match.</div>
    </div>
    <div style="display:flex;flex-direction:column;gap:16px;">
      <div>
        <label style="font-size:12px;font-weight:600;color:var(--text-secondary);margin-bottom:6px;display:block;">Full Name</label>
        <input class="input-field" placeholder="Enter your name">
      </div>
      <div>
        <label style="font-size:12px;font-weight:600;color:var(--text-secondary);margin-bottom:6px;display:block;">Date of Birth</label>
        <input class="input-field" type="date" value="1998-06-15">
      </div>
      <div>
        <label style="font-size:12px;font-weight:600;color:var(--text-secondary);margin-bottom:8px;display:block;">What drives you?</label>
        <div style="display:flex;flex-wrap:wrap;gap:8px;">
          <span class="chip chip-accent">Entrepreneurship</span>
          <span class="chip">Science</span>
          <span class="chip">Sports</span>
          <span class="chip chip-mint">Arts</span>
          <span class="chip">Leadership</span>
          <span class="chip">Technology</span>
        </div>
      </div>
    </div>
  </div>
  <button class="btn-primary" onclick="showScreen('idol-suggest')">Continue</button>
</div>`;

// ===== IDOL SEARCH =====
screens['idol-search'] = `
<div class="grid-bg" style="min-height:100%;padding:20px 20px 40px;">
  <div style="display:flex;align-items:center;gap:12px;margin-bottom:20px;">
    <button class="btn-icon" onclick="showScreen('idol-suggest')">${svg.back}</button>
    <div style="flex:1;position:relative;">
      <div style="position:absolute;left:14px;top:50%;transform:translateY(-50%);color:var(--text-tertiary);">${svg.search}</div>
      <input class="input-field" style="padding-left:40px;" placeholder="Search titan, domain, or era..." autofocus>
    </div>
  </div>
  <div class="h-scroll" style="margin-bottom:20px;">
    <span class="chip chip-mint">Entrepreneurs</span>
    <span class="chip">Scientists</span>
    <span class="chip">Athletes</span>
    <span class="chip">Artists</span>
    <span class="chip">Leaders</span>
  </div>
  <div style="display:flex;flex-direction:column;gap:10px;">
    <div class="card" style="display:flex;align-items:center;gap:14px;cursor:pointer;" onclick="showScreen('idol-confirm')">
      <div class="avatar" style="background:linear-gradient(135deg,#1E40AF,#3B82F6);">WB</div>
      <div style="flex:1;"><div style="font-weight:700;font-size:15px;">Warren Buffett</div><div style="font-size:12px;color:var(--text-tertiary);">Investor & Philanthropist</div></div>
      <div style="font-family:var(--font-mono);font-size:11px;color:var(--mint);font-weight:700;">98%</div>
    </div>
    <div class="card" style="display:flex;align-items:center;gap:14px;cursor:pointer;">
      <div class="avatar" style="background:linear-gradient(135deg,#7C3AED,#8B5CF6);">GH</div>
      <div style="flex:1;"><div style="font-weight:700;font-size:15px;">Grace Hopper</div><div style="font-size:12px;color:var(--text-tertiary);">Computer Scientist</div></div>
      <div style="font-family:var(--font-mono);font-size:11px;color:var(--mint);font-weight:700;">94%</div>
    </div>
    <div class="card" style="display:flex;align-items:center;gap:14px;cursor:pointer;">
      <div class="avatar" style="background:linear-gradient(135deg,#B45309,#F59E0B);">MA</div>
      <div style="flex:1;"><div style="font-weight:700;font-size:15px;">Marcus Aurelius</div><div style="font-size:12px;color:var(--text-tertiary);">Philosopher Emperor</div></div>
      <div style="font-family:var(--font-mono);font-size:11px;color:var(--mint);font-weight:700;">91%</div>
    </div>
    <div class="card" style="display:flex;align-items:center;gap:14px;cursor:pointer;">
      <div class="avatar" style="background:linear-gradient(135deg,#0F766E,#14B8A6);">SJ</div>
      <div style="flex:1;"><div style="font-weight:700;font-size:15px;">Steve Jobs</div><div style="font-size:12px;color:var(--text-tertiary);">Visionary Entrepreneur</div></div>
      <div style="font-family:var(--font-mono);font-size:11px;color:var(--mint);font-weight:700;">89%</div>
    </div>
  </div>
</div>`;

// ===== IDOL SUGGEST =====
screens['idol-suggest'] = `
<div class="grid-bg" style="min-height:100%;padding:20px 20px 96px;">
  <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:4px;">
    <button class="btn-icon" onclick="showScreen('onboarding')">${svg.back}</button>
    <button class="btn-icon">${svg.info}</button>
  </div>
  <div class="section-label" style="margin-bottom:4px;">Target Selection</div>
  <div class="section-title" style="margin-bottom:16px;">Choose your North Star</div>
  <div style="position:relative;margin-bottom:20px;">
    <div style="position:absolute;left:14px;top:50%;transform:translateY(-50%);color:var(--text-tertiary);">${svg.search}</div>
    <input class="input-field" style="padding-left:40px;height:52px;" placeholder="Search titan, domain, or era...">
  </div>
  <div style="display:flex;flex-direction:column;gap:14px;margin-bottom:20px;">
    <div class="card-elevated" style="border:2px solid var(--mint);box-shadow:var(--shadow-md),var(--glow-mint);cursor:pointer;" onclick="showScreen('idol-confirm')">
      <div style="display:flex;align-items:center;gap:14px;margin-bottom:12px;">
        <div class="avatar-lg avatar">WB</div>
        <div style="flex:1;"><div style="font-weight:800;font-size:18px;">Warren Buffett</div><div style="font-size:12px;color:var(--text-tertiary);">1930 - Present &middot; Investor</div></div>
        <span class="chip chip-mint" style="font-size:10px;">Best Match</span>
      </div>
      <div style="font-size:13px;color:var(--text-secondary);line-height:1.55;background:var(--surface-2);padding:12px;border-radius:var(--r12);border-left:3px solid var(--mint);">Your interest in entrepreneurship and long-term value investing aligns with Buffett's philosophy of patient, disciplined growth.</div>
    </div>
    <div class="card" style="cursor:pointer;" onclick="showScreen('idol-confirm')">
      <div style="display:flex;align-items:center;gap:14px;margin-bottom:12px;">
        <div class="avatar-lg avatar" style="background:linear-gradient(135deg,#7C3AED,#8B5CF6);">GH</div>
        <div style="flex:1;"><div style="font-weight:800;font-size:18px;">Grace Hopper</div><div style="font-size:12px;color:var(--text-tertiary);">1906 - 1992 &middot; Computer Scientist</div></div>
      </div>
      <div style="font-size:13px;color:var(--text-secondary);line-height:1.55;background:var(--surface-2);padding:12px;border-radius:var(--r12);border-left:3px solid var(--cat-education);">Your technology drive and desire to build systems mirrors Hopper's pioneering approach to making complex ideas accessible.</div>
    </div>
    <div class="card" style="cursor:pointer;" onclick="showScreen('idol-confirm')">
      <div style="display:flex;align-items:center;gap:14px;margin-bottom:12px;">
        <div class="avatar-lg avatar" style="background:linear-gradient(135deg,#B45309,#F59E0B);">MA</div>
        <div style="flex:1;"><div style="font-weight:800;font-size:18px;">Marcus Aurelius</div><div style="font-size:12px;color:var(--text-tertiary);">121 - 180 AD &middot; Philosopher</div></div>
      </div>
      <div style="font-size:13px;color:var(--text-secondary);line-height:1.55;background:var(--surface-2);padding:12px;border-radius:var(--r12);border-left:3px solid var(--cat-personal);">Your focus on personal discipline and strategic thinking resonates with Aurelius's Stoic framework for leadership.</div>
    </div>
  </div>
  <button class="btn-ghost" style="font-size:13px;color:var(--accent);">${svg.search} Search Manually</button>
</div>`;

// ===== IDOL CONFIRM =====
screens['idol-confirm'] = `
<div style="min-height:100%;background:var(--surface);">
  <div style="height:400px;background:linear-gradient(135deg,#1E40AF,#3B82F6);position:relative;display:flex;align-items:center;justify-content:center;">
    <div style="font-size:72px;font-weight:800;color:rgba(255,255,255,0.15);">WB</div>
    <div style="position:absolute;top:50px;left:20px;"><button class="btn-icon" style="background:rgba(0,0,0,0.3);border:none;color:white;" onclick="showScreen('idol-suggest')">${svg.back}</button></div>
    <div style="position:absolute;bottom:0;left:0;right:0;padding:0 20px 24px;background:linear-gradient(transparent,rgba(0,0,0,0.7));">
      <div style="font-family:var(--font-mono);font-size:11px;color:var(--mint);letter-spacing:0.8px;margin-bottom:6px;">Selected Titan</div>
      <div style="font-family:var(--font-reading);font-size:32px;font-weight:700;font-style:italic;color:white;line-height:1.1;">Warren Buffett</div>
      <div style="font-size:12px;color:rgba(255,255,255,0.7);margin-top:4px;">Investor &middot; Philanthropist</div>
    </div>
  </div>
  <div class="grid-bg" style="padding:20px 20px 40px;">
    <div style="display:grid;grid-template-columns:1fr 1fr 1fr;gap:1px;background:var(--border);border-radius:var(--r12);overflow:hidden;margin-bottom:20px;">
      <div style="background:var(--surface);padding:14px 12px;text-align:center;"><div style="font-size:20px;font-weight:800;color:var(--text-primary);">95%</div><div style="font-family:var(--font-mono);font-size:10px;color:var(--text-tertiary);letter-spacing:0.5px;">ALIGNMENT</div></div>
      <div style="background:var(--surface);padding:14px 12px;text-align:center;"><div style="font-size:20px;font-weight:800;color:var(--text-primary);">12 Wks</div><div style="font-family:var(--font-mono);font-size:10px;color:var(--text-tertiary);letter-spacing:0.5px;">DURATION</div></div>
      <div style="background:var(--surface);padding:14px 12px;text-align:center;"><div style="font-size:20px;font-weight:800;color:var(--text-primary);">High</div><div style="font-family:var(--font-mono);font-size:10px;color:var(--text-tertiary);letter-spacing:0.5px;">COMPLEXITY</div></div>
    </div>
    <div style="font-family:var(--font-mono);font-size:11px;color:var(--mint);letter-spacing:0.8px;margin-bottom:8px;">Strategic Fit</div>
    <div style="font-size:14px;color:var(--text-secondary);line-height:1.65;margin-bottom:20px;">Your entrepreneurial drive and focus on value creation matches Buffett's proven framework for compound growth and disciplined decision-making.</div>
    <div style="display:flex;flex-direction:column;gap:10px;margin-bottom:28px;">
      <div class="card" style="display:flex;align-items:center;gap:14px;">
        <div style="width:44px;height:44px;border-radius:var(--r12);background:var(--mint-muted);display:flex;align-items:center;justify-content:center;flex-shrink:0;">${svg.trending}</div>
        <div><div style="font-weight:700;font-size:14px;">12-Week Allocation Protocol</div><div style="font-size:12px;color:var(--text-tertiary);">Personalized growth plan</div></div>
      </div>
      <div class="card" style="display:flex;align-items:center;gap:14px;">
        <div style="width:44px;height:44px;border-radius:var(--r12);background:var(--accent-muted);display:flex;align-items:center;justify-content:center;flex-shrink:0;"><svg width="22" height="22" viewBox="0 0 24 24" fill="var(--accent)"><path d="M20 2H4c-1.1 0-2 .9-2 2v18l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2z"/></svg></div>
        <div><div style="font-weight:700;font-size:14px;">Unlimited Mentor Consultation</div><div style="font-size:12px;color:var(--text-tertiary);">AI-powered guidance</div></div>
      </div>
    </div>
    <div style="display:flex;flex-direction:column;gap:10px;">
      <button class="btn-primary" onclick="showScreen('intake')">Confirm Strategic Idol</button>
      <button class="btn-ghost" onclick="showScreen('idol-suggest')">Choose Different Idol</button>
    </div>
  </div>
</div>`;

// ===== AGENTIC INTAKE =====
screens.intake = `
<div class="grid-bg" style="min-height:100%;padding:20px 20px 40px;">
  <div style="display:flex;align-items:center;gap:12px;margin-bottom:24px;">
    <button class="btn-icon" onclick="showScreen('idol-confirm')">${svg.back}</button>
    <div class="section-title" style="font-size:20px;">Quick Setup</div>
  </div>
  <div class="trust-banner">
    <div class="trust-banner-icon">${svg.info}</div>
    <div class="trust-banner-text">Your answers personalize the mentor experience. This data is encrypted, never shared, and deletable from Settings.</div>
  </div>
  <div style="display:flex;flex-direction:column;gap:20px;">
    <div>
      <label style="font-size:12px;font-weight:600;color:var(--text-secondary);margin-bottom:6px;display:block;">How old are you?</label>
      <input class="input-field" type="number" placeholder="28" value="28">
    </div>
    <div>
      <label style="font-size:12px;font-weight:600;color:var(--text-secondary);margin-bottom:6px;display:block;">Current financial status</label>
      <div style="display:flex;gap:8px;flex-wrap:wrap;">
        <span class="chip chip-accent">Building wealth</span>
        <span class="chip">Stabilizing</span>
        <span class="chip">Starting from scratch</span>
      </div>
    </div>
    <div>
      <label style="font-size:12px;font-weight:600;color:var(--text-secondary);margin-bottom:8px;display:block;">Key interests</label>
      <div style="display:flex;flex-wrap:wrap;gap:8px;">
        <span class="chip chip-mint">Investing</span>
        <span class="chip chip-accent">Technology</span>
        <span class="chip">Reading</span>
        <span class="chip">Philosophy</span>
        <span class="chip">Fitness</span>
        <span class="chip">Writing</span>
        <span class="chip">Leadership</span>
      </div>
    </div>
  </div>
  <div style="margin-top:28px;">
    <button class="btn-primary" onclick="showScreen('interview')">${svg.sparkle} Generate Recommendations</button>
  </div>
</div>`;

// ===== INTERVIEW =====
screens.interview = `
<div class="grid-bg" style="min-height:100%;display:flex;flex-direction:column;">
  <div style="padding:20px 20px 12px;display:flex;align-items:center;gap:12px;">
    <button class="btn-icon" onclick="showScreen('intake')">${svg.back}</button>
    <div class="avatar-sm avatar">WB</div>
    <div style="flex:1;"><div style="font-weight:700;font-size:14px;">Warren Buffett</div><div style="display:flex;align-items:center;gap:6px;"><div style="width:6px;height:6px;border-radius:50%;background:var(--peach);"></div><span style="font-size:11px;color:var(--peach);">Thinking...</span></div></div>
    <button class="btn-ghost" style="width:auto;padding:6px 12px;font-size:12px;color:var(--text-tertiary);" onclick="showScreen('results')">Skip</button>
  </div>
  <div style="padding:0 20px 8px;display:flex;gap:4px;">
    <div style="flex:1;height:3px;border-radius:var(--rFull);background:var(--mint);"></div>
    <div style="flex:1;height:3px;border-radius:var(--rFull);background:var(--mint);"></div>
    <div style="flex:1;height:3px;border-radius:var(--rFull);background:var(--accent);animation:pulse 1.5s infinite;"></div>
    <div style="flex:1;height:3px;border-radius:var(--rFull);background:var(--surface-2);"></div>
    <div style="flex:1;height:3px;border-radius:var(--rFull);background:var(--surface-2);"></div>
  </div>
  <div style="flex:1;padding:16px 20px 0;overflow-y:auto;">
    <div style="display:flex;gap:10px;margin-bottom:16px;">
      <div class="avatar-sm avatar" style="flex-shrink:0;margin-top:2px;">WB</div>
      <div style="background:var(--surface);border:1px solid var(--border);border-radius:6px 20px 20px 20px;padding:14px;max-width:80%;box-shadow:var(--shadow-sm);">
        <div style="font-size:14px;line-height:1.55;color:var(--text-primary);">I like your ambition. When I was your age, I had just taken control of Berkshire Hathaway — most people thought I was crazy. What's the biggest risk you've taken recently?</div>
      </div>
    </div>
    <div style="display:flex;justify-content:flex-end;margin-bottom:16px;">
      <div style="background:var(--accent);border-radius:20px 6px 20px 20px;padding:14px;max-width:75%;box-shadow:var(--shadow-sm);">
        <div style="font-size:14px;line-height:1.55;color:white;font-weight:500;">I recently left a stable corporate job to start my own consulting practice. It was terrifying but I felt I had to.</div>
      </div>
    </div>
    <div style="display:flex;gap:10px;margin-bottom:16px;">
      <div class="avatar-sm avatar" style="flex-shrink:0;margin-top:2px;">WB</div>
      <div style="background:var(--surface);border:1px solid var(--border);border-radius:6px 20px 20px 20px;padding:14px 20px;display:flex;align-items:center;gap:2px;">
        <span class="typing-dot"></span><span class="typing-dot"></span><span class="typing-dot"></span>
      </div>
    </div>
  </div>
  <div style="padding:20px;border-top:1px solid var(--border);background:var(--bg);display:flex;gap:8px;align-items:center;">
    <input class="input-field" style="flex:1;" placeholder="Wait for response..." disabled>
    <button style="width:48px;height:48px;border-radius:50%;background:var(--surface-2);border:none;display:flex;align-items:center;justify-content:center;cursor:not-allowed;" disabled><span style="color:var(--text-tertiary);">${svg.send}</span></button>
  </div>
</div>`;

// ===== RESULTS =====
screens.results = `
<div class="grid-bg" style="min-height:100%;padding:20px 20px 40px;">
  <div style="display:flex;align-items:center;gap:12px;margin-bottom:20px;">
    <button class="btn-icon" onclick="showScreen('interview')">${svg.back}</button>
    <div class="section-title" style="font-size:20px;">Mirror Analysis</div>
  </div>
  <div class="trust-banner">
    <div class="trust-banner-icon">${svg.info}</div>
    <div class="trust-banner-text">This comparison is AI-generated based on public data. Verify key facts before making major decisions.</div>
  </div>
  <div class="card-elevated" style="text-align:center;margin-bottom:20px;">
    <div style="font-family:var(--font-mono);font-size:11px;color:var(--text-tertiary);letter-spacing:0.8px;margin-bottom:12px;">YOUR POSITION AT 28</div>
    <div class="progress-ring-container" style="margin:0 auto 16px;">
      <svg width="140" height="140" class="progress-ring"><circle cx="70" cy="70" r="58" stroke="var(--surface-2)" stroke-width="12" fill="none"/><circle cx="70" cy="70" r="58" stroke="var(--accent)" stroke-width="12" fill="none" stroke-linecap="round" stroke-dasharray="364.4" stroke-dashoffset="127.5" style="transform:rotate(-90deg);transform-origin:center;"/></svg>
      <div style="position:absolute;display:flex;flex-direction:column;align-items:center;"><span style="font-size:36px;font-weight:900;color:var(--text-primary);">65%</span><span style="font-family:var(--font-mono);font-size:10px;color:var(--text-tertiary);letter-spacing:0.8px;">SYNC</span></div>
    </div>
    <div style="font-size:14px;color:var(--text-secondary);">You've covered 65% of Buffett's milestones at your age</div>
  </div>
  <div style="font-weight:700;font-size:15px;margin-bottom:12px;">Category Breakdown</div>
  <div style="display:flex;flex-direction:column;gap:8px;margin-bottom:24px;">
    ${['Career|78|cat-career|briefcase','Education|90|cat-education|graduation','Skills|55|cat-skills|wrench','Personal|60|cat-personal|heartIcon','Creativity|42|cat-creativity|palette'].map(c=>{const[n,v,cl,ic]=c.split('|');return`<div class="card-compact" style="display:flex;align-items:center;gap:12px;"><span class="cat-badge ${cl}">${svg[ic]} ${n}</span><div style="flex:1;"><div class="progress-bar"><div class="progress-bar-fill" style="width:${v}%;background:var(--${cl});"></div></div></div><span style="font-family:var(--font-mono);font-size:13px;font-weight:700;color:var(--${cl});">${v}%</span></div>`}).join('')}
  </div>
  <div style="margin-bottom:24px;">
    <div style="font-weight:700;font-size:15px;margin-bottom:10px;color:var(--red);">Key Gaps</div>
    <div style="display:flex;flex-direction:column;gap:8px;">
      <div class="card" style="border-left:3px solid var(--red);padding:12px 16px;"><div style="font-weight:600;font-size:13px;margin-bottom:3px;">No published thought leadership</div><div style="font-size:12px;color:var(--text-tertiary);">Buffett had written 12 shareholder letters by 28. <a href="#" onclick="showScreen('plan');return false" style="color:var(--accent);font-weight:600;">Start writing in Week 3 &rarr;</a></div></div>
      <div class="card" style="border-left:3px solid var(--red);padding:12px 16px;"><div style="font-weight:600;font-size:13px;margin-bottom:3px;">Limited network capital</div><div style="font-size:12px;color:var(--text-tertiary);">Build mentor relationships across industries. <a href="#" onclick="showScreen('plan');return false" style="color:var(--accent);font-weight:600;">See Week 4 plan &rarr;</a></div></div>
    </div>
  </div>
  <div style="margin-bottom:24px;">
    <div class="section-label" style="margin-bottom:4px;">Strategic Blueprint</div>
    <div style="font-size:20px;font-weight:800;margin-bottom:14px;">Your Quarterly Blueprint</div>
    <div style="display:flex;flex-direction:column;gap:10px;">
      <div class="card" style="border-left:3px solid var(--mint);"><div style="font-family:var(--font-mono);font-size:10px;color:var(--mint);margin-bottom:6px;">Q1 - FOUNDATION</div><div style="font-weight:700;font-size:14px;margin-bottom:3px;">Build the Base</div><div style="font-size:12px;color:var(--text-secondary);line-height:1.55;">Establish daily reading habit, start decision journal, join one mastermind group.</div></div>
      <div class="card" style="border-left:3px solid var(--accent);"><div style="font-family:var(--font-mono);font-size:10px;color:var(--accent);margin-bottom:6px;">Q2 - ACCELERATION</div><div style="font-weight:700;font-size:14px;margin-bottom:3px;">Compound Knowledge</div><div style="font-size:12px;color:var(--text-secondary);line-height:1.55;">Publish first thought piece, develop investment framework, build 3 mentor relationships.</div></div>
    </div>
  </div>
  <button class="btn-primary" onclick="showScreen('today')">${svg.play} Start Your 12-Week Plan</button>
</div>`;

// ===== TODAY / HOME — IMPROVED: reduced above-fold, added Feed entry =====
screens.today = `
<div class="grid-bg" style="min-height:100%;padding:20px 20px 96px;">
  <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:20px;">
    <div><div style="font-family:var(--font-mono);font-size:11px;color:var(--mint);letter-spacing:0.8px;">CMPYS.TODAY</div><div style="font-size:24px;font-weight:900;margin-top:2px;">Hello, Alex.</div></div>
    <div style="display:flex;align-items:center;gap:10px;">
      <div style="display:flex;align-items:center;gap:4px;background:var(--mint-muted);padding:7px 10px;border-radius:var(--r8);">${svg.fire}<span style="font-weight:700;font-size:12px;color:var(--mint);">7</span></div>
      <button class="btn-icon">${svg.bell}</button>
    </div>
  </div>
  <div class="card" style="display:flex;align-items:center;gap:14px;margin-bottom:20px;cursor:pointer;" onclick="showScreen('comparison')">
    <div class="avatar" style="border:2px solid var(--mint);">WB</div>
    <div style="flex:1;"><div style="font-family:var(--font-mono);font-size:11px;color:var(--mint);letter-spacing:0.8px;margin-bottom:2px;">Current Mentor</div><div style="font-weight:700;font-size:15px;">Warren Buffett</div></div>
    ${svg.chevron}
  </div>
  <div style="margin-bottom:20px;">
    <div style="font-family:var(--font-mono);font-size:11px;color:var(--mint);letter-spacing:0.8px;margin-bottom:10px;">Daily Focus</div>
    <div class="card-hero">
      <div style="display:flex;align-items:center;gap:8px;margin-bottom:8px;">${svg.lightning}<span style="font-weight:700;font-size:15px;">Read 10-K reports daily</span></div>
      <div style="font-size:13px;color:var(--text-secondary);margin-bottom:10px;line-height:1.55;">Buffett reads 500 pages every day. Start with 5 pages of an annual report.</div>
      <div class="progress-bar"><div class="progress-bar-fill" style="width:40%;background:var(--accent);"></div></div>
    </div>
  </div>
  <div style="margin-bottom:20px;">
    <div style="font-family:var(--font-mono);font-size:11px;color:var(--text-tertiary);letter-spacing:0.8px;margin-bottom:10px;">Today's Tasks <span style="color:var(--text-primary);font-weight:700;">2/4</span></div>
    <div class="card" style="padding:16px;">
      <div style="display:flex;flex-direction:column;gap:10px;">
        <div style="display:flex;align-items:center;gap:12px;min-height:44px;">
          <div style="width:24px;height:24px;border-radius:50%;background:var(--mint);display:flex;align-items:center;justify-content:center;flex-shrink:0;"><span style="color:white;">${svg.check}</span></div>
          <span style="font-size:14px;color:var(--text-tertiary);text-decoration:line-through;">Read 5 pages of annual report</span>
        </div>
        <div style="display:flex;align-items:center;gap:12px;min-height:44px;">
          <div style="width:24px;height:24px;border-radius:50%;background:var(--mint);display:flex;align-items:center;justify-content:center;flex-shrink:0;"><span style="color:white;">${svg.check}</span></div>
          <span style="font-size:14px;color:var(--text-tertiary);text-decoration:line-through;">Journal one investment decision</span>
        </div>
        <div style="display:flex;align-items:center;gap:12px;min-height:44px;cursor:pointer;" onclick="showScreen('task-detail')">
          <div style="width:24px;height:24px;border-radius:50%;border:2px solid var(--border-focus);flex-shrink:0;"></div>
          <span style="font-size:14px;">Review portfolio allocation</span>
        </div>
        <div style="display:flex;align-items:center;gap:12px;min-height:44px;cursor:pointer;" onclick="showScreen('task-detail')">
          <div style="width:24px;height:24px;border-radius:50%;border:2px solid var(--border-focus);flex-shrink:0;"></div>
          <span style="font-size:14px;">Listen to shareholder meeting recording</span>
        </div>
      </div>
    </div>
  </div>
  <div class="card" style="display:flex;align-items:center;gap:14px;margin-bottom:12px;cursor:pointer;" onclick="showScreen('feed')">
    <div style="width:44px;height:44px;border-radius:var(--r12);background:var(--accent-muted);display:flex;align-items:center;justify-content:center;flex-shrink:0;">${svg.sparkle}</div>
    <div style="flex:1;"><div style="font-weight:700;font-size:14px;">Daily Insights</div><div style="font-size:12px;color:var(--text-tertiary);">3 new ideas from your mentor</div></div>
    ${svg.chevron}
  </div>
  <div class="card" style="display:flex;align-items:center;gap:14px;margin-bottom:12px;">
    <div style="width:44px;height:44px;border-radius:50%;background:var(--mint-muted);display:flex;align-items:center;justify-content:center;flex-shrink:0;">${svg.trending}</div>
    <div style="flex:1;"><div style="font-weight:700;font-size:14px;">Week 3 Summary</div><div style="font-size:12px;color:var(--text-tertiary);">5/7 tasks completed</div></div>
    <span style="font-size:12px;color:var(--mint);font-weight:600;cursor:pointer;">Review</span>
  </div>
  <div class="card" style="display:flex;align-items:center;gap:14px;margin-bottom:12px;">
    <div style="width:44px;height:44px;border-radius:var(--r12);background:rgba(59,130,246,0.1);display:flex;align-items:center;justify-content:center;flex-shrink:0;">${svg.book}</div>
    <div style="flex:1;"><div style="font-weight:700;font-size:13px;">The Intelligent Investor</div><div style="font-size:11px;color:var(--text-tertiary);">Chapter 3 &middot; 32% done</div></div>
    <div class="progress-bar" style="width:44px;"><div class="progress-bar-fill" style="width:32%;background:var(--blue);"></div></div>
  </div>
  <div class="card" style="background:var(--text-primary);border:none;position:relative;overflow:hidden;margin-bottom:12px;">
    <div style="position:absolute;top:8px;right:10px;opacity:0.08;color:white;">${svg.sparkle}</div>
    <div style="font-family:var(--font-mono);font-size:11px;color:var(--mint);letter-spacing:0.8px;margin-bottom:8px;">Today's Reflection</div>
    <div style="font-size:14px;line-height:1.55;color:white;margin-bottom:12px;font-family:var(--font-reading);font-style:italic;">"What investment decision am I avoiding because it feels uncertain?"</div>
    <span style="font-size:12px;color:var(--mint);font-weight:600;cursor:pointer;">Submit Insight</span>
  </div>
  <div style="display:grid;grid-template-columns:1fr 1fr 1fr;gap:10px;">
    <div class="card-compact" style="text-align:center;padding:14px 8px;cursor:pointer;" onclick="showScreen('mentor')"><svg width="20" height="20" viewBox="0 0 24 24" fill="var(--accent)"><path d="M20 2H4c-1.1 0-2 .9-2 2v18l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2z"/></svg><div style="font-size:11px;font-weight:600;margin-top:4px;">Chat</div></div>
    <div class="card-compact" style="text-align:center;padding:14px 8px;cursor:pointer;" onclick="showScreen('comparison')"><svg width="20" height="20" viewBox="0 0 24 24" fill="var(--mint)"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z"/></svg><div style="font-size:11px;font-weight:600;margin-top:4px;">Compare</div></div>
    <div class="card-compact" style="text-align:center;padding:14px 8px;cursor:pointer;" onclick="showScreen('achievements')"><svg width="20" height="20" viewBox="0 0 24 24" fill="var(--peach)"><path d="M19 5h-2V3c0-.55-.45-1-1-1H8c-.55 0-1 .45-1 1v2H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V7c0-1.1-.9-2-2-2zm-7 14l-5-5 1.41-1.41L12 16.17l7.59-7.59L21 10l-9 9z"/></svg><div style="font-size:11px;font-weight:600;margin-top:4px;">Achieve</div></div>
  </div>
</div>`;

// ===== COMPARISON =====
screens.comparison = `
<div class="grid-bg" style="min-height:100%;padding:20px 20px 96px;">
  <div style="display:flex;align-items:center;gap:12px;margin-bottom:20px;">
    <button class="btn-icon" onclick="showScreen('today')">${svg.back}</button>
    <div><div class="section-label" style="margin-bottom:2px;">Comparative Growth</div><div style="font-size:13px;color:var(--text-secondary);">Your trajectory vs. your idol</div></div>
  </div>
  <div class="card-elevated" style="text-align:center;margin-bottom:20px;">
    <div class="progress-ring-container" style="margin:16px auto;">
      <svg width="192" height="192" class="progress-ring"><circle cx="96" cy="96" r="82" stroke="var(--surface-2)" stroke-width="12" fill="none"/><circle cx="96" cy="96" r="82" stroke="var(--accent)" stroke-width="12" fill="none" stroke-linecap="round" stroke-dasharray="515.2" stroke-dashoffset="180" style="transform:rotate(-90deg);transform-origin:center;"/></svg>
      <div style="position:absolute;display:flex;flex-direction:column;align-items:center;"><span style="font-size:40px;font-weight:900;color:var(--text-primary);">65%</span><span style="font-family:var(--font-mono);font-size:11px;color:var(--text-tertiary);letter-spacing:0.8px;">OVERALL SYNC</span></div>
    </div>
  </div>
  <div style="display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-bottom:20px;">
    <div class="card" style="text-align:center;"><div style="font-family:var(--font-mono);font-size:11px;color:rgba(22,163,74,0.8);letter-spacing:0.8px;margin-bottom:6px;">STRENGTHS</div><div style="font-size:28px;font-weight:900;color:#16A34A;">3</div><div style="font-size:11px;color:var(--text-tertiary);">Categories ahead</div></div>
    <div class="card" style="text-align:center;"><div style="font-family:var(--font-mono);font-size:11px;color:rgba(248,113,113,0.8);letter-spacing:0.8px;margin-bottom:6px;">GAPS</div><div style="font-size:28px;font-weight:900;color:#F87171;">2</div><div style="font-size:11px;color:var(--text-tertiary);">Areas to close</div></div>
  </div>
  <div style="font-weight:700;font-size:15px;margin-bottom:12px;">Category Breakdown</div>
  <div style="display:flex;flex-direction:column;gap:8px;margin-bottom:24px;">
    ${['Career|78|cat-career|briefcase','Education|90|cat-education|graduation','Skills|55|cat-skills|wrench','Personal|60|cat-personal|heartIcon','Creativity|42|cat-creativity|palette'].map(c=>{const[n,v,cl,ic]=c.split('|');return`<div class="card-compact" style="display:flex;align-items:center;gap:12px;padding:12px 16px;"><span class="cat-badge ${cl}">${svg[ic]} ${n}</span><div style="flex:1;"><div class="progress-bar"><div class="progress-bar-fill" style="width:${v}%;background:var(--${cl});"></div></div></div><span style="font-family:var(--font-mono);font-size:13px;font-weight:700;color:var(--${cl});">${v}%</span></div>`}).join('')}
  </div>
  <div class="card" style="margin-bottom:20px;">
    <div style="display:flex;align-items:center;gap:8px;margin-bottom:12px;">${svg.sparkle}<span style="font-family:var(--font-mono);font-size:11px;color:var(--text-tertiary);letter-spacing:0.8px;">AI INTELLIGENCE SUMMARY</span></div>
    <div style="font-size:13px;color:var(--text-secondary);line-height:1.6;">Your career and education trajectory closely mirrors Buffett's early path. The primary divergence is in creative output and public thought leadership. Closing the creativity gap through structured writing would significantly increase your overall sync.</div>
    <button class="btn-secondary" style="margin-top:14px;font-size:13px;height:44px;">View Detailed Report</button>
  </div>
</div>`;

// ===== PLAN =====
screens.plan = `
<div class="grid-bg" style="min-height:100%;padding:20px 20px 96px;">
  <div style="font-family:var(--font-mono);font-size:11px;color:var(--text-tertiary);letter-spacing:0.8px;margin-bottom:4px;">PLAN</div>
  <div class="section-title" style="margin-bottom:6px;">12-Week Execution</div>
  <div style="display:flex;align-items:center;gap:10px;margin-bottom:20px;">
    <span class="chip chip-mint" style="font-size:11px;">Week 3</span>
    <div style="flex:1;" class="progress-bar"><div class="progress-bar-fill" style="width:25%;background:var(--mint);"></div></div>
    <span style="font-family:var(--font-mono);font-size:11px;color:var(--text-tertiary);">25%</span>
  </div>
  <div class="h-scroll" style="margin-bottom:20px;">
    <span class="chip" style="padding:8px 14px;">W1</span>
    <span class="chip" style="padding:8px 14px;">W2</span>
    <span class="chip chip-mint" style="padding:8px 14px;">W3</span>
    <span class="chip" style="padding:8px 14px;">W4</span>
    <span class="chip" style="padding:8px 14px;">W5</span>
    <span class="chip" style="padding:8px 14px;">W6</span>
  </div>
  <div class="card" style="margin-bottom:12px;border:1.5px solid rgba(16,185,129,0.2);box-shadow:var(--shadow-md);">
    <div style="display:flex;align-items:center;gap:14px;margin-bottom:14px;">
      <div class="progress-ring-container">
        <svg width="56" height="56" class="progress-ring"><circle cx="28" cy="28" r="22" stroke="var(--surface-2)" stroke-width="5" fill="none"/><circle cx="28" cy="28" r="22" stroke="var(--mint)" stroke-width="5" fill="none" stroke-linecap="round" stroke-dasharray="138.2" stroke-dashoffset="55" style="transform:rotate(-90deg);transform-origin:center;"/></svg>
        <div style="position:absolute;font-size:14px;font-weight:800;color:var(--mint);">60%</div>
      </div>
      <div><div style="font-weight:700;font-size:16px;">Week 3: Build the Reading Habit</div><div style="font-size:12px;color:var(--text-tertiary);">3/5 tasks completed</div></div>
    </div>
    <div style="font-size:12px;color:var(--text-secondary);line-height:1.55;margin-bottom:12px;">Establish your daily reading discipline. Buffett reads 500 pages daily — start with 5 and compound.</div>
    <div style="display:flex;gap:8px;">
      <span class="cat-badge cat-skills">${svg.book} Reading</span>
      <span class="cat-badge cat-career">${svg.briefcase} Career</span>
    </div>
  </div>
  <div class="card" style="margin-bottom:12px;opacity:0.65;">
    <div style="display:flex;align-items:center;gap:12px;">
      <div style="width:40px;height:40px;border-radius:50%;background:var(--mint-muted);display:flex;align-items:center;justify-content:center;flex-shrink:0;"><span style="color:var(--mint);">${svg.check}</span></div>
      <div style="flex:1;"><div style="font-weight:600;font-size:14px;">Week 1: Foundation Mindset</div><div style="font-size:11px;color:var(--text-tertiary);">5/5 completed</div></div>
      ${svg.chevron}
    </div>
  </div>
  <div class="card" style="margin-bottom:12px;opacity:0.65;">
    <div style="display:flex;align-items:center;gap:12px;">
      <div style="width:40px;height:40px;border-radius:50%;background:var(--mint-muted);display:flex;align-items:center;justify-content:center;flex-shrink:0;"><span style="color:var(--mint);">${svg.check}</span></div>
      <div style="flex:1;"><div style="font-weight:600;font-size:14px;">Week 2: Decision Journal</div><div style="font-size:11px;color:var(--text-tertiary);">5/5 completed</div></div>
      ${svg.chevron}
    </div>
  </div>
  <div class="card" style="margin-bottom:12px;opacity:0.4;">
    <div style="display:flex;align-items:center;gap:12px;">
      <div style="width:40px;height:40px;border-radius:50%;background:var(--surface-2);display:flex;align-items:center;justify-content:center;flex-shrink:0;">${svg.lock}</div>
      <div style="flex:1;"><div style="font-weight:600;font-size:14px;">Week 4: Network Capital</div><div style="font-size:11px;color:var(--text-tertiary);">Starts Jun 9</div></div>
    </div>
  </div>
  <div style="margin-top:20px;">
    <div style="font-weight:700;font-size:15px;margin-bottom:12px;">Week 3 Tasks</div>
    <div style="display:flex;flex-direction:column;gap:8px;">
      <div class="card-compact" style="display:flex;align-items:center;gap:12px;cursor:pointer;min-height:44px;" onclick="showScreen('task-detail')">
        <div style="width:24px;height:24px;border-radius:50%;background:var(--mint);display:flex;align-items:center;justify-content:center;flex-shrink:0;"><span style="color:white;">${svg.check}</span></div>
        <div style="flex:1;"><div style="font-size:13px;font-weight:600;text-decoration:line-through;color:var(--text-tertiary);">Read 5 pages daily</div></div><span class="cat-badge cat-skills" style="font-size:10px;padding:2px 6px;">${svg.book} Reading</span>
      </div>
      <div class="card-compact" style="display:flex;align-items:center;gap:12px;cursor:pointer;min-height:44px;" onclick="showScreen('task-detail')">
        <div style="width:24px;height:24px;border-radius:50%;background:var(--mint);display:flex;align-items:center;justify-content:center;flex-shrink:0;"><span style="color:white;">${svg.check}</span></div>
        <div style="flex:1;"><div style="font-size:13px;font-weight:600;text-decoration:line-through;color:var(--text-tertiary);">Morning decision journal</div></div><span class="cat-badge cat-career" style="font-size:10px;padding:2px 6px;">${svg.briefcase} Career</span>
      </div>
      <div class="card-compact" style="display:flex;align-items:center;gap:12px;cursor:pointer;min-height:44px;" onclick="showScreen('task-detail')">
        <div style="width:24px;height:24px;border-radius:50%;border:2px solid var(--border-focus);flex-shrink:0;"></div>
        <div style="flex:1;"><div style="font-size:13px;font-weight:600;">Write investment thesis</div></div><span class="cat-badge cat-creativity" style="font-size:10px;padding:2px 6px;">${svg.palette} Creative</span>
      </div>
      <div class="card-compact" style="display:flex;align-items:center;gap:12px;cursor:pointer;min-height:44px;" onclick="showScreen('task-detail')">
        <div style="width:24px;height:24px;border-radius:50%;border:2px solid var(--border-focus);flex-shrink:0;"></div>
        <div style="flex:1;"><div style="font-size:13px;font-weight:600;">Listen to shareholder meeting</div></div><span class="cat-badge cat-education" style="font-size:10px;padding:2px 6px;">${svg.graduation} Education</span>
      </div>
    </div>
  </div>
</div>`;

// ===== TASK DETAIL =====
screens['task-detail'] = `
<div class="grid-bg" style="min-height:100%;padding:20px 20px 40px;">
  <div style="display:flex;align-items:center;gap:12px;margin-bottom:20px;"><button class="btn-icon" onclick="showScreen('plan')">${svg.back}</button></div>
  <div style="font-family:var(--font-mono);font-size:11px;color:var(--text-tertiary);letter-spacing:0.8px;margin-bottom:4px;">Module &middot; Action Detail</div>
  <div style="font-size:26px;font-weight:800;margin-bottom:4px;">Write Investment Thesis</div>
  <span class="cat-badge cat-creativity" style="margin-bottom:20px;">${svg.palette} Creativity</span>
  <div class="card" style="margin-bottom:20px;"><div style="font-size:13px;color:var(--text-secondary);line-height:1.6;">Draft a 2-page investment thesis on a company you're interested in. Follow Buffett's framework: understand the business, identify the moat, assess management quality, and calculate intrinsic value.</div></div>
  <div style="font-family:var(--font-mono);font-size:11px;color:var(--text-tertiary);letter-spacing:0.8px;margin-bottom:12px;">Required Absorption</div>
  <div style="display:flex;flex-direction:column;gap:10px;margin-bottom:24px;">
    <div class="card" style="display:flex;align-items:center;gap:14px;padding:14px;">
      <div style="width:48px;height:48px;border-radius:var(--r12);background:rgba(59,130,246,0.1);display:flex;align-items:center;justify-content:center;flex-shrink:0;">${svg.video}</div>
      <div style="flex:1;"><div style="font-weight:600;font-size:13px;">Buffett on Moats</div><div style="font-size:11px;color:var(--text-tertiary);">Video &middot; 18 min</div></div>
      ${svg.play}
    </div>
    <div class="card" style="display:flex;align-items:center;gap:14px;padding:14px;">
      <div style="width:48px;height:48px;border-radius:var(--r12);background:rgba(139,92,246,0.1);display:flex;align-items:center;justify-content:center;flex-shrink:0;">${svg.book}</div>
      <div style="flex:1;"><div style="font-weight:600;font-size:13px;">Chapter 8: Investor Psychology</div><div style="font-size:11px;color:var(--text-tertiary);">Book &middot; The Intelligent Investor</div></div>
      ${svg.chevron}
    </div>
  </div>
  <div style="font-family:var(--font-mono);font-size:11px;color:var(--text-tertiary);letter-spacing:0.8px;margin-bottom:12px;">Execution Steps</div>
  <div style="display:flex;flex-direction:column;gap:6px;margin-bottom:24px;">
    <div class="card-compact" style="display:flex;align-items:center;gap:12px;min-height:44px;"><div style="width:24px;height:24px;border-radius:var(--r8);background:var(--mint-muted);display:flex;align-items:center;justify-content:center;flex-shrink:0;"><span style="color:var(--mint);">${svg.check}</span></div><span style="font-size:13px;color:var(--text-tertiary);text-decoration:line-through;">Choose target company</span></div>
    <div class="card-compact" style="display:flex;align-items:center;gap:12px;min-height:44px;"><div style="width:24px;height:24px;border-radius:var(--r8);background:var(--mint-muted);display:flex;align-items:center;justify-content:center;flex-shrink:0;"><span style="color:var(--mint);">${svg.check}</span></div><span style="font-size:13px;color:var(--text-tertiary);text-decoration:line-through;">Research the business model</span></div>
    <div class="card-compact" style="display:flex;align-items:center;gap:12px;min-height:44px;"><div style="width:24px;height:24px;border-radius:var(--r8);border:2px solid var(--border);flex-shrink:0;"></div><span style="font-size:13px;">Identify competitive moat</span></div>
    <div class="card-compact" style="display:flex;align-items:center;gap:12px;min-height:44px;"><div style="width:24px;height:24px;border-radius:var(--r8);border:2px solid var(--border);flex-shrink:0;"></div><span style="font-size:13px;">Assess management quality</span></div>
    <div class="card-compact" style="display:flex;align-items:center;gap:12px;min-height:44px;"><div style="width:24px;height:24px;border-radius:var(--r8);border:2px solid var(--border);flex-shrink:0;"></div><span style="font-size:13px;">Draft the thesis document</span></div>
  </div>
  <div style="background:var(--mint-muted);border:1px solid rgba(16,185,129,0.2);border-radius:var(--r16);padding:14px;margin-bottom:24px;">
    <div style="font-family:var(--font-mono);font-size:11px;color:var(--mint);letter-spacing:0.8px;margin-bottom:6px;">Expected Output</div>
    <div style="font-size:13px;color:var(--text-secondary);line-height:1.55;">A 2-page investment thesis document covering business model, moat, management, and valuation.</div>
  </div>
  <button class="btn-primary">Complete Task</button>
</div>`;

// ===== MENTOR CHAT =====
screens.mentor = `
<div class="grid-bg" style="min-height:100%;display:flex;flex-direction:column;">
  <div style="padding:20px 20px 12px;border-bottom:1px solid var(--border);display:flex;align-items:center;gap:12px;">
    <div class="avatar" style="border:2px solid var(--mint);">WB</div>
    <div style="flex:1;"><div style="font-weight:700;font-size:15px;">Warren Buffett</div>
      <div style="display:flex;align-items:center;gap:6px;"><div style="width:6px;height:6px;border-radius:50%;background:var(--mint);"></div><span style="font-size:11px;color:var(--mint);font-weight:500;">AI Active</span></div>
    </div>
    <div class="trust-banner" style="margin:0;padding:6px 10px;border-radius:var(--r8);">
      <div class="trust-banner-icon" style="font-size:12px;">${svg.info}</div>
      <div class="trust-banner-text" style="font-size:10px;line-height:1.3;">AI simulation &middot; not a real person</div>
    </div>
  </div>
  <div style="flex:1;padding:20px;overflow-y:auto;">
    <div style="text-align:center;margin-bottom:24px;">
      <div class="avatar-xl avatar" style="margin:0 auto 12px;">WB</div>
      <div style="font-size:16px;font-weight:700;margin-bottom:4px;">Warren Buffett</div>
      <div style="font-size:11px;color:var(--text-tertiary);margin-bottom:12px;">AI simulation based on public information</div>
    </div>
    <div style="display:flex;gap:10px;margin-bottom:14px;">
      <div class="avatar-sm avatar" style="flex-shrink:0;margin-top:2px;">WB</div>
      <div style="background:var(--surface);border:1px solid var(--border);border-radius:6px 20px 20px 20px;padding:14px;max-width:80%;box-shadow:var(--shadow-sm);"><div style="font-size:14px;line-height:1.55;color:var(--text-primary);">Welcome. I'm here to help you think like an owner, not a speculator. What's on your mind today?</div><div style="font-size:10px;color:var(--text-tertiary);margin-top:6px;cursor:pointer;">Save to Notes</div></div>
    </div>
    <div style="display:flex;justify-content:flex-end;margin-bottom:14px;">
      <div style="background:var(--accent);border-radius:20px 6px 20px 20px;padding:14px;max-width:75%;box-shadow:var(--shadow-sm);"><div style="font-size:14px;line-height:1.55;color:white;font-weight:500;">I've been reading about value investing but I'm not sure how to start analyzing companies. Any advice?</div></div>
    </div>
    <div style="display:flex;gap:10px;margin-bottom:14px;">
      <div class="avatar-sm avatar" style="flex-shrink:0;margin-top:2px;">WB</div>
      <div style="background:var(--surface);border:1px solid var(--border);border-radius:6px 20px 20px 20px;padding:14px;max-width:80%;box-shadow:var(--shadow-sm);"><div style="font-size:14px;line-height:1.55;color:var(--text-primary);">Start with what you know. Pick a business you understand — maybe a company whose products you use daily. Read their annual report cover to cover. Don't worry about being right; worry about being rational.</div><div style="font-size:10px;color:var(--text-tertiary);margin-top:6px;cursor:pointer;">Save to Notes</div></div>
    </div>
    <div style="display:flex;justify-content:flex-end;margin-bottom:14px;">
      <div style="background:var(--accent);border-radius:20px 6px 20px 20px;padding:14px;max-width:75%;"><div style="font-size:14px;line-height:1.55;color:white;font-weight:500;">What should I look for in the annual report?</div></div>
    </div>
    <div style="display:flex;gap:10px;margin-bottom:14px;">
      <div class="avatar-sm avatar" style="flex-shrink:0;margin-top:2px;">WB</div>
      <div style="background:var(--surface);border:1px solid var(--border);border-radius:6px 20px 20px 20px;padding:14px 20px;display:flex;align-items:center;gap:2px;">
        <span class="typing-dot"></span><span class="typing-dot"></span><span class="typing-dot"></span>
      </div>
    </div>
  </div>
  <div style="padding:0 20px 8px;"><div class="h-scroll"><span class="chip" style="cursor:pointer;">Advice for today</span><span class="chip" style="cursor:pointer;">My goals</span><span class="chip" style="cursor:pointer;">Tell me about your journey</span><span class="chip" style="cursor:pointer;">How to handle fear</span></div></div>
  <div style="padding:20px;border-top:1px solid var(--border);background:var(--bg);display:flex;gap:8px;align-items:center;">
    <input class="input-field" style="flex:1;" placeholder="Ask your mentor...">
    <button style="width:48px;height:48px;border-radius:50%;background:var(--accent);border:none;display:flex;align-items:center;justify-content:center;box-shadow:var(--glow-accent);cursor:pointer;"><span style="color:white;">${svg.send}</span></button>
  </div>
</div>`;

// ===== FEED — IMPROVED: full-screen immersive cards =====
screens.feed = `
<div style="min-height:100%;background:var(--bg);position:relative;">
  <div style="position:sticky;top:0;z-index:10;padding:44px 20px 12px;background:linear-gradient(var(--bg),transparent);pointer-events:none;">
    <div style="pointer-events:auto;display:flex;align-items:center;justify-content:space-between;">
      <div><div style="font-family:var(--font-mono);font-size:11px;color:var(--mint);letter-spacing:0.8px;">IDEAS</div><div style="font-size:22px;font-weight:900;">Daily Insights</div></div>
      <button class="btn-icon">${svg.search}</button>
    </div>
  </div>
  <div style="padding:0 20px 96px;">
    <div style="min-height:520px;background:linear-gradient(145deg,rgba(236,72,153,0.05),rgba(139,92,246,0.04));border:1px solid rgba(236,72,153,0.12);border-radius:var(--r20);padding:28px;margin-bottom:16px;position:relative;overflow:hidden;">
      <div style="position:absolute;top:-20px;right:-20px;width:100px;height:100px;background:radial-gradient(circle,rgba(236,72,153,0.06),transparent);"></div>
      <span class="cat-badge cat-creativity" style="margin-bottom:14px;">${svg.palette} Creativity</span>
      <div style="font-family:var(--font-reading);font-size:24px;font-weight:600;font-style:italic;color:var(--text-primary);line-height:1.4;margin-bottom:14px;">"The most important thing to do if you find yourself in a hole is to stop digging."</div>
      <div style="font-size:15px;color:var(--text-secondary);line-height:1.55;margin-bottom:20px;">Buffett's first rule of investing is simplicity itself: don't lose money. Yet most people ignore this and chase returns. The discipline to stop when you're wrong is worth more than any strategy.</div>
      <div style="display:flex;align-items:center;justify-content:space-between;">
        <div style="display:flex;align-items:center;gap:8px;"><div class="avatar-sm avatar">WB</div><span style="font-size:12px;color:var(--text-tertiary);">Warren Buffett</span></div>
        <div style="display:flex;align-items:center;gap:16px;">
          <div style="display:flex;align-items:center;gap:5px;cursor:pointer;min-height:44px;min-width:44px;">${svg.heart}<span style="font-size:12px;color:var(--text-tertiary);">24</span></div>
          <div style="cursor:pointer;min-height:44px;min-width:44px;display:flex;align-items:center;justify-content:center;">${svg.bookmark}</div>
        </div>
      </div>
    </div>
    <div style="min-height:520px;background:linear-gradient(145deg,rgba(16,185,129,0.05),rgba(59,130,246,0.04));border:1px solid rgba(16,185,129,0.12);border-radius:var(--r20);padding:28px;margin-bottom:16px;position:relative;overflow:hidden;">
      <span class="cat-badge cat-skills" style="margin-bottom:14px;">${svg.wrench} Skills</span>
      <div style="font-family:var(--font-reading);font-size:24px;font-weight:600;font-style:italic;color:var(--text-primary);line-height:1.4;margin-bottom:14px;">"In the business world, the rearview mirror is always clearer than the windshield."</div>
      <div style="font-size:15px;color:var(--text-secondary);line-height:1.55;margin-bottom:20px;">Hindsight bias makes past events seem inevitable. The antidote: keep a decision journal so you can evaluate your thinking process, not just outcomes.</div>
      <div style="display:flex;align-items:center;justify-content:space-between;">
        <div style="display:flex;align-items:center;gap:8px;"><div class="avatar-sm avatar">WB</div><span style="font-size:12px;color:var(--text-tertiary);">Warren Buffett</span></div>
        <div style="display:flex;align-items:center;gap:16px;">
          <div style="display:flex;align-items:center;gap:5px;cursor:pointer;min-height:44px;min-width:44px;color:var(--accent);">${svg.heart}<span style="font-size:12px;color:var(--accent);">31</span></div>
          <div style="cursor:pointer;min-height:44px;min-width:44px;display:flex;align-items:center;justify-content:center;color:var(--mint);">${svg.bookmark}</div>
        </div>
      </div>
    </div>
    <div style="min-height:520px;background:linear-gradient(145deg,rgba(59,130,246,0.05),rgba(139,92,246,0.04));border:1px solid rgba(59,130,246,0.12);border-radius:var(--r20);padding:28px;position:relative;overflow:hidden;">
      <span class="cat-badge cat-career" style="margin-bottom:14px;">${svg.briefcase} Career</span>
      <div style="font-family:var(--font-reading);font-size:24px;font-weight:600;font-style:italic;color:var(--text-primary);line-height:1.4;margin-bottom:14px;">"Your premium brand had better be delivering something special, or it's not going to get the business."</div>
      <div style="font-size:15px;color:var(--text-secondary);line-height:1.55;margin-bottom:20px;">Personal branding isn't about visibility — it's about delivering unique value consistently. What makes your work irreplaceable?</div>
      <div style="display:flex;align-items:center;justify-content:space-between;">
        <div style="display:flex;align-items:center;gap:8px;"><div class="avatar-sm avatar">WB</div><span style="font-size:12px;color:var(--text-tertiary);">Warren Buffett</span></div>
        <div style="display:flex;align-items:center;gap:16px;">
          <div style="display:flex;align-items:center;gap:5px;cursor:pointer;min-height:44px;min-width:44px;">${svg.heart}<span style="font-size:12px;color:var(--text-tertiary);">18</span></div>
          <div style="cursor:pointer;min-height:44px;min-width:44px;display:flex;align-items:center;justify-content:center;">${svg.bookmark}</div>
        </div>
      </div>
    </div>
  </div>
</div>`;

// ===== LIBRARY =====
screens.library = `
<div class="grid-bg" style="min-height:100%;padding:20px 20px 96px;">
  <div style="font-family:var(--font-mono);font-size:11px;color:var(--mint);letter-spacing:0.8px;margin-bottom:4px;">LIBRARY</div>
  <div class="section-title" style="margin-bottom:16px;">Your Library</div>
  <div style="display:flex;gap:8px;margin-bottom:24px;">
    <span class="chip chip-mint">Reading</span>
    <span class="chip">Insights</span>
    <span class="chip">Saved</span>
  </div>
  <div style="font-weight:700;font-size:15px;margin-bottom:14px;">Continue Reading</div>
  <div class="h-scroll" style="margin-bottom:24px;">
    <div class="card" style="width:160px;padding:14px;"><div style="width:100%;height:80px;border-radius:var(--r12);background:rgba(139,92,246,0.08);display:flex;align-items:center;justify-content:center;margin-bottom:10px;">${svg.book}</div><div style="font-weight:700;font-size:13px;margin-bottom:4px;">The Intelligent Investor</div><div style="font-size:10px;color:var(--text-tertiary);margin-bottom:8px;">Benjamin Graham</div><div class="progress-bar"><div class="progress-bar-fill" style="width:32%;background:var(--cat-education);"></div></div></div>
    <div class="card" style="width:160px;padding:14px;"><div style="width:100%;height:80px;border-radius:var(--r12);background:var(--mint-muted);display:flex;align-items:center;justify-content:center;margin-bottom:10px;">${svg.video}</div><div style="font-weight:700;font-size:13px;margin-bottom:4px;">Buffett on Moats</div><div style="font-size:10px;color:var(--text-tertiary);margin-bottom:8px;">Video &middot; 18 min</div><div class="progress-bar"><div class="progress-bar-fill" style="width:65%;background:var(--mint);"></div></div></div>
    <div class="card" style="width:160px;padding:14px;"><div style="width:100%;height:80px;border-radius:var(--r12);background:var(--accent-muted);display:flex;align-items:center;justify-content:center;margin-bottom:10px;">${svg.sparkle}</div><div style="font-weight:700;font-size:13px;margin-bottom:4px;">Decision Journal Guide</div><div style="font-size:10px;color:var(--text-tertiary);margin-bottom:8px;">Article &middot; 8 min</div><div class="progress-bar"><div class="progress-bar-fill" style="width:100%;background:var(--cat-creativity);"></div></div></div>
  </div>
  <div style="font-weight:700;font-size:15px;margin-bottom:14px;">Book Modules</div>
  <div style="display:flex;flex-direction:column;gap:10px;">
    <div class="card" style="display:flex;align-items:center;gap:14px;">
      <div style="width:48px;height:64px;border-radius:var(--r8);background:rgba(139,92,246,0.08);display:flex;align-items:center;justify-content:center;flex-shrink:0;">${svg.book}</div>
      <div style="flex:1;"><div style="font-weight:700;font-size:13px;margin-bottom:2px;">Margin of Safety</div><div style="font-size:11px;color:var(--text-tertiary);">Seth Klarman &middot; 45 min read</div></div>
      <span class="chip chip-mint" style="font-size:10px;">New</span>
    </div>
    <div class="card" style="display:flex;align-items:center;gap:14px;">
      <div style="width:48px;height:64px;border-radius:var(--r8);background:var(--mint-muted);display:flex;align-items:center;justify-content:center;flex-shrink:0;">${svg.book}</div>
      <div style="flex:1;"><div style="font-weight:700;font-size:13px;margin-bottom:2px;">Poor Charlie's Almanack</div><div style="font-size:11px;color:var(--text-tertiary);">Charlie Munger &middot; 60 min</div></div>
      <div style="font-family:var(--font-mono);font-size:11px;color:var(--mint);">78%</div>
    </div>
    <div class="card" style="display:flex;align-items:center;gap:14px;">
      <div style="width:48px;height:64px;border-radius:var(--r8);background:rgba(249,115,22,0.08);display:flex;align-items:center;justify-content:center;flex-shrink:0;">${svg.book}</div>
      <div style="flex:1;"><div style="font-weight:700;font-size:13px;margin-bottom:2px;">Meditations</div><div style="font-size:11px;color:var(--text-tertiary);">Marcus Aurelius &middot; 35 min</div></div>
      <span class="chip" style="font-size:10px;">Saved</span>
    </div>
  </div>
</div>`;

// ===== PROFILE =====
screens.profile = `
<div style="min-height:100%;background:linear-gradient(var(--surface-highlight),var(--bg) 52%);padding:20px 20px 96px;">
  <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:24px;">
    <div class="section-title">Profile</div>
    <button class="btn-icon" onclick="showScreen('achievements')">${svg.gear}</button>
  </div>
  <div class="card-elevated" style="text-align:center;margin-bottom:24px;position:relative;overflow:hidden;">
    <div style="position:absolute;top:0;left:0;right:0;height:80px;background:linear-gradient(135deg,var(--accent-muted),rgba(255,194,122,0.08));"></div>
    <div class="avatar-xl avatar" style="margin:0 auto 14px;position:relative;z-index:1;">AK</div>
    <div style="font-size:20px;font-weight:800;margin-bottom:2px;">Alex K.</div>
    <div style="font-size:13px;color:var(--text-tertiary);margin-bottom:14px;">alex@example.com</div>
    <div style="display:flex;justify-content:center;gap:24px;margin-bottom:14px;">
      <div style="text-align:center;"><div style="font-size:20px;font-weight:800;">28</div><div style="font-family:var(--font-mono);font-size:10px;color:var(--text-tertiary);">AGE</div></div>
      <div style="width:1px;background:var(--border);"></div>
      <div style="text-align:center;"><div style="font-size:20px;font-weight:800;">3</div><div style="font-family:var(--font-mono);font-size:10px;color:var(--text-tertiary);">INTERESTS</div></div>
    </div>
    <button class="btn-secondary" style="font-size:13px;height:44px;">Edit Profile</button>
  </div>
  <div style="margin-bottom:24px;">
    <div style="font-weight:700;font-size:15px;margin-bottom:12px;">Interests</div>
    <div style="display:flex;flex-wrap:wrap;gap:8px;"><span class="chip chip-accent">Investing</span><span class="chip">Technology</span><span class="chip">Reading</span></div>
  </div>
  <div class="card" style="display:flex;align-items:center;gap:14px;margin-bottom:24px;cursor:pointer;" onclick="showScreen('comparison')">
    <div class="progress-ring-container">
      <svg width="48" height="48" class="progress-ring"><circle cx="24" cy="24" r="19" stroke="var(--surface-2)" stroke-width="4" fill="none"/><circle cx="24" cy="24" r="19" stroke="var(--accent)" stroke-width="4" fill="none" stroke-linecap="round" stroke-dasharray="119.4" stroke-dashoffset="41.8" style="transform:rotate(-90deg);transform-origin:center;"/></svg>
      <div style="position:absolute;font-size:11px;font-weight:800;color:var(--accent);">65%</div>
    </div>
    <div style="flex:1;"><div style="font-weight:700;font-size:14px;">Overall Progress</div><div style="font-size:12px;color:var(--text-tertiary);">vs. Warren Buffett</div></div>
    ${svg.chevron}
  </div>
  <div style="display:flex;flex-direction:column;gap:2px;">
    <div class="card-compact" style="display:flex;align-items:center;gap:14px;padding:14px 16px;cursor:pointer;min-height:48px;"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M20 21v-2a4 4 0 00-4-4H8a4 4 0 00-4 4v2"/><circle cx="12" cy="7" r="4"/></svg><span style="flex:1;font-size:14px;font-weight:500;">Edit Profile</span>${svg.chevron}</div>
    <div class="card-compact" style="display:flex;align-items:center;gap:14px;padding:14px 16px;cursor:pointer;min-height:48px;"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M17 21v-2a4 4 0 00-4-4H5a4 4 0 00-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 00-3-3.87M16 3.13a4 4 0 010 7.75"/></svg><span style="flex:1;font-size:14px;font-weight:500;">Change Idol</span>${svg.chevron}</div>
    <div class="card-compact" style="display:flex;align-items:center;gap:14px;padding:14px 16px;cursor:pointer;min-height:48px;">${svg.bell}<span style="flex:1;font-size:14px;font-weight:500;">Notifications</span>${svg.chevron}</div>
    <div class="card-compact" style="display:flex;align-items:center;gap:14px;padding:14px 16px;cursor:pointer;min-height:48px;"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="5"/><path d="M12 1v2M12 21v2M4.22 4.22l1.42 1.42M18.36 18.36l1.42 1.42M1 12h2M21 12h2M4.22 19.78l1.42-1.42M18.36 5.64l1.42-1.42"/></svg><span style="flex:1;font-size:14px;font-weight:500;">Appearance</span><span style="font-size:12px;color:var(--text-tertiary);">Light</span>${svg.chevron}</div>
    <div class="card-compact" style="display:flex;align-items:center;gap:14px;padding:14px 16px;cursor:pointer;min-height:48px;"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><path d="M9.09 9a3 3 0 015.83 1c0 2-3 3-3 3M12 17h.01"/></svg><span style="flex:1;font-size:14px;font-weight:500;">Help Center</span>${svg.chevron}</div>
    <div class="card-compact" style="display:flex;align-items:center;gap:14px;padding:14px 16px;cursor:pointer;min-height:48px;"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg><span style="flex:1;font-size:14px;font-weight:500;">Privacy Policy</span>${svg.chevron}</div>
  </div>
  <div style="margin-top:20px;"><button class="btn-ghost" style="color:var(--red);"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M9 21H5a2 2 0 01-2-2V5a2 2 0 012-2h4M16 17l5-5-5-5M21 12H9"/></svg> Sign Out</button></div>
</div>`;

// ===== ACHIEVEMENTS =====
screens.achievements = `
<div class="grid-bg" style="min-height:100%;padding:20px 20px 40px;">
  <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:24px;">
    <div><div style="font-family:var(--font-mono);font-size:11px;color:var(--mint);letter-spacing:0.8px;">ACHIEVEMENTS</div><div style="font-size:22px;font-weight:900;">Your Milestones</div></div>
    <button style="width:44px;height:44px;border-radius:var(--r12);background:var(--accent);border:none;display:flex;align-items:center;justify-content:center;box-shadow:var(--glow-accent);cursor:pointer;color:white;">${svg.plus}</button>
  </div>
  <div style="display:flex;flex-direction:column;gap:10px;">
    <div class="card" style="display:flex;align-items:center;gap:14px;min-height:44px;">
      <div style="width:40px;height:40px;border-radius:var(--r10);background:rgba(59,130,246,0.1);display:flex;align-items:center;justify-content:center;flex-shrink:0;">${svg.briefcase}</div>
      <div style="flex:1;"><div style="font-weight:700;font-size:14px;">Founded Consulting Practice</div><div style="font-size:11px;color:var(--text-tertiary);"><span class="cat-badge cat-career" style="font-size:9px;padding:1px 5px;">${svg.briefcase} Career</span> &middot; Mar 2026</div></div>
    </div>
    <div class="card" style="display:flex;align-items:center;gap:14px;min-height:44px;">
      <div style="width:40px;height:40px;border-radius:var(--r10);background:rgba(139,92,246,0.1);display:flex;align-items:center;justify-content:center;flex-shrink:0;">${svg.graduation}</div>
      <div style="flex:1;"><div style="font-weight:700;font-size:14px;">MBA Completed</div><div style="font-size:11px;color:var(--text-tertiary);"><span class="cat-badge cat-education" style="font-size:9px;padding:1px 5px;">${svg.graduation} Education</span> &middot; Jun 2025</div></div>
    </div>
    <div class="card" style="display:flex;align-items:center;gap:14px;min-height:44px;">
      <div style="width:40px;height:40px;border-radius:var(--r10);background:rgba(16,185,129,0.1);display:flex;align-items:center;justify-content:center;flex-shrink:0;">${svg.wrench}</div>
      <div style="flex:1;"><div style="font-weight:700;font-size:14px;">First Investment Thesis</div><div style="font-size:11px;color:var(--text-tertiary);"><span class="cat-badge cat-skills" style="font-size:9px;padding:1px 5px;">${svg.wrench} Skills</span> &middot; Jan 2026</div></div>
    </div>
    <div class="card" style="display:flex;align-items:center;gap:14px;min-height:44px;">
      <div style="width:40px;height:40px;border-radius:var(--r10);background:rgba(249,115,22,0.1);display:flex;align-items:center;justify-content:center;flex-shrink:0;">${svg.heartIcon}</div>
      <div style="flex:1;"><div style="font-weight:700;font-size:14px;">30-Day Meditation Streak</div><div style="font-size:11px;color:var(--text-tertiary);"><span class="cat-badge cat-personal" style="font-size:9px;padding:1px 5px;">${svg.heartIcon} Personal</span> &middot; Feb 2026</div></div>
    </div>
  </div>
</div>`;

// Initialize
showScreen('today');