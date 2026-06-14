#!/usr/bin/env python3
"""从 txt 歌词文件批量生成 songs-data.js"""

import json
import re
import hashlib
from pathlib import Path

TXT_DIR = Path(r"C:\Users\70707\Desktop\sodagreen-lyrics\lrc\output_txt")
OUTPUT = Path(__file__).parent / "songs-data.js"

METADATA_PATTERN = re.compile(
    r"^(作词|作曲|编曲|制作人|词|曲|编|Lyricist|Composer|Arranger|Producer)\s*[:：]",
    re.IGNORECASE,
)

GREEN_PALETTE = [
    ("#1b4332", "#40916c"),
    ("#2d6a4f", "#52b788"),
    ("#344e41", "#588157"),
    ("#006d77", "#83c5be"),
    ("#264653", "#2a9d8f"),
    ("#52796f", "#84a98c"),
    ("#606c38", "#a7c957"),
    ("#1d3557", "#457b9d"),
]


def parse_filename(filename: str) -> tuple[str, str]:
    """从文件名解析歌名与专辑/版本信息。"""
    base = filename
    if base.endswith(".txt"):
        base = base[:-4]
    base = re.sub(r"\s*-\s*苏打绿\s*$", "", base)

    match = re.search(r"\(([^)]+)\)\s*$", base)
    if match:
        album = match.group(1).strip()
    else:
        album = "未知专辑"

    return base.strip(), album


def clean_lyrics(raw: str) -> str:
    lines = raw.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    cleaned = []
    for line in lines:
        stripped = line.strip()
        if not stripped:
            if cleaned and cleaned[-1] != "":
                cleaned.append("")
            continue
        if METADATA_PATTERN.match(stripped):
            continue
        cleaned.append(stripped)

    while cleaned and cleaned[-1] == "":
        cleaned.pop()
    return "\n".join(cleaned)


def pick_colors(key: str) -> list[str]:
    digest = hashlib.md5(key.encode("utf-8")).hexdigest()
    idx = int(digest[:8], 16) % len(GREEN_PALETTE)
    return list(GREEN_PALETTE[idx])


def load_songs() -> list[dict]:
    files = sorted(TXT_DIR.glob("*.txt"))
    if not files:
        raise FileNotFoundError(f"未找到 txt 文件: {TXT_DIR}")

    songs = []
    for i, path in enumerate(files, start=1):
        title, album = parse_filename(path.name)
        lyrics = clean_lyrics(path.read_text(encoding="utf-8"))
        song_id = f"{i:03d}"

        songs.append(
            {
                "id": song_id,
                "title": title,
                "artist": "苏打绿",
                "album": album,
                "cover": "",
                "coverColor": pick_colors(title),
                "lyrics": lyrics,
            }
        )

    return songs


def write_js(songs: list[dict]) -> None:
    payload = json.dumps(songs, ensure_ascii=False, indent=2)
    content = (
        "/**\n"
        " * 苏打绿歌词数据库（自动生成）\n"
        f" * 来源: {TXT_DIR}\n"
        f" * 共 {len(songs)} 首\n"
        " * 重新生成: python import_lyrics.py\n"
        " */\n"
        f"const SONGS_DATA = {payload};\n"
    )
    OUTPUT.write_text(content, encoding="utf-8")


def main() -> None:
    songs = load_songs()
    write_js(songs)
    print(f"已导入 {len(songs)} 首歌曲 -> {OUTPUT}")


if __name__ == "__main__":
    main()
