// app.jsx — Main App for macOS Clipboard Manager prototype

function App() {
  const [t, setTweak] = useTweaks(TWEAK_DEFAULTS);
  const dark = t.dark;
  const [drawerVisible, setDrawerVisible] = React.useState(true);
  const [showMenuBar, setShowMenuBar] = React.useState(false);
  const [showPrefs, setShowPrefs] = React.useState(false);
  const [showOnboarding, setShowOnboarding] = React.useState(false);
  const [showEmptyState, setShowEmptyState] = React.useState(false);

  // Toggle drawer with Escape
  React.useEffect(() => {
    const handler = (e) => {
      if (e.key === 'Escape') {
        if (showPrefs) { setShowPrefs(false); return; }
        if (showOnboarding) { setShowOnboarding(false); return; }
        if (showMenuBar) { setShowMenuBar(false); return; }
      }
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [showPrefs, showOnboarding, showMenuBar]);

  const accentColor = t.accent || '#007AFF';

  // Desktop wallpaper gradient (macOS-like)
  const wallpaper = dark
    ? 'radial-gradient(ellipse at 30% 20%, #1a1040 0%, #0c0c1d 40%, #0a0a16 100%)'
    : 'radial-gradient(ellipse at 50% 30%, #c2d7f0 0%, #8aadd4 30%, #5b8abf 60%, #e8dcc8 100%)';

  const desktopS = {
    position: 'fixed', inset: 0, background: wallpaper,
    fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro", "Helvetica Neue", sans-serif',
    overflow: 'hidden', transition: 'background 0.5s ease',
  };

  // ─── macOS Menu Bar ─────────────────────────────────────────────────

  const menuBarS = {
    position: 'fixed', top: 0, left: 0, right: 0, height: 25, zIndex: 8000,
    display: 'flex', alignItems: 'center', justifyContent: 'space-between',
    padding: '0 12px',
    background: dark ? 'rgba(30,30,30,0.65)' : 'rgba(255,255,255,0.65)',
    backdropFilter: 'blur(30px) saturate(180%)',
    WebkitBackdropFilter: 'blur(30px) saturate(180%)',
    borderBottom: `0.5px solid ${dark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)'}`,
    color: dark ? 'rgba(255,255,255,0.85)' : 'rgba(0,0,0,0.85)',
    fontSize: 13, fontWeight: 500,
    fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif',
  };

  const menuLeftS = { display: 'flex', gap: 16, alignItems: 'center' };
  const menuRightS = { display: 'flex', gap: 14, alignItems: 'center' };
  const menuIconBtnS = (active) => ({
    padding: '2px 6px', borderRadius: 4, cursor: 'default',
    background: active ? (dark ? 'rgba(255,255,255,0.15)' : 'rgba(0,0,0,0.1)') : 'transparent',
    display: 'flex', alignItems: 'center', justifyContent: 'center',
  });

  const now = new Date();
  const timeStr = now.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true });
  const dayStr = now.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' });

  // ─── Desktop hint (when drawer is hidden) ───────────────────────────

  const hintS = {
    position: 'fixed', bottom: 60, left: '50%', transform: 'translateX(-50%)',
    display: 'flex', gap: 8, alignItems: 'center',
    padding: '8px 16px', borderRadius: 10,
    background: dark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)',
    backdropFilter: 'blur(20px)',
    color: dark ? 'rgba(255,255,255,0.5)' : 'rgba(0,0,0,0.4)',
    fontSize: 12, fontWeight: 500,
    opacity: drawerVisible ? 0 : 1,
    transition: 'opacity 0.3s',
    pointerEvents: 'none',
  };

  // ─── Floating nav for prototype ─────────────────────────────────────

  const navS = {
    position: 'fixed', top: 38, left: '50%', transform: 'translateX(-50%)',
    display: 'flex', gap: 6, zIndex: 8500,
    padding: '4px 6px', borderRadius: 9,
    background: dark ? 'rgba(40,40,42,0.85)' : 'rgba(255,255,255,0.85)',
    backdropFilter: 'blur(20px) saturate(180%)',
    WebkitBackdropFilter: 'blur(20px) saturate(180%)',
    border: `0.5px solid ${dark ? 'rgba(255,255,255,0.1)' : 'rgba(0,0,0,0.06)'}`,
    boxShadow: dark ? '0 4px 20px rgba(0,0,0,0.3)' : '0 4px 20px rgba(0,0,0,0.08)',
  };

  const NavBtn = ({ label, active, onClick }) => {
    const [hover, setHover] = React.useState(false);
    return (
      <div onMouseEnter={() => setHover(true)} onMouseLeave={() => setHover(false)}
        onClick={onClick}
        style={{
          padding: '4px 12px', borderRadius: 6, fontSize: 11, fontWeight: 500, cursor: 'default',
          background: active ? accentColor : hover ? (dark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.04)') : 'transparent',
          color: active ? '#fff' : (dark ? 'rgba(255,255,255,0.6)' : 'rgba(0,0,0,0.5)'),
          transition: 'all 0.1s',
          letterSpacing: '-0.01em',
        }}>
        {label}
      </div>
    );
  };

  return (
    <div style={desktopS} data-theme={dark ? 'dark' : 'light'}>
      {/* ── macOS Menu Bar ── */}
      <div style={menuBarS}>
        <div style={menuLeftS}>
          <span style={{ fontSize: 15, fontWeight: 700, letterSpacing: '-0.02em' }}>
            <svg width="13" height="15" viewBox="0 0 814 1000" fill="currentColor" style={{ marginTop: 1 }}>
              <path d="M788.1 340.9c-5.8 4.5-108.2 62.2-108.2 190.5 0 148.4 130.3 200.9 134.2 202.2-.6 3.2-20.7 71.9-68.7 141.9-42.8 61.6-87.5 123.1-155.5 123.1s-85.5-39.5-164-39.5c-76.5 0-103.7 40.8-165.9 40.8s-105.6-57.4-155.5-127.2c-58.5-81.6-105.2-208.7-105.2-330.1 0-194.3 126.4-297.5 250.8-297.5 66.1 0 121.2 43.4 162.7 43.4 39.5 0 101.1-46 176.3-46 28.5 0 130.9 2.6 198.3 99.2l-.3.2z"/>
            </svg>
          </span>
          <span style={{ fontWeight: 700 }}>Clipboard Manager</span>
          <span style={{ opacity: 0.7 }}>File</span>
          <span style={{ opacity: 0.7 }}>Edit</span>
          <span style={{ opacity: 0.7 }}>View</span>
          <span style={{ opacity: 0.7 }}>Help</span>
        </div>
        <div style={menuRightS}>
          <span style={{ opacity: 0.5, fontSize: 12 }}>
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" style={{ verticalAlign: -2 }}>
              <path d="M12 18.5C15.5 18.5 18.5 15.5 18.5 12C18.5 8.5 15.5 5.5 12 5.5C8.5 5.5 5.5 8.5 5.5 12C5.5 15.5 8.5 18.5 12 18.5Z" stroke="currentColor" strokeWidth="1.5"/>
              <path d="M12 2V4M12 20V22M2 12H4M20 12H22" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round"/>
            </svg>
          </span>
          <span style={{ opacity: 0.5, fontSize: 12 }}>
            <svg width="15" height="12" viewBox="0 0 24 18" fill="none" style={{ verticalAlign: -1 }}>
              <path d="M2 5C5 2 9 1 12 1s7 1 10 4" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/>
              <path d="M5 9c2-2 5-3 7-3s5 1 7 3" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/>
              <circle cx="12" cy="14" r="2" fill="currentColor"/>
            </svg>
          </span>
          {/* Clipboard Manager menu bar icon */}
          <div style={menuIconBtnS(showMenuBar)}
            onClick={() => setShowMenuBar(!showMenuBar)}>
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" style={{ opacity: 0.75 }}>
              <rect x="6" y="3" width="12" height="16" rx="2" stroke="currentColor" strokeWidth="1.5"/>
              <path d="M10 3V1M14 3V1" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round"/>
              <path d="M9 8h6M9 11h4" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" opacity="0.6"/>
            </svg>
          </div>
          <span style={{ fontSize: 12, opacity: 0.85 }}>{dayStr} {timeStr}</span>
        </div>
      </div>

      {/* ── Prototype Navigation ── */}
      <div style={navS}>
        <NavBtn label="Drawer" active={drawerVisible && !showEmptyState}
          onClick={() => { setDrawerVisible(true); setShowEmptyState(false); }} />
        <NavBtn label="Empty State" active={showEmptyState}
          onClick={() => { setShowEmptyState(!showEmptyState); setDrawerVisible(true); }} />
        <NavBtn label="Preferences" active={showPrefs}
          onClick={() => setShowPrefs(!showPrefs)} />
        <NavBtn label="Onboarding" active={showOnboarding}
          onClick={() => setShowOnboarding(!showOnboarding)} />
      </div>

      {/* ── Desktop background dock hint ── */}
      <div style={hintS}>
        Press <kbd style={{
          padding: '1px 5px', borderRadius: 4,
          background: dark ? 'rgba(255,255,255,0.1)' : 'rgba(0,0,0,0.08)',
          fontWeight: 600, fontSize: 11,
        }}>⌘⇧V</kbd> to open
      </div>

      {/* ── macOS Dock (decorative) ── */}
      <Dock dark={dark} />

      {/* ── Bottom Drawer ── */}
      {showEmptyState ? (
        <div style={{
          position: 'fixed', bottom: 0, left: 0, right: 0, height: 300, zIndex: 9000,
          borderRadius: '16px 16px 0 0', overflow: 'hidden',
          backgroundColor: dark ? '#2c2c30' : '#f2f2f7',
          backgroundImage: dark
            ? 'linear-gradient(180deg, rgba(52,52,56,0.97) 0%, rgba(32,32,35,0.99) 100%)'
            : 'linear-gradient(180deg, rgba(248,248,252,0.97) 0%, rgba(240,240,245,0.99) 100%)',
          backdropFilter: 'blur(60px) saturate(180%)',
          WebkitBackdropFilter: 'blur(60px) saturate(180%)',
          border: `0.5px solid ${dark ? 'rgba(255,255,255,0.15)' : 'rgba(0,0,0,0.08)'}`,
          borderBottom: 'none',
          boxShadow: dark
            ? '0 -8px 60px rgba(0,0,0,0.5), inset 0 1px 0 rgba(255,255,255,0.1), 0 -1px 0 rgba(255,255,255,0.08)'
            : '0 -8px 60px rgba(0,0,0,0.1), inset 0 1px 0 rgba(255,255,255,0.6), 0 -1px 0 rgba(0,0,0,0.04)',
          display: 'flex',
          color: dark ? '#fff' : '#000',
          transform: drawerVisible ? 'translateY(0)' : 'translateY(100%)',
          transition: 'transform 0.45s cubic-bezier(0.25, 1, 0.5, 1)',
        }}>
          <EmptyState dark={dark} />
        </div>
      ) : (
        <BottomDrawer dark={dark} visible={drawerVisible} />
      )}

      {/* ── Menu Bar Dropdown ── */}
      {showMenuBar && (
        <MenuBarDropdown dark={dark}
          onClose={() => setShowMenuBar(false)}
          onOpenPrefs={() => setShowPrefs(true)} />
      )}

      {/* ── Preferences ── */}
      {showPrefs && <PreferencesWindow dark={dark} onClose={() => setShowPrefs(false)} />}

      {/* ── Onboarding ── */}
      {showOnboarding && <OnboardingFlow dark={dark} onClose={() => setShowOnboarding(false)} />}

      {/* ── Tweaks ── */}
      <TweaksPanel>
        <TweakSection label="Appearance" />
        <TweakToggle label="Dark Mode" value={t.dark}
          onChange={(v) => setTweak('dark', v)} />
        <TweakColor label="Accent Color" value={t.accent}
          options={['#007AFF', '#5856D6', '#AF52DE', '#FF375F', '#FF9500', '#30D158']}
          onChange={(v) => setTweak('accent', v)} />
        <TweakSection label="Layout" />
        <TweakSlider label="Card Width" value={t.cardWidth} min={140} max={240} step={4} unit="px"
          onChange={(v) => setTweak('cardWidth', v)} />
        <TweakSlider label="Drawer Height" value={t.drawerHeight} min={240} max={400} step={8} unit="px"
          onChange={(v) => setTweak('drawerHeight', v)} />
        <TweakSlider label="Card Gap" value={t.cardGap} min={6} max={20} step={1} unit="px"
          onChange={(v) => setTweak('cardGap', v)} />
        <TweakSection label="Effects" />
        <TweakSlider label="Blur Intensity" value={t.blur} min={20} max={100} step={5} unit="px"
          onChange={(v) => setTweak('blur', v)} />
        <TweakSlider label="Background Opacity" value={t.bgOpacity} min={0.4} max={0.98} step={0.02}
          onChange={(v) => setTweak('bgOpacity', v)} />
        <TweakToggle label="Show Dock" value={t.showDock}
          onChange={(v) => setTweak('showDock', v)} />
      </TweaksPanel>
    </div>
  );
}

// ─── Decorative macOS Dock ──────────────────────────────────────────────────

function Dock({ dark }) {
  const dockApps = [
    { color: '#007AFF', label: 'Finder' },
    { color: '#30D158', label: 'Messages' },
    { color: '#FF9500', label: 'Notes' },
    { color: '#5856D6', label: 'Mail' },
    { color: '#FF375F', label: 'Music' },
    { color: '#007AFF', label: 'Safari' },
    { color: '#8E8E93', label: 'Terminal' },
    { color: '#AF52DE', label: 'Figma' },
  ];

  return (
    <div style={{
      position: 'fixed', bottom: 8, left: '50%', transform: 'translateX(-50%)',
      display: 'flex', gap: 6, padding: '6px 10px', borderRadius: 16, zIndex: 7000,
      background: dark ? 'rgba(40,40,42,0.45)' : 'rgba(255,255,255,0.35)',
      backdropFilter: 'blur(20px) saturate(180%)',
      WebkitBackdropFilter: 'blur(20px) saturate(180%)',
      border: `0.5px solid ${dark ? 'rgba(255,255,255,0.08)' : 'rgba(255,255,255,0.5)'}`,
      boxShadow: dark ? '0 4px 20px rgba(0,0,0,0.25)' : '0 4px 20px rgba(0,0,0,0.06)',
    }}>
      {dockApps.map((app, i) => (
        <div key={i} title={app.label} style={{
          width: 42, height: 42, borderRadius: 10,
          background: app.color, opacity: 0.85,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          boxShadow: '0 2px 6px rgba(0,0,0,0.15)',
          color: '#fff', fontSize: 16, fontWeight: 700,
          fontFamily: '-apple-system, sans-serif',
        }}>
          {app.label[0]}
        </div>
      ))}
    </div>
  );
}

// ─── Render ─────────────────────────────────────────────────────────────────

const root = ReactDOM.createRoot(document.getElementById('root'));
root.render(<App />);
