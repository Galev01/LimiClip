// screens.jsx — Additional screens for macOS Clipboard Manager
// MenuBarDropdown, PreferencesWindow, SnippetEditor, OnboardingFlow, EmptyState

const SCR_FONT = '-apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro", "Helvetica Neue", sans-serif';
const SCR_MONO = '"SF Mono", ui-monospace, "SFMono-Regular", Menlo, Consolas, monospace';

// ─── Menu Bar Dropdown ──────────────────────────────────────────────────────

function MenuBarDropdown({ dark, onClose, onOpenPrefs }) {
  const ref = React.useRef(null);
  React.useEffect(() => {
    const h = (e) => { if (ref.current && !ref.current.contains(e.target)) onClose(); };
    setTimeout(() => document.addEventListener('mousedown', h), 10);
    return () => document.removeEventListener('mousedown', h);
  }, [onClose]);

  const recentItems = CLIPBOARD_ITEMS.slice(0, 5);

  const dropS = {
    position: 'fixed', top: 30, right: 80, width: 280,
    borderRadius: 10, overflow: 'hidden', padding: '6px 0',
    background: dark ? 'rgba(40,40,42,0.98)' : 'rgba(255,255,255,0.98)',
    backdropFilter: 'blur(50px) saturate(200%)',
    WebkitBackdropFilter: 'blur(50px) saturate(200%)',
    border: `0.5px solid ${dark ? 'rgba(255,255,255,0.15)' : 'rgba(0,0,0,0.1)'}`,
    boxShadow: dark
      ? '0 12px 40px rgba(0,0,0,0.5), 0 0 0 0.5px rgba(255,255,255,0.08)'
      : '0 12px 40px rgba(0,0,0,0.18), 0 0 0 0.5px rgba(0,0,0,0.05)',
    zIndex: 10002, animation: 'menuIn 0.12s ease-out',
    fontFamily: SCR_FONT, color: dark ? 'rgba(255,255,255,0.9)' : 'rgba(0,0,0,0.85)',
  };

  const DItem = ({ label, sublabel, onClick, icon }) => {
    const [hover, setHover] = React.useState(false);
    return (
      <div onMouseEnter={() => setHover(true)} onMouseLeave={() => setHover(false)}
        onClick={onClick || onClose}
        style={{
          display: 'flex', alignItems: 'center', gap: 8,
          padding: '5px 14px', margin: '0 4px', borderRadius: 5,
          background: hover ? '#007AFF' : 'transparent',
          color: hover ? '#fff' : 'inherit', cursor: 'default',
        }}>
        {icon && <div style={{ width: 8, height: 8, borderRadius: '50%', background: icon, flexShrink: 0, opacity: hover ? 0.9 : 0.7 }} />}
        <span style={{ flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', fontSize: 13 }}>{label}</span>
        {sublabel && <span style={{ fontSize: 11, opacity: hover ? 0.8 : 0.4, flexShrink: 0 }}>{sublabel}</span>}
      </div>
    );
  };

  const SectionLabel = ({ label }) => (
    <div style={{
      padding: '8px 18px 3px', fontSize: 11, fontWeight: 600,
      color: dark ? 'rgba(255,255,255,0.35)' : 'rgba(0,0,0,0.35)',
      letterSpacing: '0.02em',
    }}>{label}</div>
  );

  const Separator = () => (
    <div style={{ height: 0.5, margin: '4px 12px', background: dark ? 'rgba(255,255,255,0.1)' : 'rgba(0,0,0,0.08)' }} />
  );

  return (
    <div ref={ref} style={dropS}>
      <SectionLabel label="Recent" />
      {recentItems.map(item => (
        <DItem key={item.id}
          label={item.content ? item.content.split('\n')[0].substring(0, 40) : item.filename}
          sublabel={item.time}
          icon={item.appColor} />
      ))}
      <Separator />
      <SectionLabel label="Snippets" />
      {SNIPPET_ITEMS.slice(0, 3).map(item => (
        <DItem key={item.id} label={item.title} sublabel={item.keyword} icon="#AF52DE" />
      ))}
      <Separator />
      <DItem label="Open Clipboard…" sublabel="⌘⇧V" />
      <DItem label="Preferences…" sublabel="⌘," onClick={() => { onClose(); onOpenPrefs(); }} />
      <Separator />
      <DItem label="Quit Clipboard Manager" sublabel="⌘Q" />
    </div>
  );
}

// ─── Preferences Window ─────────────────────────────────────────────────────

const PREF_SECTIONS = ['General', 'Privacy', 'Snippets', 'Shortcuts', 'About'];

function PreferencesWindow({ dark, onClose }) {
  const [section, setSection] = React.useState('General');
  const [editingSnippet, setEditingSnippet] = React.useState(null);

  const overlayS = {
    position: 'fixed', inset: 0, zIndex: 10003,
    display: 'flex', alignItems: 'center', justifyContent: 'center',
    background: 'rgba(0,0,0,0.35)',
    backdropFilter: 'blur(4px)',
    animation: 'fadeIn 0.2s ease',
  };

  const winS = {
    width: 760, height: 520, borderRadius: 14, overflow: 'hidden',
    background: dark ? '#1e1e20' : '#fff',
    boxShadow: '0 0 0 0.5px rgba(0,0,0,0.2), 0 24px 80px rgba(0,0,0,0.4)',
    display: 'flex', position: 'relative',
    fontFamily: SCR_FONT,
    color: dark ? 'rgba(255,255,255,0.9)' : 'rgba(0,0,0,0.85)',
    animation: 'windowIn 0.3s cubic-bezier(0.25, 1, 0.5, 1)',
  };

  // Sidebar
  const sidebarS = {
    width: 200, flexShrink: 0, display: 'flex', flexDirection: 'column',
    background: dark ? 'rgba(255,255,255,0.04)' : 'rgba(0,0,0,0.02)',
    borderRight: `0.5px solid ${dark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)'}`,
    padding: '12px 0',
  };

  const trafficS = { display: 'flex', gap: 8, padding: '4px 16px 14px', alignItems: 'center' };
  const dot = (bg) => ({ width: 12, height: 12, borderRadius: '50%', background: bg, cursor: 'default' });

  const SideItem = ({ label, active }) => {
    const [hover, setHover] = React.useState(false);
    const iconColors = { General: '#007AFF', Privacy: '#FF9500', Snippets: '#AF52DE', Shortcuts: '#30D158', About: '#8E8E93' };
    return (
      <div onMouseEnter={() => setHover(true)} onMouseLeave={() => setHover(false)}
        onClick={() => setSection(label)}
        style={{
          display: 'flex', alignItems: 'center', gap: 8,
          padding: '6px 12px', margin: '1px 8px', borderRadius: 7,
          background: active ? (dark ? 'rgba(255,255,255,0.1)' : 'rgba(0,0,0,0.06)')
            : hover ? (dark ? 'rgba(255,255,255,0.05)' : 'rgba(0,0,0,0.03)') : 'transparent',
          cursor: 'default', fontSize: 13, fontWeight: active ? 600 : 400,
          transition: 'background 0.1s',
        }}>
        <div style={{
          width: 22, height: 22, borderRadius: 5, display: 'flex', alignItems: 'center', justifyContent: 'center',
          background: iconColors[label], color: '#fff', fontSize: 12, fontWeight: 700,
        }}>{label[0]}</div>
        {label}
      </div>
    );
  };

  const renderContent = () => {
    switch (section) {
      case 'General': return <PrefGeneral dark={dark} />;
      case 'Privacy': return <PrefPrivacy dark={dark} />;
      case 'Snippets': return <PrefSnippets dark={dark} onEdit={setEditingSnippet} />;
      case 'Shortcuts': return <PrefShortcuts dark={dark} />;
      case 'About': return <PrefAbout dark={dark} />;
      default: return null;
    }
  };

  return (
    <div style={overlayS} onClick={(e) => e.target === e.currentTarget && onClose()}>
      <div style={winS}>
        <div style={sidebarS}>
          <div style={trafficS}>
            <div style={dot('#ff736a')} onClick={onClose} />
            <div style={dot('#febc2e')} />
            <div style={dot('#19c332')} />
          </div>
          {PREF_SECTIONS.map(s => <SideItem key={s} label={s} active={section === s} />)}
        </div>
        <div style={{ flex: 1, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
          <div style={{ padding: '16px 24px 12px', fontSize: 18, fontWeight: 700, letterSpacing: '-0.02em', flexShrink: 0 }}>
            {section}
          </div>
          <div style={{ flex: 1, overflow: 'auto', padding: '0 24px 24px' }}>
            {renderContent()}
          </div>
        </div>
      </div>
      {editingSnippet && <SnippetEditor dark={dark} snippet={editingSnippet} onClose={() => setEditingSnippet(null)} />}
    </div>
  );
}

// ─── Pref Sections ──────────────────────────────────────────────────────────

function PrefRow({ label, children, dark, description }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '10px 0', gap: 16 }}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
        <span style={{ fontSize: 13, fontWeight: 500 }}>{label}</span>
        {description && <span style={{ fontSize: 11, color: dark ? 'rgba(255,255,255,0.4)' : 'rgba(0,0,0,0.35)' }}>{description}</span>}
      </div>
      {children}
    </div>
  );
}

function PrefToggle({ checked, dark }) {
  return (
    <div style={{
      width: 36, height: 20, borderRadius: 999, position: 'relative', cursor: 'default', flexShrink: 0,
      background: checked ? '#007AFF' : (dark ? 'rgba(255,255,255,0.15)' : 'rgba(0,0,0,0.12)'),
      transition: 'background 0.15s',
    }}>
      <div style={{
        width: 16, height: 16, borderRadius: '50%', background: '#fff',
        position: 'absolute', top: 2, left: checked ? 18 : 2,
        boxShadow: '0 1px 3px rgba(0,0,0,0.2)', transition: 'left 0.15s',
      }} />
    </div>
  );
}

function PrefSelect({ options, value, dark }) {
  return (
    <div style={{
      padding: '4px 10px', borderRadius: 6, fontSize: 12, fontWeight: 500, flexShrink: 0,
      background: dark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.05)',
      border: `0.5px solid ${dark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)'}`,
      color: dark ? 'rgba(255,255,255,0.7)' : 'rgba(0,0,0,0.6)',
      cursor: 'default', display: 'flex', gap: 4, alignItems: 'center',
    }}>
      {value || options[0]} <span style={{ opacity: 0.4, fontSize: 10 }}>▾</span>
    </div>
  );
}

function PrefDivider({ dark }) {
  return <div style={{ height: 0.5, background: dark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.06)', margin: '4px 0' }} />;
}

function PrefGeneral({ dark }) {
  return (
    <div>
      <PrefRow label="Launch at Login" dark={dark}><PrefToggle checked dark={dark} /></PrefRow>
      <PrefDivider dark={dark} />
      <PrefRow label="Global Hotkey" dark={dark}>
        <div style={{
          padding: '4px 10px', borderRadius: 6, fontSize: 12, fontWeight: 600, fontFamily: SCR_FONT,
          background: dark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.05)',
          border: `0.5px solid ${dark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)'}`,
          color: dark ? 'rgba(255,255,255,0.7)' : 'rgba(0,0,0,0.6)',
          letterSpacing: '0.02em',
        }}>⌘⇧V</div>
      </PrefRow>
      <PrefDivider dark={dark} />
      <PrefRow label="Appearance" description="Follow macOS system setting" dark={dark}>
        <PrefSelect options={['System', 'Light', 'Dark']} value="System" dark={dark} />
      </PrefRow>
      <PrefDivider dark={dark} />
      <PrefRow label="History Limit" description="Max items to keep" dark={dark}>
        <PrefSelect options={['500', '1000', '5000', 'Unlimited']} value="1000" dark={dark} />
      </PrefRow>
      <PrefDivider dark={dark} />
      <PrefRow label="Retention" description="Auto-delete items older than" dark={dark}>
        <PrefSelect options={['7 days', '30 days', '90 days', 'Forever']} value="30 days" dark={dark} />
      </PrefRow>
      <PrefDivider dark={dark} />
      <PrefRow label="Show Preview on Hover" dark={dark}><PrefToggle checked dark={dark} /></PrefRow>
      <PrefDivider dark={dark} />
      <PrefRow label="Sound Effects" dark={dark}><PrefToggle checked={false} dark={dark} /></PrefRow>
    </div>
  );
}

function PrefPrivacy({ dark }) {
  const excludedApps = ['1Password', 'Keychain Access'];
  return (
    <div>
      <PrefRow label="Respect Concealed Content" description="Don't capture passwords and sensitive fields" dark={dark}>
        <PrefToggle checked dark={dark} />
      </PrefRow>
      <PrefDivider dark={dark} />
      <PrefRow label="Pause Monitoring" dark={dark}>
        <div style={{ display: 'flex', gap: 6 }}>
          {['5 min', '15 min', '1 hour'].map(t => (
            <div key={t} style={{
              padding: '4px 10px', borderRadius: 6, fontSize: 11, fontWeight: 500,
              background: dark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.04)',
              border: `0.5px solid ${dark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)'}`,
              color: dark ? 'rgba(255,255,255,0.5)' : 'rgba(0,0,0,0.45)',
              cursor: 'default',
            }}>{t}</div>
          ))}
        </div>
      </PrefRow>
      <PrefDivider dark={dark} />
      <div style={{ padding: '10px 0' }}>
        <div style={{ fontSize: 13, fontWeight: 500, marginBottom: 8 }}>Excluded Apps</div>
        <div style={{ fontSize: 11, color: dark ? 'rgba(255,255,255,0.4)' : 'rgba(0,0,0,0.35)', marginBottom: 10 }}>
          Clipboard data from these apps will not be recorded
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
          {excludedApps.map(app => (
            <div key={app} style={{
              display: 'flex', alignItems: 'center', justifyContent: 'space-between',
              padding: '6px 10px', borderRadius: 7,
              background: dark ? 'rgba(255,255,255,0.04)' : 'rgba(0,0,0,0.02)',
              border: `0.5px solid ${dark ? 'rgba(255,255,255,0.05)' : 'rgba(0,0,0,0.04)'}`,
              fontSize: 12,
            }}>
              <span>{app}</span>
              <span style={{ opacity: 0.3, cursor: 'default', fontSize: 14 }}>×</span>
            </div>
          ))}
        </div>
        <div style={{
          marginTop: 8, padding: '20px', borderRadius: 8, textAlign: 'center',
          border: `1.5px dashed ${dark ? 'rgba(255,255,255,0.1)' : 'rgba(0,0,0,0.08)'}`,
          color: dark ? 'rgba(255,255,255,0.3)' : 'rgba(0,0,0,0.25)', fontSize: 12,
        }}>
          Drag apps here to exclude them
        </div>
      </div>
    </div>
  );
}

function PrefSnippets({ dark, onEdit }) {
  return (
    <div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
        {SNIPPET_ITEMS.map(s => (
          <div key={s.id} style={{
            display: 'flex', alignItems: 'center', gap: 10,
            padding: '10px 12px', borderRadius: 8,
            background: dark ? 'rgba(255,255,255,0.04)' : 'rgba(0,0,0,0.02)',
            border: `0.5px solid ${dark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.04)'}`,
            cursor: 'default',
          }}>
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 13, fontWeight: 600, marginBottom: 2 }}>{s.title}</div>
              <div style={{ fontSize: 11, color: dark ? 'rgba(255,255,255,0.4)' : 'rgba(0,0,0,0.35)',
                overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', maxWidth: 320 }}>
                {s.content.split('\n')[0]}
              </div>
            </div>
            {s.keyword && (
              <span style={{
                font: `500 11px ${SCR_MONO}`, color: '#AF52DE',
                background: dark ? 'rgba(175,82,222,0.12)' : 'rgba(175,82,222,0.08)',
                borderRadius: 4, padding: '2px 6px', flexShrink: 0,
              }}>{s.keyword}</span>
            )}
            <div onClick={() => onEdit(s)} style={{
              width: 26, height: 26, borderRadius: 6, display: 'flex',
              alignItems: 'center', justifyContent: 'center', cursor: 'default',
              color: dark ? 'rgba(255,255,255,0.3)' : 'rgba(0,0,0,0.25)',
              background: dark ? 'rgba(255,255,255,0.04)' : 'rgba(0,0,0,0.03)',
            }}>
              <svg width="12" height="12" viewBox="0 0 12 12" fill="none">
                <path d="M8.5 1.5l2 2-7 7H1.5v-2l7-7z" stroke="currentColor" strokeWidth="1.2" strokeLinecap="round" strokeLinejoin="round"/>
              </svg>
            </div>
          </div>
        ))}
      </div>
      <div style={{
        marginTop: 12, padding: '8px 0', display: 'flex', justifyContent: 'center',
      }}>
        <div style={{
          padding: '6px 16px', borderRadius: 7, fontSize: 12, fontWeight: 500,
          background: '#007AFF', color: '#fff', cursor: 'default',
        }}>
          + New Snippet
        </div>
      </div>
    </div>
  );
}

function PrefShortcuts({ dark }) {
  const shortcuts = [
    { label: 'Open Clipboard', key: '⌘⇧V' },
    { label: 'Paste as Plain Text', key: '⇧⏎' },
    { label: 'Quick Actions', key: '⌘.' },
    { label: 'Search', key: '/' },
    { label: 'Select Item 1-9', key: '⌘1-9' },
    { label: 'Navigate Left', key: '←' },
    { label: 'Navigate Right', key: '→' },
    { label: 'Delete Item', key: '⌫' },
    { label: 'Pin to Snippets', key: '⌘S' },
    { label: 'Dismiss', key: 'Esc' },
  ];
  return (
    <div>
      {shortcuts.map((s, i) => (
        <React.Fragment key={s.label}>
          <PrefRow label={s.label} dark={dark}>
            <div style={{
              padding: '4px 10px', borderRadius: 6, fontSize: 12, fontWeight: 600, fontFamily: SCR_FONT,
              background: dark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.05)',
              border: `0.5px solid ${dark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)'}`,
              color: dark ? 'rgba(255,255,255,0.6)' : 'rgba(0,0,0,0.5)',
              letterSpacing: '0.03em', cursor: 'default',
            }}>{s.key}</div>
          </PrefRow>
          {i < shortcuts.length - 1 && <PrefDivider dark={dark} />}
        </React.Fragment>
      ))}
    </div>
  );
}

function PrefAbout({ dark }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', paddingTop: 32, gap: 12 }}>
      <div style={{
        width: 72, height: 72, borderRadius: 16, display: 'flex', alignItems: 'center', justifyContent: 'center',
        background: 'linear-gradient(135deg, #007AFF, #5856D6)',
        boxShadow: '0 4px 16px rgba(0,122,255,0.3)',
      }}>
        <svg width="36" height="36" viewBox="0 0 24 24" fill="none">
          <rect x="5" y="2" width="14" height="18" rx="2" stroke="#fff" strokeWidth="1.5"/>
          <path d="M9 2V0M15 2V0" stroke="#fff" strokeWidth="1.5" strokeLinecap="round"/>
          <path d="M9 8h6M9 12h4" stroke="#fff" strokeWidth="1.5" strokeLinecap="round"/>
        </svg>
      </div>
      <div style={{ fontSize: 18, fontWeight: 700, letterSpacing: '-0.02em' }}>Clipboard Manager</div>
      <div style={{ fontSize: 12, color: dark ? 'rgba(255,255,255,0.4)' : 'rgba(0,0,0,0.35)' }}>Version 2.1.0 (Build 247)</div>
      <div style={{ fontSize: 11, color: dark ? 'rgba(255,255,255,0.3)' : 'rgba(0,0,0,0.25)', textAlign: 'center', lineHeight: 1.5, marginTop: 8 }}>
        © 2026 All rights reserved.
      </div>
      <div style={{
        marginTop: 16, padding: '6px 16px', borderRadius: 7, fontSize: 12, fontWeight: 500,
        background: dark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.04)',
        border: `0.5px solid ${dark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)'}`,
        cursor: 'default',
      }}>
        Check for Updates
      </div>
    </div>
  );
}

// ─── Snippet Editor ─────────────────────────────────────────────────────────

function SnippetEditor({ dark, snippet, onClose }) {
  const [title, setTitle] = React.useState(snippet?.title || '');
  const [body, setBody] = React.useState(snippet?.content || '');
  const [keyword, setKeyword] = React.useState(snippet?.keyword || '');

  const overlayS = {
    position: 'fixed', inset: 0, zIndex: 10005,
    display: 'flex', alignItems: 'center', justifyContent: 'center',
    background: 'rgba(0,0,0,0.3)',
  };

  const modalS = {
    width: 480, borderRadius: 14, overflow: 'hidden',
    background: dark ? '#2a2a2c' : '#fff',
    boxShadow: '0 0 0 0.5px rgba(0,0,0,0.2), 0 24px 60px rgba(0,0,0,0.35)',
    fontFamily: SCR_FONT, color: dark ? 'rgba(255,255,255,0.9)' : 'rgba(0,0,0,0.85)',
    animation: 'windowIn 0.25s cubic-bezier(0.25, 1, 0.5, 1)',
  };

  const fieldS = {
    width: '100%', boxSizing: 'border-box', border: 'none', outline: 'none',
    borderRadius: 7, padding: '8px 10px', fontFamily: SCR_FONT,
    background: dark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.03)',
    color: dark ? '#fff' : '#000', fontSize: 13,
  };

  return (
    <div style={overlayS} onClick={(e) => e.target === e.currentTarget && onClose()}>
      <div style={modalS}>
        <div style={{ padding: '16px 20px 12px', fontSize: 15, fontWeight: 700 }}>
          {snippet ? 'Edit Snippet' : 'New Snippet'}
        </div>
        <div style={{ padding: '0 20px 20px', display: 'flex', flexDirection: 'column', gap: 12 }}>
          <div>
            <label style={{ fontSize: 11, fontWeight: 600, color: dark ? 'rgba(255,255,255,0.5)' : 'rgba(0,0,0,0.45)', marginBottom: 4, display: 'block' }}>Title</label>
            <input value={title} onChange={e => setTitle(e.target.value)} style={fieldS} placeholder="e.g. Email Signature" />
          </div>
          <div>
            <label style={{ fontSize: 11, fontWeight: 600, color: dark ? 'rgba(255,255,255,0.5)' : 'rgba(0,0,0,0.45)', marginBottom: 4, display: 'block' }}>Body</label>
            <textarea value={body} onChange={e => setBody(e.target.value)} rows={5}
              style={{ ...fieldS, fontFamily: SCR_MONO, fontSize: 12, resize: 'vertical', lineHeight: 1.5 }}
              placeholder="Snippet content…" />
          </div>
          <div>
            <label style={{ fontSize: 11, fontWeight: 600, color: dark ? 'rgba(255,255,255,0.5)' : 'rgba(0,0,0,0.45)', marginBottom: 4, display: 'block' }}>
              Keyword <span style={{ fontWeight: 400 }}>(optional — type anywhere to expand)</span>
            </label>
            <input value={keyword} onChange={e => setKeyword(e.target.value)} style={{ ...fieldS, fontFamily: SCR_MONO }}
              placeholder="e.g. ;sig" />
            {keyword && (
              <div style={{ marginTop: 6, fontSize: 11, color: dark ? 'rgba(255,255,255,0.35)' : 'rgba(0,0,0,0.3)' }}>
                Typing <span style={{ fontFamily: SCR_MONO, color: '#AF52DE' }}>{keyword}</span> will auto-expand to the body text
              </div>
            )}
          </div>

          {/* Live preview */}
          <div>
            <label style={{ fontSize: 11, fontWeight: 600, color: dark ? 'rgba(255,255,255,0.5)' : 'rgba(0,0,0,0.45)', marginBottom: 6, display: 'block' }}>Preview</label>
            <div style={{
              padding: '10px 12px', borderRadius: 8,
              background: dark ? 'rgba(255,255,255,0.04)' : 'rgba(0,0,0,0.02)',
              border: `0.5px solid ${dark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.04)'}`,
              minHeight: 40,
            }}>
              <div style={{ fontSize: 12, fontWeight: 600, marginBottom: 3, color: dark ? 'rgba(255,255,255,0.8)' : 'rgba(0,0,0,0.7)' }}>
                {title || 'Untitled'}
              </div>
              <div style={{ fontSize: 11, color: dark ? 'rgba(255,255,255,0.4)' : 'rgba(0,0,0,0.35)', whiteSpace: 'pre-wrap', fontFamily: SCR_MONO, lineHeight: 1.5 }}>
                {body || 'No content'}
              </div>
            </div>
          </div>

          <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8, marginTop: 4 }}>
            <div onClick={onClose} style={{
              padding: '7px 16px', borderRadius: 7, fontSize: 13, fontWeight: 500,
              background: dark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.04)',
              cursor: 'default',
            }}>Cancel</div>
            <div onClick={onClose} style={{
              padding: '7px 16px', borderRadius: 7, fontSize: 13, fontWeight: 600,
              background: '#007AFF', color: '#fff', cursor: 'default',
            }}>Save</div>
          </div>
        </div>
      </div>
    </div>
  );
}

// ─── Onboarding Flow ────────────────────────────────────────────────────────

function OnboardingFlow({ dark, onClose }) {
  const [step, setStep] = React.useState(0);

  const overlayS = {
    position: 'fixed', inset: 0, zIndex: 10004,
    display: 'flex', alignItems: 'center', justifyContent: 'center',
    background: dark ? 'rgba(0,0,0,0.6)' : 'rgba(0,0,0,0.35)',
    backdropFilter: 'blur(8px)',
    animation: 'fadeIn 0.3s ease',
  };

  const steps = [
    {
      title: 'Welcome to Clipboard Manager',
      description: 'A beautiful, powerful clipboard history for macOS. Everything you copy is saved, searchable, and ready to paste.',
      icon: (
        <svg width="48" height="48" viewBox="0 0 24 24" fill="none">
          <rect x="5" y="2" width="14" height="18" rx="2" stroke="#007AFF" strokeWidth="1.5"/>
          <path d="M9 2V0M15 2V0" stroke="#007AFF" strokeWidth="1.5" strokeLinecap="round"/>
          <path d="M9 8h6M9 12h4" stroke="#007AFF" strokeWidth="1.5" strokeLinecap="round"/>
        </svg>
      ),
      buttonLabel: 'Get Started',
    },
    {
      title: 'Enable Accessibility',
      description: 'Clipboard Manager needs Accessibility access to paste items into other apps and enable keyword expansion for snippets.',
      icon: (
        <svg width="48" height="48" viewBox="0 0 24 24" fill="none">
          <circle cx="12" cy="12" r="10" stroke="#FF9500" strokeWidth="1.5"/>
          <circle cx="12" cy="12" r="3" fill="#FF9500"/>
          <path d="M12 2v3M12 19v3M2 12h3M19 12h3" stroke="#FF9500" strokeWidth="1.5" strokeLinecap="round"/>
        </svg>
      ),
      buttonLabel: 'Open System Settings',
      whyText: 'This permission lets the app simulate ⌘V to paste and detect keyword triggers. No data leaves your Mac.',
    },
    {
      title: 'Set Your Hotkey',
      description: 'Press ⌘⇧V anywhere to open the clipboard drawer. You can customize this anytime in Preferences.',
      icon: (
        <svg width="48" height="48" viewBox="0 0 24 24" fill="none">
          <rect x="2" y="6" width="20" height="14" rx="3" stroke="#30D158" strokeWidth="1.5"/>
          <rect x="5" y="9" width="4" height="4" rx="1" fill="#30D158" opacity="0.3"/>
          <rect x="10" y="9" width="4" height="4" rx="1" fill="#30D158" opacity="0.3"/>
          <rect x="15" y="9" width="4" height="4" rx="1" fill="#30D158"/>
          <rect x="7" y="14" width="10" height="3" rx="1" fill="#30D158" opacity="0.3"/>
        </svg>
      ),
      buttonLabel: 'Done',
    },
  ];

  const s = steps[step];

  const cardS = {
    width: 420, borderRadius: 18, overflow: 'hidden', textAlign: 'center',
    background: dark ? 'rgba(35,35,38,0.98)' : 'rgba(255,255,255,0.99)',
    backdropFilter: 'blur(40px)',
    boxShadow: '0 0 0 0.5px rgba(0,0,0,0.15), 0 24px 60px rgba(0,0,0,0.3)',
    fontFamily: SCR_FONT, color: dark ? 'rgba(255,255,255,0.9)' : 'rgba(0,0,0,0.85)',
    animation: 'windowIn 0.35s cubic-bezier(0.25, 1, 0.5, 1)',
    padding: '40px 36px 32px',
  };

  return (
    <div style={overlayS}>
      <div style={cardS} key={step}>
        {/* Step dots */}
        <div style={{ display: 'flex', gap: 6, justifyContent: 'center', marginBottom: 28 }}>
          {steps.map((_, i) => (
            <div key={i} style={{
              width: i === step ? 20 : 6, height: 6, borderRadius: 3,
              background: i === step ? '#007AFF' : (dark ? 'rgba(255,255,255,0.15)' : 'rgba(0,0,0,0.1)'),
              transition: 'all 0.3s ease',
            }} />
          ))}
        </div>

        {/* Icon */}
        <div style={{ marginBottom: 20, display: 'flex', justifyContent: 'center' }}>
          <div style={{
            width: 80, height: 80, borderRadius: 20, display: 'flex', alignItems: 'center', justifyContent: 'center',
            background: dark ? 'rgba(255,255,255,0.04)' : 'rgba(0,0,0,0.02)',
          }}>
            {s.icon}
          </div>
        </div>

        <div style={{ fontSize: 20, fontWeight: 700, letterSpacing: '-0.02em', marginBottom: 10 }}>
          {s.title}
        </div>
        <div style={{
          fontSize: 13, lineHeight: 1.6, color: dark ? 'rgba(255,255,255,0.55)' : 'rgba(0,0,0,0.5)',
          marginBottom: 24, maxWidth: 340, margin: '0 auto 24px',
        }}>
          {s.description}
        </div>

        {s.whyText && (
          <div style={{
            fontSize: 11, lineHeight: 1.5, padding: '10px 14px', borderRadius: 8, marginBottom: 20,
            background: dark ? 'rgba(255,149,0,0.08)' : 'rgba(255,149,0,0.06)',
            color: dark ? 'rgba(255,255,255,0.6)' : 'rgba(0,0,0,0.55)',
            textAlign: 'left',
          }}>
            <strong>Why?</strong> {s.whyText}
          </div>
        )}

        <div style={{ display: 'flex', gap: 10, justifyContent: 'center' }}>
          {step > 0 && (
            <div onClick={() => setStep(step - 1)} style={{
              padding: '9px 20px', borderRadius: 9, fontSize: 14, fontWeight: 500,
              background: dark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.04)',
              cursor: 'default',
            }}>Back</div>
          )}
          <div onClick={() => step < 2 ? setStep(step + 1) : onClose()} style={{
            padding: '9px 24px', borderRadius: 9, fontSize: 14, fontWeight: 600,
            background: '#007AFF', color: '#fff', cursor: 'default',
          }}>{s.buttonLabel}</div>
        </div>
      </div>
    </div>
  );
}

// ─── Empty State ────────────────────────────────────────────────────────────

function EmptyState({ dark }) {
  return (
    <div style={{
      flex: 1, display: 'flex', flexDirection: 'column',
      alignItems: 'center', justifyContent: 'center', gap: 12,
      fontFamily: SCR_FONT, padding: 40,
    }}>
      <svg width="56" height="56" viewBox="0 0 24 24" fill="none" style={{ opacity: 0.2 }}>
        <rect x="5" y="2" width="14" height="18" rx="2" stroke="currentColor" strokeWidth="1.2"/>
        <path d="M9 2V0M15 2V0" stroke="currentColor" strokeWidth="1.2" strokeLinecap="round"/>
        <path d="M9 9h6M9 13h3" stroke="currentColor" strokeWidth="1.2" strokeLinecap="round"/>
      </svg>
      <div style={{
        fontSize: 15, fontWeight: 600, letterSpacing: '-0.01em',
        color: dark ? 'rgba(255,255,255,0.35)' : 'rgba(0,0,0,0.3)',
      }}>
        Your clipboard is empty
      </div>
      <div style={{
        fontSize: 12, color: dark ? 'rgba(255,255,255,0.2)' : 'rgba(0,0,0,0.18)',
        textAlign: 'center', lineHeight: 1.5, maxWidth: 260,
      }}>
        Copy something to get started. Text, images, and files will appear here automatically.
      </div>
    </div>
  );
}

Object.assign(window, {
  MenuBarDropdown, PreferencesWindow, SnippetEditor,
  OnboardingFlow, EmptyState,
});
