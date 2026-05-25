// drawer.jsx — Bottom Drawer components for macOS Clipboard Manager
// Components: ClipboardCard, TabBar, SearchField, HoverPreview, ContextMenu, BottomDrawer

const FONT = '-apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro", "Helvetica Neue", sans-serif';
const MONO = '"SF Mono", ui-monospace, "SFMono-Regular", Menlo, Consolas, monospace';

// ─── Sample Data ────────────────────────────────────────────────────────────

const CLIPBOARD_ITEMS = [
  {
    id: 1, type: 'text', subtype: 'code',
    content: `const handlePaste = async () => {\n  const text = await navigator\n    .clipboard.readText();\n  setItems(prev => [\n    { id: Date.now(), text },\n    ...prev\n  ]);\n};`,
    app: 'VS Code', appColor: '#007ACC', time: '2m ago',
  },
  {
    id: 2, type: 'image', subtype: 'screenshot',
    gradient: 'linear-gradient(135deg, #1a1a2e 0%, #16213e 40%, #0f3460 100%)',
    dimensions: '2560 × 1440', app: 'Screenshot', appColor: '#8E8E93', time: '5m ago',
  },
  {
    id: 3, type: 'text', subtype: 'url',
    content: 'https://github.com/user/clipboard-manager/pull/42',
    app: 'Safari', appColor: '#007AFF', time: '8m ago',
  },
  {
    id: 4, type: 'text', subtype: 'json',
    content: `{\n  "name": "clipboard-app",\n  "version": "2.1.0",\n  "author": "Alex Chen",\n  "license": "MIT"\n}`,
    app: 'VS Code', appColor: '#007ACC', time: '12m ago',
  },
  {
    id: 5, type: 'file',
    filename: 'Q2 Report.pdf', path: '~/Documents/Reports/', size: '2.4 MB',
    app: 'Finder', appColor: '#30D158', time: '15m ago',
  },
  {
    id: 6, type: 'text', subtype: 'plain',
    content: 'Hey team, the new clipboard manager is looking great! Can we schedule a review for Thursday afternoon?',
    app: 'Messages', appColor: '#30D158', time: '22m ago',
  },
  {
    id: 7, type: 'image', subtype: 'design',
    gradient: 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)',
    dimensions: '1440 × 900', app: 'Figma', appColor: '#A259FF', time: '35m ago',
  },
  {
    id: 8, type: 'text', subtype: 'code',
    content: 'brew install --cask clipboard-manager && open -a "Clipboard Manager"',
    app: 'Terminal', appColor: '#8E8E93', time: '1h ago',
  },
  {
    id: 9, type: 'file',
    filename: 'Design System v3.fig', path: '~/Projects/Design/', size: '18.7 MB',
    app: 'Finder', appColor: '#30D158', time: '1h ago',
  },
  {
    id: 10, type: 'text', subtype: 'code',
    content: `SELECT u.name, u.email\nFROM users u\nJOIN orders o ON u.id = o.user_id\nWHERE o.total > 100\nORDER BY o.created_at DESC;`,
    app: 'TablePlus', appColor: '#FF6F61', time: '2h ago',
  },
  {
    id: 11, type: 'text', subtype: 'plain',
    content: '1600 Amphitheatre Parkway, Mountain View, CA 94043',
    app: 'Maps', appColor: '#30D158', time: '3h ago',
  },
  {
    id: 12, type: 'image', subtype: 'photo',
    gradient: 'linear-gradient(135deg, #43e97b 0%, #38f9d7 100%)',
    dimensions: '4032 × 3024', app: 'Photos', appColor: '#FF375F', time: '4h ago',
  },
];

const SNIPPET_ITEMS = [
  { id: 101, type: 'snippet', title: 'Email Signature', keyword: ';sig',
    content: 'Best regards,\nAlex Chen\nSenior Engineer\nalex@company.com\n+1 (555) 012-3456', app: 'Snippets', appColor: '#AF52DE', time: 'Pinned' },
  { id: 102, type: 'snippet', title: 'Zoom Link', keyword: ';zoom',
    content: 'https://zoom.us/j/1234567890?pwd=aBcDeFgHiJ', app: 'Snippets', appColor: '#AF52DE', time: 'Pinned' },
  { id: 103, type: 'snippet', title: 'SSH Key Path', keyword: ';ssh',
    content: '~/.ssh/id_ed25519.pub', app: 'Snippets', appColor: '#AF52DE', time: 'Pinned' },
  { id: 104, type: 'snippet', title: 'Thanks Reply', keyword: ';thanks',
    content: 'Thanks for reaching out! I appreciate your message and will get back to you within 24 hours.', app: 'Snippets', appColor: '#AF52DE', time: 'Pinned' },
  { id: 105, type: 'snippet', title: 'Lorem Ipsum', keyword: ';lorem',
    content: 'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore.', app: 'Snippets', appColor: '#AF52DE', time: 'Pinned' },
];

// ─── Tab Bar ────────────────────────────────────────────────────────────────

const TABS = [
  { id: 'all', label: 'All', icon: null },
  { id: 'text', label: 'Text', icon: null },
  { id: 'images', label: 'Images', icon: null },
  { id: 'files', label: 'Files', icon: null },
  { id: 'pinned', label: 'Pinned', icon: null },
];

function DrawerTabBar({ activeTab, onTabChange, dark }) {
  const tabBarS = {
    display: 'flex', gap: 2, padding: '3px',
    borderRadius: 8,
    background: dark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.04)',
  };
  const tabS = (active) => ({
    padding: '5px 14px', border: 'none', borderRadius: 6,
    font: `500 12px/1 ${FONT}`, cursor: 'default',
    color: active
      ? (dark ? 'rgba(255,255,255,0.95)' : 'rgba(0,0,0,0.85)')
      : (dark ? 'rgba(255,255,255,0.45)' : 'rgba(0,0,0,0.4)'),
    background: active
      ? (dark ? 'rgba(255,255,255,0.12)' : 'rgba(0,0,0,0.08)')
      : 'transparent',
    transition: 'all 0.15s ease',
    letterSpacing: '-0.01em',
  });

  return (
    <div style={tabBarS}>
      {TABS.map(tab => (
        <button key={tab.id} style={tabS(activeTab === tab.id)}
          onClick={() => onTabChange(tab.id)}>
          {tab.label}
        </button>
      ))}
    </div>
  );
}

// ─── Search Field ───────────────────────────────────────────────────────────

function DrawerSearch({ searchQuery, onSearch, expanded, onExpand, dark }) {
  const inputRef = React.useRef(null);

  React.useEffect(() => {
    if (expanded && inputRef.current) inputRef.current.focus();
  }, [expanded]);

  const wrapS = {
    display: 'flex', alignItems: 'center', gap: 6,
    padding: '0 10px', height: 28,
    borderRadius: 7,
    background: dark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.05)',
    border: expanded
      ? `1px solid ${dark ? 'rgba(255,255,255,0.15)' : 'rgba(0,0,0,0.1)'}`
      : '1px solid transparent',
    width: expanded ? 220 : 32,
    transition: 'width 0.25s cubic-bezier(0.25, 1, 0.5, 1), border 0.15s',
    cursor: expanded ? 'text' : 'default',
    overflow: 'hidden', flexShrink: 0,
  };

  const iconS = { opacity: dark ? 0.4 : 0.35, flexShrink: 0 };

  return (
    <div style={wrapS} onClick={() => !expanded && onExpand(true)}>
      <svg width="13" height="13" viewBox="0 0 13 13" fill="none" style={iconS}>
        <circle cx="5.5" cy="5.5" r="4" stroke="currentColor" strokeWidth="1.5"/>
        <path d="M8.5 8.5l3 3" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round"/>
      </svg>
      {expanded && (
        <>
          <input ref={inputRef} value={searchQuery} onChange={e => onSearch(e.target.value)}
            placeholder="Search clipboard…"
            onKeyDown={e => e.key === 'Escape' && (onSearch(''), onExpand(false))}
            style={{
              flex: 1, border: 'none', background: 'none', outline: 'none',
              font: `13px ${FONT}`, color: dark ? '#fff' : '#000',
              padding: 0, minWidth: 0,
            }}
          />
          {searchQuery && (
            <button onClick={() => onSearch('')} style={{
              border: 'none', background: dark ? 'rgba(255,255,255,0.15)' : 'rgba(0,0,0,0.1)',
              borderRadius: '50%', width: 16, height: 16, padding: 0,
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              cursor: 'default', flexShrink: 0, color: dark ? '#fff' : '#000',
            }}>
              <svg width="8" height="8" viewBox="0 0 8 8" fill="none">
                <path d="M1 1l6 6M7 1l-6 6" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round"/>
              </svg>
            </button>
          )}
        </>
      )}
    </div>
  );
}

// ─── File Type Icons ────────────────────────────────────────────────────────

function FileIcon({ filename, dark }) {
  const ext = filename.split('.').pop().toLowerCase();
  const colors = { pdf: '#FF3B30', fig: '#A259FF', sketch: '#FF9500',
    key: '#007AFF', xlsx: '#30D158', docx: '#007AFF', zip: '#8E8E93',
    png: '#FF375F', jpg: '#FF375F', mp4: '#AF52DE' };
  const color = colors[ext] || '#8E8E93';
  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 8,
      padding: '16px 12px 8px', flex: 1 }}>
      <svg width="48" height="56" viewBox="0 0 48 56" fill="none">
        <path d="M4 0h26l14 14v38a4 4 0 01-4 4H4a4 4 0 01-4-4V4a4 4 0 014-4z"
          fill={dark ? 'rgba(255,255,255,0.1)' : 'rgba(0,0,0,0.06)'} />
        <path d="M30 0l14 14H34a4 4 0 01-4-4V0z"
          fill={dark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.03)'} />
        <rect x="8" y="34" width="32" height="14" rx="3" fill={color} opacity="0.9" />
        <text x="24" y="45" textAnchor="middle" fill="#fff"
          style={{ font: `bold 9px ${FONT}`, letterSpacing: '0.02em' }}>
          .{ext.toUpperCase()}
        </text>
      </svg>
      <span style={{
        font: `500 11px/1.2 ${FONT}`, textAlign: 'center',
        color: dark ? 'rgba(255,255,255,0.85)' : 'rgba(0,0,0,0.75)',
        maxWidth: '100%', overflow: 'hidden', textOverflow: 'ellipsis',
        whiteSpace: 'nowrap', padding: '0 4px',
      }}>{filename}</span>
    </div>
  );
}

// ─── Clipboard Card ─────────────────────────────────────────────────────────

function ClipboardCard({ item, focused, dark, onHover, onLeave, onContextMenu, onClick, searchQuery }) {
  const [hovered, setHovered] = React.useState(false);
  const isSnippet = item.type === 'snippet';
  const isImage = item.type === 'image';
  const isFile = item.type === 'file';
  const isCode = item.subtype === 'code' || item.subtype === 'json';
  const isUrl = item.subtype === 'url';

  const tintMap = { text: 'transparent', image: dark ? 'rgba(0,122,255,0.08)' : 'rgba(0,122,255,0.05)',
    file: dark ? 'rgba(255,149,0,0.08)' : 'rgba(255,149,0,0.05)',
    snippet: dark ? 'rgba(175,82,222,0.08)' : 'rgba(175,82,222,0.05)' };
  const tint = tintMap[item.type] || 'transparent';

  const cardS = {
    width: 184, minWidth: 184, height: 210, borderRadius: 12, overflow: 'hidden',
    display: 'flex', flexDirection: 'column',
    background: dark ? 'rgba(255,255,255,0.06)' : 'rgba(255,255,255,0.72)',
    border: focused ? `2px solid #007AFF` : `0.5px solid ${dark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)'}`,
    boxShadow: focused
      ? '0 8px 32px rgba(0,122,255,0.2), 0 2px 8px rgba(0,0,0,0.12)'
      : hovered
        ? (dark ? '0 8px 24px rgba(0,0,0,0.3)' : '0 4px 16px rgba(0,0,0,0.1)')
        : (dark ? '0 1px 4px rgba(0,0,0,0.2)' : '0 1px 3px rgba(0,0,0,0.05)'),
    transform: hovered ? 'scale(1.03) translateY(-4px)' : 'scale(1)',
    transition: 'transform 0.15s cubic-bezier(0.25, 1, 0.5, 1), box-shadow 0.15s ease, border 0.15s',
    cursor: 'default', position: 'relative', flexShrink: 0,
  };

  const contentS = {
    flex: 1, overflow: 'hidden', position: 'relative',
    background: tint,
  };

  const highlightText = (text) => {
    if (!searchQuery) return text;
    const regex = new RegExp(`(${searchQuery.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')})`, 'gi');
    const parts = text.split(regex);
    return parts.map((part, i) =>
      regex.test(part) ? <mark key={i} style={{
        background: 'rgba(0,122,255,0.3)', color: 'inherit',
        borderRadius: 2, padding: '0 1px',
      }}>{part}</mark> : part
    );
  };

  const renderContent = () => {
    if (isImage) {
      return (
        <div style={{ position: 'absolute', inset: 0, background: item.gradient,
          display: 'flex', alignItems: 'flex-end', justifyContent: 'flex-end', padding: 8 }}>
          <span style={{
            font: `500 10px ${FONT}`, color: 'rgba(255,255,255,0.8)',
            background: 'rgba(0,0,0,0.4)', borderRadius: 4, padding: '2px 6px',
            backdropFilter: 'blur(8px)',
          }}>{item.dimensions}</span>
        </div>
      );
    }
    if (isFile) {
      return <FileIcon filename={item.filename} dark={dark} />;
    }
    // Text content
    return (
      <div style={{
        padding: '10px 12px', height: '100%', overflow: 'hidden',
        font: `${isCode ? `11.5px/1.5 ${MONO}` : `12.5px/1.55 ${FONT}`}`,
        color: dark ? 'rgba(255,255,255,0.8)' : 'rgba(0,0,0,0.7)',
        whiteSpace: 'pre-wrap', wordBreak: 'break-word',
        textDecoration: isUrl ? 'underline' : 'none',
        WebkitMaskImage: 'linear-gradient(180deg, black 65%, transparent 100%)',
        maskImage: 'linear-gradient(180deg, black 65%, transparent 100%)',
      }}>
        {highlightText(item.content)}
      </div>
    );
  };

  const footerS = {
    display: 'flex', alignItems: 'center', gap: 6,
    padding: '8px 10px', borderTop: `0.5px solid ${dark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.04)'}`,
    flexShrink: 0,
  };

  return (
    <div style={cardS}
      onMouseEnter={(e) => { setHovered(true); onHover && onHover(item, e); }}
      onMouseLeave={() => { setHovered(false); onLeave && onLeave(); }}
      onContextMenu={(e) => { e.preventDefault(); onContextMenu && onContextMenu(item, e); }}
      onClick={() => onClick && onClick(item)}
    >
      {/* Snippet title bar */}
      {isSnippet && (
        <div style={{
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          padding: '7px 10px 0',
        }}>
          <span style={{
            font: `600 11.5px/1 ${FONT}`,
            color: dark ? 'rgba(255,255,255,0.9)' : 'rgba(0,0,0,0.8)',
            letterSpacing: '-0.01em',
          }}>{item.title}</span>
          {item.keyword && (
            <span style={{
              font: `500 10px/1 ${MONO}`,
              color: '#AF52DE', background: dark ? 'rgba(175,82,222,0.15)' : 'rgba(175,82,222,0.1)',
              borderRadius: 4, padding: '2px 5px',
            }}>{item.keyword}</span>
          )}
        </div>
      )}

      {/* Content preview */}
      <div style={contentS}>{renderContent()}</div>

      {/* Footer */}
      <div style={footerS}>
        <div style={{
          width: 10, height: 10, borderRadius: '50%',
          background: item.appColor, flexShrink: 0,
        }} />
        <span style={{
          font: `500 10.5px/1 ${FONT}`, flex: 1,
          color: dark ? 'rgba(255,255,255,0.5)' : 'rgba(0,0,0,0.4)',
          overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
        }}>{item.app}</span>
        <span style={{
          font: `400 10px/1 ${FONT}`,
          color: dark ? 'rgba(255,255,255,0.3)' : 'rgba(0,0,0,0.25)',
          flexShrink: 0,
        }}>{item.time}</span>
      </div>
    </div>
  );
}

// ─── Hover Preview Popover ──────────────────────────────────────────────────

function HoverPreview({ item, position, dark }) {
  if (!item || !position) return null;
  const isImage = item.type === 'image';
  const isFile = item.type === 'file';
  const isCode = item.subtype === 'code' || item.subtype === 'json';

  const popoverS = {
    position: 'fixed', left: position.x, bottom: position.y,
    width: isImage ? 380 : 340, maxHeight: 300,
    borderRadius: 14, overflow: 'hidden',
    background: dark ? 'rgba(35,35,38,0.95)' : 'rgba(255,255,255,0.96)',
    backdropFilter: 'blur(40px) saturate(180%)',
    WebkitBackdropFilter: 'blur(40px) saturate(180%)',
    border: `0.5px solid ${dark ? 'rgba(255,255,255,0.12)' : 'rgba(0,0,0,0.08)'}`,
    boxShadow: dark
      ? '0 16px 48px rgba(0,0,0,0.4), 0 0 0 0.5px rgba(255,255,255,0.08)'
      : '0 16px 48px rgba(0,0,0,0.15), 0 0 0 0.5px rgba(0,0,0,0.06)',
    zIndex: 10000,
    animation: 'popoverIn 0.2s cubic-bezier(0.25, 1, 0.5, 1)',
    pointerEvents: 'none',
    transform: 'translateX(-50%)',
  };

  return (
    <div style={popoverS}>
      {isImage && (
        <div style={{ height: 200, background: item.gradient, position: 'relative' }}>
          <div style={{
            position: 'absolute', bottom: 8, right: 8, display: 'flex', gap: 6,
          }}>
            <span style={{
              font: `500 11px ${FONT}`, color: 'rgba(255,255,255,0.9)',
              background: 'rgba(0,0,0,0.5)', borderRadius: 6, padding: '3px 8px',
              backdropFilter: 'blur(8px)',
            }}>{item.dimensions}</span>
            <span style={{
              font: `500 11px ${FONT}`, color: 'rgba(255,255,255,0.9)',
              background: 'rgba(0,0,0,0.5)', borderRadius: 6, padding: '3px 8px',
              backdropFilter: 'blur(8px)',
            }}>{item.app}</span>
          </div>
        </div>
      )}
      {isFile && (
        <div style={{ padding: '20px 16px', display: 'flex', gap: 14, alignItems: 'center' }}>
          <FileIcon filename={item.filename} dark={dark} />
          <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
            <span style={{ font: `600 13px ${FONT}`, color: dark ? '#fff' : '#000' }}>
              {item.filename}
            </span>
            <span style={{ font: `400 11px ${FONT}`, color: dark ? 'rgba(255,255,255,0.5)' : 'rgba(0,0,0,0.45)' }}>
              {item.path}
            </span>
            <span style={{ font: `400 11px ${FONT}`, color: dark ? 'rgba(255,255,255,0.4)' : 'rgba(0,0,0,0.35)' }}>
              {item.size}
            </span>
          </div>
        </div>
      )}
      {!isImage && !isFile && (
        <div style={{
          padding: '14px 16px', maxHeight: 280, overflow: 'auto',
          font: `${isCode ? `12px/1.6 ${MONO}` : `13px/1.6 ${FONT}`}`,
          color: dark ? 'rgba(255,255,255,0.85)' : 'rgba(0,0,0,0.8)',
          whiteSpace: 'pre-wrap', wordBreak: 'break-word',
        }}>
          {item.content}
        </div>
      )}
    </div>
  );
}

// ─── Context Menu ───────────────────────────────────────────────────────────

function ContextMenu({ item, position, dark, onClose }) {
  if (!item || !position) return null;
  const isUrl = item.subtype === 'url';
  const isFile = item.type === 'file';
  const isCode = item.subtype === 'code' || item.subtype === 'json';

  const menuRef = React.useRef(null);
  React.useEffect(() => {
    const handler = (e) => {
      if (menuRef.current && !menuRef.current.contains(e.target)) onClose();
    };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, [onClose]);

  const menuS = {
    position: 'fixed', left: position.x, top: position.y,
    minWidth: 230, borderRadius: 10, overflow: 'hidden', padding: '4px 0',
    background: dark ? 'rgba(40,40,42,0.98)' : 'rgba(255,255,255,0.98)',
    backdropFilter: 'blur(50px) saturate(200%)',
    WebkitBackdropFilter: 'blur(50px) saturate(200%)',
    border: `0.5px solid ${dark ? 'rgba(255,255,255,0.15)' : 'rgba(0,0,0,0.1)'}`,
    boxShadow: dark
      ? '0 12px 40px rgba(0,0,0,0.5), 0 0 0 0.5px rgba(255,255,255,0.1)'
      : '0 12px 40px rgba(0,0,0,0.2), 0 0 0 0.5px rgba(0,0,0,0.05)',
    zIndex: 10001, animation: 'menuIn 0.12s ease-out',
    font: `13px/1 ${FONT}`,
    color: dark ? 'rgba(255,255,255,0.9)' : 'rgba(0,0,0,0.85)',
  };

  const MenuItem = ({ label, shortcut, disabled, danger }) => {
    const [hover, setHover] = React.useState(false);
    return (
      <div onMouseEnter={() => setHover(true)} onMouseLeave={() => setHover(false)}
        onClick={() => !disabled && onClose()}
        style={{
          display: 'flex', justifyContent: 'space-between', alignItems: 'center',
          padding: '5px 14px', margin: '0 4px', borderRadius: 5,
          background: hover && !disabled ? '#007AFF' : 'transparent',
          color: hover && !disabled ? '#fff' : disabled ? (dark ? 'rgba(255,255,255,0.25)' : 'rgba(0,0,0,0.25)') : danger ? '#FF3B30' : 'inherit',
          cursor: disabled ? 'default' : 'default',
        }}>
        <span>{label}</span>
        {shortcut && <span style={{
          font: `12px ${FONT}`, opacity: hover ? 0.8 : 0.4,
          color: hover ? '#fff' : 'inherit',
        }}>{shortcut}</span>}
      </div>
    );
  };

  const Separator = () => (
    <div style={{
      height: 0.5, margin: '4px 12px',
      background: dark ? 'rgba(255,255,255,0.1)' : 'rgba(0,0,0,0.08)',
    }} />
  );

  return (
    <div ref={menuRef} style={menuS}>
      <MenuItem label="Paste" shortcut="⏎" />
      <MenuItem label="Paste as Plain Text" shortcut="⇧⏎" />
      <MenuItem label="Copy without Pasting" shortcut="⌘C" />
      <Separator />
      <MenuItem label="Transform ▸" />
      <MenuItem label="Encode/Decode ▸" />
      {isCode && <MenuItem label="Pretty Print JSON" shortcut="⌘P" />}
      <MenuItem label="Trim Whitespace" />
      <Separator />
      {isUrl && <MenuItem label="Open URL" shortcut="⌘O" />}
      {isFile && <MenuItem label="Reveal in Finder" shortcut="⌘F" />}
      <MenuItem label="Pin to Snippets" shortcut="⌘S" />
      <Separator />
      <MenuItem label="Delete" shortcut="⌫" danger />
    </div>
  );
}

// ─── Bottom Drawer ──────────────────────────────────────────────────────────

function BottomDrawer({ dark, visible, onOpenPrefs, onOpenMenuBar }) {
  const [activeTab, setActiveTab] = React.useState('all');
  const [searchQuery, setSearchQuery] = React.useState('');
  const [searchExpanded, setSearchExpanded] = React.useState(false);
  const [focusedIndex, setFocusedIndex] = React.useState(0);
  const [hoverItem, setHoverItem] = React.useState(null);
  const [hoverPos, setHoverPos] = React.useState(null);
  const [contextItem, setContextItem] = React.useState(null);
  const [contextPos, setContextPos] = React.useState(null);
  const hoverTimer = React.useRef(null);
  const scrollRef = React.useRef(null);

  // Filter items by tab and search
  const baseItems = activeTab === 'pinned' ? SNIPPET_ITEMS :
    activeTab === 'all' ? CLIPBOARD_ITEMS :
    activeTab === 'text' ? CLIPBOARD_ITEMS.filter(i => i.type === 'text') :
    activeTab === 'images' ? CLIPBOARD_ITEMS.filter(i => i.type === 'image') :
    activeTab === 'files' ? CLIPBOARD_ITEMS.filter(i => i.type === 'file') :
    CLIPBOARD_ITEMS;

  const items = searchQuery
    ? baseItems.filter(i => {
        const text = (i.content || i.filename || i.title || '').toLowerCase();
        return text.includes(searchQuery.toLowerCase());
      })
    : baseItems;

  React.useEffect(() => { setFocusedIndex(0); }, [activeTab, searchQuery]);

  // Keyboard navigation
  React.useEffect(() => {
    const handler = (e) => {
      if (e.key === 'ArrowRight') setFocusedIndex(i => Math.min(i + 1, items.length - 1));
      if (e.key === 'ArrowLeft') setFocusedIndex(i => Math.max(i - 1, 0));
      if (e.key === '/' && !searchExpanded) { e.preventDefault(); setSearchExpanded(true); }
      if (e.key >= '1' && e.key <= '9' && e.metaKey) {
        e.preventDefault();
        setFocusedIndex(Math.min(parseInt(e.key) - 1, items.length - 1));
      }
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [items.length, searchExpanded]);

  // Scroll focused card into view (manual scroll, no scrollIntoView)
  React.useEffect(() => {
    if (scrollRef.current) {
      const container = scrollRef.current;
      const cards = container.children;
      if (cards[focusedIndex]) {
        const card = cards[focusedIndex];
        const cardLeft = card.offsetLeft;
        const cardWidth = card.offsetWidth;
        const containerWidth = container.clientWidth;
        const scrollLeft = container.scrollLeft;
        if (cardLeft < scrollLeft + 40) {
          container.scrollTo({ left: Math.max(0, cardLeft - 40), behavior: 'smooth' });
        } else if (cardLeft + cardWidth > scrollLeft + containerWidth - 40) {
          container.scrollTo({ left: cardLeft + cardWidth - containerWidth + 40, behavior: 'smooth' });
        }
      }
    }
  }, [focusedIndex]);

  const handleHover = (item, e) => {
    clearTimeout(hoverTimer.current);
    hoverTimer.current = setTimeout(() => {
      const rect = e.currentTarget.getBoundingClientRect();
      setHoverItem(item);
      setHoverPos({ x: rect.left + rect.width / 2, y: window.innerHeight - rect.top + 8 });
    }, 400);
  };
  const handleLeave = () => { clearTimeout(hoverTimer.current); setHoverItem(null); };
  const handleContext = (item, e) => {
    setContextItem(item);
    setContextPos({ x: e.clientX, y: e.clientY });
    setHoverItem(null);
  };

  const drawerS = {
    position: 'fixed', bottom: 0, left: 0, right: 0,
    height: 300, zIndex: 9000,
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
    display: 'flex', flexDirection: 'column',
    transform: visible ? 'translateY(0)' : 'translateY(100%)',
    transition: 'transform 0.45s cubic-bezier(0.25, 1, 0.5, 1)',
    fontFamily: FONT,
  };

  const topBarS = {
    display: 'flex', alignItems: 'center', justifyContent: 'space-between',
    padding: '14px 20px 10px', flexShrink: 0, gap: 16,
  };

  const cardAreaS = {
    flex: 1, display: 'flex', gap: 12, alignItems: 'stretch',
    padding: '4px 20px 16px', overflowX: 'auto', overflowY: 'hidden',
    scrollbarWidth: 'none',
  };

  const hintS = {
    font: `500 11px ${FONT}`,
    color: dark ? 'rgba(255,255,255,0.25)' : 'rgba(0,0,0,0.2)',
    display: 'flex', gap: 4, alignItems: 'center', flexShrink: 0,
    letterSpacing: '-0.01em',
  };

  const kbdS = {
    font: `500 10px ${FONT}`, padding: '1px 5px', borderRadius: 4,
    background: dark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.05)',
    border: `0.5px solid ${dark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)'}`,
  };

  return (
    <>
      <div style={drawerS}>
        {/* Top bar: Search | Tabs | Keyboard hint */}
        <div style={topBarS}>
          <DrawerSearch searchQuery={searchQuery} onSearch={setSearchQuery}
            expanded={searchExpanded} onExpand={setSearchExpanded} dark={dark} />

          <DrawerTabBar activeTab={activeTab} onTabChange={setActiveTab} dark={dark} />

          <div style={hintS}>
            <span style={kbdS}>⌘⇧V</span>
            <span>toggle</span>
          </div>
        </div>

        {/* Card strip */}
        <div ref={scrollRef} style={cardAreaS} className="hide-scrollbar">
          {items.length === 0 ? (
            <div style={{
              flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center',
              color: dark ? 'rgba(255,255,255,0.3)' : 'rgba(0,0,0,0.25)',
              font: `500 14px ${FONT}`,
            }}>
              {searchQuery ? `No results for "${searchQuery}"` : 'No items'}
            </div>
          ) : (
            items.map((item, idx) => (
              <ClipboardCard key={item.id} item={item} focused={idx === focusedIndex}
                dark={dark} searchQuery={searchQuery}
                onHover={handleHover} onLeave={handleLeave}
                onContextMenu={handleContext}
                onClick={() => setFocusedIndex(idx)} />
            ))
          )}
        </div>

        {/* Bottom count bar */}
        <div style={{
          padding: '0 20px 10px', display: 'flex', justifyContent: 'space-between',
          color: dark ? 'rgba(255,255,255,0.2)' : 'rgba(0,0,0,0.18)',
          font: `400 11px ${FONT}`, flexShrink: 0,
        }}>
          <span>{items.length} item{items.length !== 1 ? 's' : ''}{searchQuery ? ' matched' : ''}</span>
          <span>⏎ paste · ⌫ delete · / search</span>
        </div>
      </div>

      {/* Hover preview popover */}
      <HoverPreview item={hoverItem} position={hoverPos} dark={dark} />

      {/* Context menu */}
      <ContextMenu item={contextItem} position={contextPos} dark={dark}
        onClose={() => { setContextItem(null); setContextPos(null); }} />
    </>
  );
}

Object.assign(window, {
  BottomDrawer, ClipboardCard, DrawerTabBar, DrawerSearch,
  HoverPreview, ContextMenu, FileIcon,
  CLIPBOARD_ITEMS, SNIPPET_ITEMS,
});
