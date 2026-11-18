const $ = id => document.getElementById(id);

// h('p', {className: 'text'}, 'hello') builds an element; strings become text
// nodes, and null, undefined, false and '' are skipped so `cond && h(...)` works.
function h(tag, props, ...children) {
  const el = Object.assign(document.createElement(tag), props);
  el.append(...children.filter(Boolean));
  return el;
}

async function api(path, method = 'GET', body) {
  const res = await fetch('/api/' + path, { method, body: body && JSON.stringify(body) });
  if (!res.ok) throw new Error(await res.text());
  return res.json();
}

const view = { q: '', kind: '', board: 0, offset: 0, done: false, loading: false };
let boards = [];
let cards = [];

// Place each card in the shortest column, so order reads across the page
// and loading more never moves the cards already shown.
function place(added) {
  const grid = $('grid');
  const n = Math.max(1, Math.floor(grid.clientWidth / 270));
  if (grid.children.length !== n) {
    grid.replaceChildren(...Array.from({ length: n }, () => h('div', { className: 'col' })));
    added = cards;
  }
  for (const c of added) {
    [...grid.children].reduce((a, b) => (b.offsetHeight < a.offsetHeight ? b : a)).append(c);
  }
}
addEventListener('resize', () => place([]));

// ---- posts -----------------------------------------------------------

async function reload() {
  view.offset = 0;
  view.done = false;
  cards = [];
  $('grid').replaceChildren();
  await loadMore();
}

async function loadMore() {
  if (view.done || view.loading) return;
  view.loading = true;
  const { q, kind, board, offset } = view;
  const posts = await api('posts?' + new URLSearchParams({ q, kind, board, offset }));
  view.loading = false;
  if (q !== view.q || kind !== view.kind || board !== view.board) return; // filters changed meanwhile
  view.offset += posts.length;
  view.done = posts.length === 0;
  const added = posts.map(card);
  cards.push(...added);
  place(added);
  const none = view.offset === 0;
  $('empty').hidden = !none;
  if (none) {
    $('empty').textContent = q || kind || board
      ? 'Nothing matches.'
      : 'No saves yet. Press Sync to sign in to X and fetch your bookmarks and likes.';
  }
  // Keep loading until the page is taller than the window.
  if (!view.done && $('more').getBoundingClientRect().top < innerHeight) loadMore();
}

const byline = p => `${p.name} @${p.handle}`;

// One media item at a time, with arrows when a post has several.
function gallery(p) {
  const items = (p.media || []).filter(m => m.file);
  if (!items.length) return null;
  let i = 0;
  const stage = h('div', { className: 'stage' });
  const count = h('span', { className: 'badge' });
  const show = () => {
    const m = items[i], gif = m.type === 'animated_gif';
    stage.replaceChildren(m.type === 'photo'
      ? h('img', { src: '/media/' + m.file, loading: 'lazy', alt: '' })
      : h('video', {
          src: '/media/' + m.file, poster: '/media/' + m.poster, playsInline: true,
          controls: !gif, preload: gif ? 'auto' : 'none', autoplay: gif, loop: gif, muted: gif,
        }));
    count.textContent = `${i + 1} / ${items.length}`;
  };
  const step = by => e => {
    e.stopPropagation();
    i = (i + by + items.length) % items.length;
    show();
  };
  // The first item sets the shape, so stepping through never moves the page.
  const { w, h: height } = items[0];
  if (w && height) stage.style.aspectRatio = `${w} / ${height}`;
  show();
  const many = items.length > 1;
  return h('div', {
      className: 'media',
      // Using a video's controls must not also open the post.
      onclick: e => { if (e.target.closest('video[controls]')) e.stopPropagation(); },
    },
    stage,
    many && h('button', { className: 'step prev', ariaLabel: 'Previous', onclick: step(-1) }, '‹'),
    many && h('button', { className: 'step next', ariaLabel: 'Next', onclick: step(1) }, '›'),
    many && count);
}

function card(p) {
  return h('div', {
      className: 'card', role: 'button', tabIndex: 0,
      onclick: () => openDetail(p),
      onkeydown: e => { if (e.key === 'Enter' && e.target === e.currentTarget) openDetail(p); },
    },
    gallery(p),
    h('div', { className: 'body' },
      p.text && h('p', { className: 'text' }, p.text),
      h('div', { className: 'author' }, byline(p))));
}

// ---- detail ----------------------------------------------------------

function linked(text) {
  return text.split(/(https:\/\/\S+)/).map((part, i) =>
    i % 2 ? h('a', { href: part, onclick: e => { e.preventDefault(); openExternal(part); } }, part) : part);
}

function body(p) {
  return [
    h('div', { className: 'head' },
      h('img', { src: `/media/avatars/${p.authorId}.jpg`, alt: '', onerror: e => e.target.remove() }),
      h('div', { className: 'who' },
        h('div', {}, p.name),
        h('div', { className: 'author' },
          `@${p.handle} · ${p.createdAt ? new Date(p.createdAt).toLocaleDateString() : ''}`)),
      h('button', { onclick: () => openExternal(`https://x.com/${p.handle}/status/${p.id}`) }, 'Open on X')),
    p.text && h('p', { className: 'text' }, ...linked(p.text)),
    gallery(p),
  ];
}

function openDetail(p) {
  const pick = h('div', { className: 'pick' });
  const drawPick = () => pick.replaceChildren(...boards.map(b => {
    const on = (p.boards || []).includes(b.id);
    return h('button', {
      ariaPressed: String(on),
      onclick: async () => {
        await api(`boards/${b.id}/posts/${p.id}`, on ? 'DELETE' : 'PUT');
        p.boards = on ? p.boards.filter(id => id !== b.id) : [...(p.boards || []), b.id];
        drawPick();
        if (view.board === b.id) reload();
      },
    }, b.name);
  }));
  drawPick();
  $('detail').replaceChildren(h('div', {},
    ...body(p),
    p.quoted && h('div', { className: 'quoted' }, ...body(p.quoted)),
    boards.length ? pick : null));
  $('detail').showModal();
  $('detail').scrollTop = 0;
}

$('detail').onclick = e => { if (e.target === $('detail')) $('detail').close(); };
$('detail').onclose = () => $('detail').replaceChildren(); // stops any playing video

// ---- boards ----------------------------------------------------------

async function loadBoards() {
  boards = await api('boards');
  if (!boards.some(b => b.id === view.board)) view.board = 0;
  const add = h('input', {
    placeholder: 'New board', ariaLabel: 'New board name',
    onkeydown: async e => {
      if (e.key !== 'Enter' || !add.value.trim()) return;
      await api('boards', 'POST', { name: add.value.trim() });
      loadBoards();
    },
  });
  $('boards').replaceChildren(
    ...boards.map(b => h('button', {
      ariaPressed: String(view.board === b.id),
      title: 'Right-click to delete',
      onclick: () => { view.board = view.board === b.id ? 0 : b.id; loadBoards(); reload(); },
      oncontextmenu: async e => {
        e.preventDefault();
        if (!confirm(`Delete the board "${b.name}"? Its posts stay saved.`)) return;
        await api('boards/' + b.id, 'DELETE');
        await loadBoards();
        reload();
      },
    }, b.name)),
    add);
}

// ---- filters ---------------------------------------------------------

let typing;
$('search').oninput = () => {
  clearTimeout(typing);
  typing = setTimeout(() => { view.q = $('search').value; reload(); }, 200);
};

$('kinds').onclick = e => {
  if (e.target.dataset.kind == null) return;
  view.kind = e.target.dataset.kind;
  for (const b of $('kinds').children) b.ariaPressed = String(b === e.target);
  reload();
};

new IntersectionObserver(es => es[0].isIntersecting && loadMore()).observe($('more'));

// ---- sync ------------------------------------------------------------

let syncing = false;
async function watchSync() {
  const s = await api('sync');
  const found = s.bookmarks + s.likes;
  $('sync').disabled = s.running;
  $('status').className = s.error ? 'error' : '';
  $('status').textContent = s.error ? s.error
    : !s.running ? (found ? `${found} new` : '')
    : `Syncing… ${found} new` + (s.media ? `, ${s.media} files to download` : '');
  if (s.running) setTimeout(watchSync, 1000);
  else if (syncing) reload(); // new posts, or media that has now downloaded
  syncing = s.running;
}

$('sync').onclick = async () => {
  await api('sync', 'POST');
  watchSync();
};

$('schedule').onchange = async () => {
  try {
    await api('schedule', 'POST', { on: $('schedule').checked });
  } catch (err) {
    $('schedule').checked = !$('schedule').checked;
    $('status').className = 'error';
    $('status').textContent = err.message;
  }
};

api('schedule').then(s => { $('schedule').checked = s.on; });
loadBoards();
reload();
watchSync();
