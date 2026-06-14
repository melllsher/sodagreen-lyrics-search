/**
 * 苏打绿歌词搜索 · 主脚本
 *
 * 数据结构说明（每条歌曲）：
 * {
 *   id: string,        // 唯一标识，建议用 "001" 格式
 *   title: string,     // 歌名
 *   artist: string,    // 歌手（默认苏打绿）
 *   album: string,     // 专辑名称
 *   cover: string,     // 专辑封面 URL，留空则使用占位图
 *   coverColor: string,// 占位图渐变色 [color1, color2]
 *   lyrics: string     // 完整歌词，用 \n 换行
 * }
 *
 * 专辑字段均为「××（苏打绿版）」重制版名称；Live in summer 仅为版本标识
 * 专辑/封面对照见 album-map.json，运行 assign_covers.ps1 更新
 */

// ============================================================
//  歌词数据库框架
// ============================================================

const SongsDB = (() => {
  /** @type {Song[]} */
  let songs = typeof SONGS_DATA !== "undefined" ? [...SONGS_DATA] : [];

  return {
    /** 获取全部歌曲 */
    getAll() {
      return [...songs];
    },

    /** 按 id 查找 */
    getById(id) {
      return songs.find((s) => s.id === id) ?? null;
    },

    /** 按歌名查找（精确） */
    getByTitle(title) {
      return songs.find((s) => s.title === title) ?? null;
    },

    /** 添加歌曲，id 重复则覆盖 */
    add(song) {
      const index = songs.findIndex((s) => s.id === song.id);
      if (index >= 0) {
        songs[index] = { ...song };
      } else {
        songs.push({ ...song });
      }
      return song;
    },

    /** 批量导入 */
    importMany(newSongs) {
      newSongs.forEach((s) => this.add(s));
      return songs.length;
    },

    /** 更新指定 id 的字段 */
    update(id, fields) {
      const index = songs.findIndex((s) => s.id === id);
      if (index < 0) return null;
      songs[index] = { ...songs[index], ...fields };
      return songs[index];
    },

    /** 删除歌曲 */
    remove(id) {
      const before = songs.length;
      songs = songs.filter((s) => s.id !== id);
      return before - songs.length;
    },

    /** 导出 JSON（便于备份或迁移） */
    exportJSON() {
      return JSON.stringify(songs, null, 2);
    },

    /** 从 JSON 字符串加载（会替换现有数据） */
    loadFromJSON(json) {
      const parsed = JSON.parse(json);
      if (!Array.isArray(parsed)) throw new Error("JSON 必须是歌曲数组");
      songs = parsed;
      return songs.length;
    },

    /** 在歌词（及歌名）中搜索关键字，支持单字与多字词组 */
    search(keyword) {
      if (!keyword) return [];
      const lowerKeyword = keyword.toLowerCase();
      const matchesText = (text) =>
        text.includes(keyword) || text.toLowerCase().includes(lowerKeyword);

      return songs
        .filter(
          (song) =>
            matchesText(song.lyrics) ||
            matchesText(song.title) ||
            (song.album && matchesText(song.album))
        )
        .map((song) => {
          let snippet = extractSnippet(song.lyrics, keyword);
          if (snippet.length === 0) {
            const lines = song.lyrics.split("\n").filter((l) => l.trim());
            snippet = lines.slice(0, 3);
          }
          return { song, snippet };
        });
    },
  };
})();

// 暴露到全局，方便在浏览器控制台添加/修改数据
window.SongsDB = SongsDB;

// ============================================================
//  搜索工具函数
// ============================================================

/** 校验关键字 */
function validateKeyword(keyword) {
  const trimmed = keyword.trim();
  if (!trimmed) {
    return { valid: false, message: "请输入搜索关键字" };
  }
  return { valid: true, keyword: trimmed };
}

/** 转义 HTML 特殊字符 */
function escapeHtml(str) {
  return str
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

/** 高亮关键字 */
function highlightKeyword(text, keyword) {
  const escaped = escapeHtml(text);
  if (!keyword) return escaped;

  const parts = escaped.split(new RegExp(`(${escapeRegExp(keyword)})`, "gi"));
  return parts
    .map((part) =>
      part.toLowerCase() === keyword.toLowerCase()
        ? `<mark>${part}</mark>`
        : part
    )
    .join("");
}

function escapeRegExp(str) {
  return str.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/** 编码封面路径，避免中文/空格在移动端请求失败 */
function encodeCoverPath(path) {
  if (!path) return "";
  return path
    .split("/")
    .map((segment, index) => (index === 0 ? segment : encodeURIComponent(segment)))
    .join("/");
}

/**
 * 提取匹配歌词片段（最多 3 行）
 * 优先返回包含关键字的行；若不足 3 行，补充相邻行
 */
function extractSnippet(lyrics, keyword) {
  const lines = lyrics.split("\n").filter((l) => l.trim());
  const matchingIndices = [];

  lines.forEach((line, i) => {
    if (line.includes(keyword) || line.toLowerCase().includes(keyword.toLowerCase())) {
      matchingIndices.push(i);
    }
  });

  if (matchingIndices.length === 0) return [];

  const selected = new Set();
  for (const idx of matchingIndices) {
    selected.add(idx);
    if (selected.size >= 3) break;
  }

  // 若匹配行不足 3 行，尝试添加上下文
  if (selected.size < 3) {
    for (const idx of matchingIndices) {
      if (idx > 0) selected.add(idx - 1);
      if (idx < lines.length - 1) selected.add(idx + 1);
      if (selected.size >= 3) break;
    }
  }

  return [...selected]
    .sort((a, b) => a - b)
    .slice(0, 3)
    .map((i) => lines[i]);
}

/** 生成专辑封面占位 HTML */
function renderCover(song) {
  const [c1, c2] = song.coverColor || ["#2d6a4f", "#52b788"];
  if (song.cover) {
    const src = encodeCoverPath(song.cover);
    return `<img src="${src}" alt="${escapeHtml(song.album)} 封面" loading="lazy" decoding="async">`;
  }
  return `
    <div class="card-cover-placeholder" style="background: linear-gradient(145deg, ${c1}, ${c2});">
      <span class="cover-icon">♪</span>
      <span class="cover-album">${escapeHtml(song.album)}</span>
    </div>`;
}

/** 渲染单张歌曲卡片 */
function renderSongCard({ song, snippet }, keyword) {
  const lyricLines = snippet
    .map((line) => `<span class="lyric-line">${highlightKeyword(line, keyword)}</span>`)
    .join("");

  return `
    <article class="song-card">
      <div class="card-cover">${renderCover(song)}</div>
      <div class="card-body">
        <h3 class="card-title">${escapeHtml(song.title)}</h3>
        <p class="card-album">${escapeHtml(song.album)} · ${escapeHtml(song.artist)}</p>
        <div class="card-lyrics">${lyricLines || "<span class='lyric-line'>—</span>"}</div>
      </div>
    </article>`;
}

// ============================================================
//  UI 交互
// ============================================================

const searchForm = document.getElementById("searchForm");
const searchInput = document.getElementById("searchInput");
const resultsEl = document.getElementById("results");
const statsBar = document.getElementById("statsBar");
const welcomeEl = document.getElementById("welcome");

function showWelcome() {
  statsBar.innerHTML = "";
  resultsEl.innerHTML = "";
  resultsEl.appendChild(welcomeEl);
  welcomeEl.style.display = "";
}

function showError(message) {
  statsBar.innerHTML = "";
  resultsEl.innerHTML = `<div class="error-state"><p>${escapeHtml(message)}</p></div>`;
}

function showEmpty(keyword) {
  statsBar.innerHTML = `未找到包含「<strong>${escapeHtml(keyword)}</strong>」的歌曲`;
  resultsEl.innerHTML = `
    <div class="empty-state">
      <p>没有找到匹配的歌词，试试其他关键字吧。</p>
    </div>`;
}

function showResults(keyword, matches) {
  statsBar.innerHTML = `找到 <strong>${matches.length}</strong> 首包含「<strong>${escapeHtml(keyword)}</strong>」的歌曲`;
  resultsEl.innerHTML = `
    <div class="results-grid">
      ${matches.map((m) => renderSongCard(m, keyword)).join("")}
    </div>`;
}

function performSearch(rawKeyword) {
  const validation = validateKeyword(rawKeyword);
  if (!validation.valid) {
    showError(validation.message);
    return;
  }

  const { keyword } = validation;
  searchInput.value = keyword;

  const matches = SongsDB.search(keyword);

  if (matches.length === 0) {
    showEmpty(keyword);
  } else {
    showResults(keyword, matches);
  }
}

// 表单提交
searchForm.addEventListener("submit", (e) => {
  e.preventDefault();
  performSearch(searchInput.value);
});

// 示例关键字快捷搜索
document.querySelectorAll(".keyword-chip").forEach((chip) => {
  chip.addEventListener("click", () => {
    const keyword = chip.dataset.keyword;
    searchInput.value = keyword;
    performSearch(keyword);
  });
});

// 初始化
showWelcome();
